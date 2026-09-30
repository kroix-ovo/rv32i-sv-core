`timescale 1ns/1ps
package rv32i_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum int {EV_IMEM, EV_DMEM, EV_RETIRE, EV_TRAP} rv_event_kind;
  class rv32i_event extends uvm_sequence_item;
    rv_event_kind kind;
    logic [31:0] addr, instruction, wdata, rdata, cause, tval;
    logic [3:0] wstrb;
    bit write, error;
    int wait_cycles;
    `uvm_object_utils(rv32i_event)
    function new(string name="rv32i_event"); super.new(name); endfunction
  endclass

  // One item describes how the memory slave answers one core request. The
  // request itself comes from the DUT; a sequence never drives a core address.
  class rv32i_response_item extends uvm_sequence_item;
    int unsigned wait_cycles, epoch;
    bit fault_enable;
    logic [31:0] fault_addr;
    `uvm_object_utils(rv32i_response_item)
    function new(string name="rv32i_response_item"); super.new(name); endfunction
  endclass

  class rv32i_response_sequencer extends uvm_sequencer#(rv32i_response_item);
    int unsigned active_epoch;
    `uvm_component_utils(rv32i_response_sequencer)
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
  endclass

  // A responder stays one item ahead at most: finish_item waits until the
  // driver completes or cancels the corresponding memory transfer.
  class rv32i_response_sequence extends uvm_sequence#(rv32i_response_item);
    int unsigned state, epoch;
    int fixed_delay=-1;
    int max_delay=3;
    bit fault_enable;
    logic [31:0] fault_addr;
    `uvm_object_utils(rv32i_response_sequence)
    function new(string name="rv32i_response_sequence"); super.new(name); endfunction
    function int unsigned next_delay();
      state=(state*32'd1664525)+32'd1013904223;
      return (state & 32'h7fffffff) % (max_delay+1);
    endfunction
    task body();
      rv32i_response_item item;
      forever begin
        item=rv32i_response_item::type_id::create("response_item");
        start_item(item);
        item.wait_cycles=(fixed_delay>=0) ? fixed_delay : next_delay();
        item.fault_enable=fault_enable;
        item.fault_addr=fault_addr;
        item.epoch=epoch;
        finish_item(item);
      end
    endtask
  endclass

  // Separate from the architectural model so a memory-driver mistake cannot
  // automatically become the scoreboard's expected result.
  class rv32i_memory extends uvm_object;
    logic [7:0] bytes[0:4095];
    logic [31:0] words[0:1023];
    `uvm_object_utils(rv32i_memory)
    function new(string name="rv32i_memory"); super.new(name); clear(); endfunction
    function void clear();
      for (int i=0;i<4096;i++) bytes[i]=0;
    endfunction
    function void load_hex(string path);
      for (int i=0;i<1024;i++) words[i]=32'h00000013;
      $readmemh(path,words);
      for (int i=0;i<1024;i++)
        for (int lane=0;lane<4;lane++) bytes[i*4+lane]=words[i][lane*8 +: 8];
    endfunction
    function void put_word(int unsigned addr, logic [31:0] word);
      for (int lane=0;lane<4;lane++) bytes[addr+lane]=word[lane*8 +: 8];
    endfunction
    function logic [31:0] read_word(logic [31:0] addr);
      logic [31:0] value;
      value=0;
      if (addr+4>4096) return 0;
      for (int lane=0;lane<4;lane++) value[lane*8 +: 8]=bytes[addr+lane];
      return value;
    endfunction
    function void store(logic [31:0] addr, logic [31:0] data,
                        logic [3:0] strobes);
      logic [31:0] base;
      base=addr & 32'hffff_fffc;
      if (base+4>4096) return;
      for (int lane=0;lane<4;lane++)
        if (strobes[lane]) bytes[base+lane]=data[lane*8 +: 8];
    endfunction
  endclass

  `include "rv32i_ref_model.svh"

  class rv32i_mem_driver extends uvm_driver#(rv32i_response_item);
    virtual rv32i_core_if vif;
    rv32i_memory memory;
    rv32i_response_sequencer sequencer;
    rv32i_response_item response;
    bit is_data, pending;
    logic [31:0] held_addr, held_wdata;
    logic [3:0] held_wstrb;
    bit held_write;
    int delay_left, request_count, aborted_items;
    `uvm_component_utils(rv32i_mem_driver)
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rv32i_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NO_VIF","memory driver has no core interface")
      if (!uvm_config_db#(rv32i_memory)::get(this,"","memory",memory))
        `uvm_fatal("NO_MEM","memory driver has no shared memory")
      if (!uvm_config_db#(bit)::get(this,"","is_data",is_data)) is_data=0;
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        @(negedge vif.clk);
        if (!vif.rst_n) begin
          if (response!=null) begin
            seq_item_port.item_done();
            response=null;
            aborted_items++;
          end
          pending=0; request_count=0;
          if (is_data) begin
            vif.drive_cb.dmem_ready <= 0;
            vif.drive_cb.dmem_error <= 0;
            vif.drive_cb.dmem_rdata <= 0;
          end else begin
            vif.drive_cb.imem_ready <= 0;
            vif.drive_cb.imem_error <= 0;
            vif.drive_cb.imem_rdata <= 0;
          end
        end else if (is_data) begin
          vif.drive_cb.dmem_ready <= 0;
          vif.drive_cb.dmem_error <= 0;
          if (!pending && vif.dmem_valid) begin
            pending=1; held_addr=vif.dmem_addr;
            held_write=vif.dmem_write; held_wdata=vif.dmem_wdata;
            held_wstrb=vif.dmem_wstrb;
          end
          if (pending) begin
            if (response==null) begin
              seq_item_port.try_next_item(response);
              if (response!=null) begin
                if (response.epoch!=sequencer.active_epoch)
                  `uvm_error("STALE_RESPONSE","data response belongs to an earlier scenario")
                delay_left=response.wait_cycles;
              end
            end
            if (response!=null) begin
              if (delay_left>0) delay_left--;
              else begin
                vif.drive_cb.dmem_ready <= 1;
                vif.drive_cb.dmem_error <= (held_addr>=4096) ||
                    (response.fault_enable && held_addr==response.fault_addr);
                vif.drive_cb.dmem_rdata <= memory.read_word(held_addr & 32'hffff_fffc);
              end
            end
          end
        end else begin
          vif.drive_cb.imem_ready <= 0;
          vif.drive_cb.imem_error <= 0;
          if (!pending && vif.imem_valid) begin
            pending=1; held_addr=vif.imem_addr;
          end
          if (pending) begin
            if (response==null) begin
              seq_item_port.try_next_item(response);
              if (response!=null) begin
                if (response.epoch!=sequencer.active_epoch)
                  `uvm_error("STALE_RESPONSE","instruction response belongs to an earlier scenario")
                delay_left=response.wait_cycles;
              end
            end
            if (response!=null) begin
              if (delay_left>0) delay_left--;
              else begin
                vif.drive_cb.imem_ready <= 1;
                vif.drive_cb.imem_error <= (held_addr>=4096) ||
                    (response.fault_enable && held_addr==response.fault_addr);
                vif.drive_cb.imem_rdata <= memory.read_word(held_addr);
              end
            end
          end
        end
        @(posedge vif.clk);
        if (vif.rst_n && pending) begin
          if (is_data && vif.dmem_valid && vif.dmem_ready) begin
            if (held_write && !vif.dmem_error)
              memory.store(held_addr,held_wdata,held_wstrb);
            pending=0; request_count++;
            seq_item_port.item_done(); response=null;
          end
          if (!is_data && vif.imem_valid && vif.imem_ready) begin
            pending=0; request_count++;
            seq_item_port.item_done(); response=null;
          end
        end
      end
    endtask
  endclass

  class rv32i_mem_monitor extends uvm_monitor;
    virtual rv32i_core_if vif;
    bit is_data, stalled;
    logic [31:0] held_addr, held_wdata;
    logic [3:0] held_wstrb;
    bit held_write;
    int wait_count;
    uvm_analysis_port#(rv32i_event) ap;
    `uvm_component_utils(rv32i_mem_monitor)
    function new(string name,uvm_component parent);
      super.new(name,parent); ap=new("ap",this);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rv32i_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NO_VIF","memory monitor has no core interface")
      if (!uvm_config_db#(bit)::get(this,"","is_data",is_data)) is_data=0;
    endfunction
    task run_phase(uvm_phase phase);
      rv32i_event event_item;
      bit valid_now, ready_now;
      logic [31:0] addr_now, wdata_now, rdata_now;
      logic [3:0] wstrb_now;
      bit write_now, error_now;
      forever begin
        @(posedge vif.clk);
        if (!vif.rst_n) begin stalled=0; wait_count=0; continue; end
        valid_now=is_data ? vif.dmem_valid : vif.imem_valid;
        ready_now=is_data ? vif.dmem_ready : vif.imem_ready;
        addr_now=is_data ? vif.dmem_addr : vif.imem_addr;
        wdata_now=is_data ? vif.dmem_wdata : 0;
        wstrb_now=is_data ? vif.dmem_wstrb : 0;
        write_now=is_data ? vif.dmem_write : 0;
        rdata_now=is_data ? vif.dmem_rdata : vif.imem_rdata;
        error_now=is_data ? vif.dmem_error : vif.imem_error;
        if (stalled && (!valid_now || addr_now!==held_addr ||
            (is_data && {write_now,wdata_now,wstrb_now} !==
                        {held_write,held_wdata,held_wstrb})))
          `uvm_error("UNSTABLE","request changed or withdrew before ready")
        if (is_data && valid_now && write_now && wstrb_now==0)
          `uvm_error("WSTRB","store has no active byte lane")
        if (!is_data && valid_now && addr_now[1:0]!=0)
          `uvm_error("I_ALIGN","instruction fetch is not word aligned")
        if (valid_now && ready_now) begin
          event_item=rv32i_event::type_id::create("bus_event");
          event_item.kind=is_data ? EV_DMEM : EV_IMEM;
          event_item.addr=addr_now; event_item.write=write_now;
          event_item.wdata=wdata_now; event_item.wstrb=wstrb_now;
          event_item.rdata=rdata_now; event_item.error=error_now;
          event_item.wait_cycles=wait_count;
          ap.write(event_item);
          stalled=0; wait_count=0;
        end else if (valid_now) begin
          if (!stalled) begin
            held_addr=addr_now; held_write=write_now;
            held_wdata=wdata_now; held_wstrb=wstrb_now;
          end
          stalled=1; wait_count++;
        end
      end
    endtask
  endclass

  class rv32i_mem_agent extends uvm_agent;
    rv32i_mem_driver driver;
    rv32i_mem_monitor monitor;
    rv32i_response_sequencer sequencer;
    `uvm_component_utils(rv32i_mem_agent)
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      driver=rv32i_mem_driver::type_id::create("driver",this);
      monitor=rv32i_mem_monitor::type_id::create("monitor",this);
      sequencer=rv32i_response_sequencer::type_id::create("sequencer",this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
      driver.sequencer=sequencer;
    endfunction
  endclass

  class rv32i_retire_monitor extends uvm_monitor;
    virtual rv32i_core_if vif;
    uvm_analysis_port#(rv32i_event) ap;
    bit trap_seen;
    logic [31:0] held_cause, held_pc, held_tval;
    `uvm_component_utils(rv32i_retire_monitor)
    function new(string name,uvm_component parent);
      super.new(name,parent); ap=new("ap",this);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rv32i_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NO_VIF","retirement monitor has no core interface")
    endfunction
    task run_phase(uvm_phase phase);
      rv32i_event item;
      forever begin
        @(posedge vif.clk);
        if (!vif.rst_n) begin trap_seen=0; continue; end
        if (vif.imem_valid && vif.dmem_valid)
          `uvm_error("DUAL_REQ","instruction and data requests overlap")
        if (trap_seen && (!vif.trap_valid || vif.retire_valid ||
            vif.imem_valid || vif.dmem_valid ||
            {vif.trap_cause,vif.trap_pc,vif.trap_tval} !==
            {held_cause,held_pc,held_tval}))
          `uvm_error("TRAP_STICKY","trapped core changed or issued work")
        if (vif.retire_valid) begin
          item=rv32i_event::type_id::create("retire_event");
          item.kind=EV_RETIRE; item.addr=vif.retire_pc;
          item.instruction=vif.retire_instruction;
          ap.write(item);
        end
        if (vif.trap_valid && !trap_seen) begin
          item=rv32i_event::type_id::create("trap_event");
          item.kind=EV_TRAP; item.addr=vif.trap_pc;
          item.cause=vif.trap_cause; item.tval=vif.trap_tval;
          ap.write(item);
          held_cause=vif.trap_cause;
          held_pc=vif.trap_pc;
          held_tval=vif.trap_tval;
        end
        trap_seen=vif.trap_valid;
      end
    endtask
  endclass

  `include "rv32i_scoreboard.svh"

  // Coordinates the two reactive slave sequencers and the existing scenario
  // state. No driver is connected to this virtual sequencer.
  class rv32i_virtual_sequencer extends uvm_sequencer#(uvm_sequence_item);
    virtual rv32i_core_if vif;
    rv32i_memory memory;
    rv32i_scoreboard scoreboard;
    rv32i_response_sequencer imem_sqr, dmem_sqr;
    rv32i_mem_driver imem_driver, dmem_driver;
    `uvm_component_utils(rv32i_virtual_sequencer)
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rv32i_core_if)::get(this,"","vif",vif))
        `uvm_fatal("NO_VIF","virtual sequencer has no core interface")
    endfunction
  endclass

  class rv32i_uvm_env extends uvm_env;
    rv32i_memory memory;
    rv32i_mem_agent imem, dmem;
    rv32i_retire_monitor retirement;
    rv32i_scoreboard scoreboard;
    rv32i_virtual_sequencer virtual_sequencer;
    `uvm_component_utils(rv32i_uvm_env)
    function new(string name,uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      memory=rv32i_memory::type_id::create("memory");
      uvm_config_db#(rv32i_memory)::set(this,"*","memory",memory);
      uvm_config_db#(bit)::set(this,"imem.*","is_data",0);
      uvm_config_db#(bit)::set(this,"dmem.*","is_data",1);
      imem=rv32i_mem_agent::type_id::create("imem",this);
      dmem=rv32i_mem_agent::type_id::create("dmem",this);
      retirement=rv32i_retire_monitor::type_id::create("retirement",this);
      scoreboard=rv32i_scoreboard::type_id::create("scoreboard",this);
      virtual_sequencer=rv32i_virtual_sequencer::type_id::create("virtual_sequencer",this);
    endfunction
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      imem.monitor.ap.connect(scoreboard.analysis_export);
      dmem.monitor.ap.connect(scoreboard.analysis_export);
      retirement.ap.connect(scoreboard.analysis_export);
      virtual_sequencer.imem_sqr=imem.sequencer;
      virtual_sequencer.dmem_sqr=dmem.sequencer;
      virtual_sequencer.imem_driver=imem.driver;
      virtual_sequencer.dmem_driver=dmem.driver;
      virtual_sequencer.memory=memory;
      virtual_sequencer.scoreboard=scoreboard;
    endfunction
  endclass

  `include "rv32i_tests.svh"
endpackage

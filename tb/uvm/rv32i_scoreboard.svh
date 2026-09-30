// Analysis-port scoreboard. Bus and retirement events sampled on a rising edge
// are processed together at the next falling edge, independent of monitor order.
class rv32i_scoreboard extends uvm_scoreboard;
  covergroup instruction_cg with function sample(logic [6:0] op);
    opcode: coverpoint op {
      bins lui={7'h37}; bins auipc={7'h17}; bins jal={7'h6f};
      bins jalr={7'h67}; bins branch={7'h63}; bins load={7'h03};
      bins store={7'h23}; bins immediate={7'h13};
      bins register_op={7'h33}; bins fence={7'h0f};
    }
  endgroup
  covergroup trap_cg with function sample(int cause);
    trap_cause: coverpoint cause {
      bins align_instruction={0}; bins access_instruction={1};
      bins illegal={2}; bins breakpoint={3};
      bins align_load={4}; bins access_load={5};
      bins align_store={6}; bins access_store={7}; bins ecall={11};
    }
  endgroup
  covergroup wait_cg with function sample(int port_id,int bucket);
    port: coverpoint port_id { bins instruction={0}; bins data={1}; }
    delay: coverpoint bucket { bins immediate={0}; bins one={1};
                               bins two={2}; bins three_plus={3}; }
    port_delay: cross port,delay;
  endgroup
  covergroup branch_cg with function sample(bit taken);
    outcome: coverpoint taken { bins not_taken={0}; bins taken={1}; }
  endgroup
  covergroup load_cg with function sample(int variant);
    width_sign: coverpoint variant { bins lb={0}; bins lh={1};
      bins lw={2}; bins lbu={3}; bins lhu={4}; }
  endgroup
  covergroup store_cg with function sample(int width_code);
    width: coverpoint width_code { bins sb={0}; bins sh={1}; bins sw={2}; }
  endgroup
  virtual rv32i_core_if vif;
  rv32i_memory memory;
  rv32i_ref_model reference;
  uvm_analysis_imp#(rv32i_event,rv32i_scoreboard) analysis_export;
  rv32i_event incoming[$], data_done[$];
  bit expect_trap, trapped;
  bit fetch_error_seen;
  logic [31:0] fetch_error_addr;
  logic [31:0] want_cause, want_pc, want_tval;
  int observed_retirements, observed_traps;
  int opcode_bins[0:127], load_bins[0:5], store_bins[0:2];
  int trap_bins[0:11], branch_bins[0:1], wait_bins[0:1][0:3];
  int raw_bins, load_use_bins, raw_stall_cycles, load_use_stall_cycles;
  int interlock_cycles, memory_wait_cycles;
  bit prev_writes, prev_load;
  logic [4:0] prev_rd;
  `uvm_component_utils(rv32i_scoreboard)
  function new(string name,uvm_component parent);
    super.new(name,parent);
    analysis_export=new("analysis_export",this);
    reference=new();
    instruction_cg=new(); trap_cg=new(); wait_cg=new();
    branch_cg=new(); load_cg=new(); store_cg=new();
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual rv32i_core_if)::get(this,"","vif",vif))
      `uvm_fatal("NO_VIF","scoreboard has no core interface")
    if (!uvm_config_db#(rv32i_memory)::get(this,"","memory",memory))
      `uvm_fatal("NO_MEM","scoreboard has no shared memory")
  endfunction
  function void write(rv32i_event item); incoming.push_back(item); endfunction
  function void begin_scenario(bit should_trap=0, logic [31:0] cause=0,
                               logic [31:0] pc=0, logic [31:0] tval=0);
    incoming.delete(); data_done.delete(); reference.reset_from(memory);
    expect_trap=should_trap; want_cause=cause; want_pc=pc; want_tval=tval;
    trapped=0; observed_retirements=0; observed_traps=0;
    fetch_error_seen=0; fetch_error_addr=0;
    prev_writes=0; prev_load=0; prev_rd=0;
  endfunction
  function void process_bus(rv32i_event item);
    int port_index, bucket;
    port_index=(item.kind==EV_DMEM);
    bucket=(item.wait_cycles>=3) ? 3 : item.wait_cycles;
    wait_bins[port_index][bucket]++;
    wait_cg.sample(port_index,bucket);
    if (item.kind==EV_DMEM) data_done.push_back(item);
    if (item.kind==EV_IMEM && item.error) begin
      fetch_error_seen=1; fetch_error_addr=item.addr;
    end
  endfunction
  function void process_retire(rv32i_event item);
    rv32i_event expected, actual;
    string problem;
    logic [31:0] old_pc;
    logic [6:0] op;
    logic [2:0] f3;
    bit uses_rs1, uses_rs2, writes_rd;
    if (trapped) `uvm_error("LATE_RETIRE","instruction retired after trap")
    if (item.addr !== reference.pc ||
        item.instruction !== reference.read_data(reference.pc,4))
      `uvm_error("RETIRE",$sformatf("got pc=%08x insn=%08x expected pc=%08x insn=%08x",
        item.addr,item.instruction,reference.pc,
        reference.read_data(reference.pc,4)))
    old_pc=reference.pc;
    if (!reference.step(item.instruction,expected,problem))
      `uvm_error("REF_MODEL",$sformatf("pc=%08x: %s",old_pc,problem))
    if (expected!=null) begin
      if (data_done.size()==0) `uvm_error("NO_DMEM","memory instruction retired without handshake")
      else begin
        actual=data_done.pop_front();
        if (actual.error || actual.addr!==expected.addr ||
            actual.write!==expected.write || actual.wstrb!==expected.wstrb)
          `uvm_error("DMEM",$sformatf("bad transfer at retired pc=%08x",old_pc))
        if (expected.write) begin
          for (int lane=0;lane<4;lane++)
            if (expected.wstrb[lane] &&
                actual.wdata[lane*8 +: 8] !== expected.wdata[lane*8 +: 8])
              `uvm_error("STORE_DATA",$sformatf("bad store lane %0d at pc=%08x",lane,old_pc))
        end else if (actual.rdata!==expected.rdata)
          `uvm_error("LOAD_DATA",$sformatf("bad load word at pc=%08x",old_pc))
      end
    end
    observed_retirements++;
    op=item.instruction[6:0]; f3=item.instruction[14:12];
    opcode_bins[op]++;
    instruction_cg.sample(op);
    if (op==7'h63) begin
      branch_bins[reference.pc!=old_pc+4]++;
      branch_cg.sample(reference.pc!=old_pc+4);
    end
    if (op==7'h03) begin
      case (f3)
        0:load_bins[0]++; 1:load_bins[1]++; 2:load_bins[2]++;
        4:load_bins[3]++; 5:load_bins[4]++;
      endcase
      case (f3)
        0:load_cg.sample(0); 1:load_cg.sample(1); 2:load_cg.sample(2);
        4:load_cg.sample(3); 5:load_cg.sample(4);
      endcase
    end
    if (op==7'h23 && f3<=2) begin
      store_bins[f3]++;
      store_cg.sample(f3);
    end
    uses_rs1=(op inside {7'h67,7'h03,7'h13,7'h63,7'h23,7'h33});
    uses_rs2=(op inside {7'h63,7'h23,7'h33});
    if (prev_writes && prev_rd!=0 &&
        ((uses_rs1 && item.instruction[19:15]==prev_rd) ||
         (uses_rs2 && item.instruction[24:20]==prev_rd))) begin
      raw_bins++;
      if (prev_load) load_use_bins++;
    end
    writes_rd=(op inside {7'h37,7'h17,7'h6f,7'h67,7'h03,7'h13,7'h33});
    prev_writes=writes_rd; prev_load=(op==7'h03);
    prev_rd=item.instruction[11:7];
  endfunction
  function void process_trap(rv32i_event item);
    rv32i_event actual;
    observed_traps++; trapped=1;
    if (!expect_trap || item.cause!==want_cause || item.addr!==want_pc ||
        item.tval!==want_tval)
      `uvm_error("TRAP",$sformatf("got %0d/%08x/%08x expected %0d/%08x/%08x",
        item.cause,item.addr,item.tval,want_cause,want_pc,want_tval))
    if (item.cause<=11) trap_bins[item.cause]++;
    trap_cg.sample(item.cause);
    if (item.cause==1 && (!fetch_error_seen || fetch_error_addr!==item.addr))
      `uvm_error("FAULT_BUS","instruction access fault lacked matching error response")
    if (item.cause==5 || item.cause==7) begin
      if (data_done.size()==0)
        `uvm_error("FAULT_BUS","data access fault lacked a bus response")
      else begin
        actual=data_done.pop_front();
        if (!actual.error || actual.addr!==item.tval ||
            actual.write!==(item.cause==7))
          `uvm_error("FAULT_BUS","data access fault response mismatch")
      end
    end
    if (data_done.size()!=0)
      `uvm_error("EXTRA_BUS","unmatched data transfer at trap")
  endfunction
  task run_phase(uvm_phase phase);
    rv32i_event item;
    rv32i_event retired[$], traps[$];
    forever begin
      @(negedge vif.clk);
      if (vif.rst_n) begin
        if (vif.debug_state==1) interlock_cycles++;
        if (vif.debug_state==2) memory_wait_cycles++;
        if (vif.raw_stall) raw_stall_cycles++;
        if (vif.load_use_stall) load_use_stall_cycles++;
      end
      while (incoming.size()!=0) begin
        item=incoming.pop_front();
        case (item.kind)
          EV_IMEM,EV_DMEM: process_bus(item);
          EV_RETIRE: retired.push_back(item);
          EV_TRAP: traps.push_back(item);
        endcase
      end
      while (retired.size()!=0) process_retire(retired.pop_front());
      while (traps.size()!=0) process_trap(traps.pop_front());
    end
  endtask
  function void report_coverage();
    int required_ops[0:9]='{7'h37,7'h17,7'h6f,7'h67,7'h63,
                              7'h03,7'h23,7'h13,7'h33,7'h0f};
    int required_traps[0:8]='{0,1,2,3,4,5,6,7,11};
    for (int i=0;i<10;i++) if (opcode_bins[required_ops[i]]==0)
      `uvm_error("COVERAGE",$sformatf("missing opcode %02x",required_ops[i]))
    for (int i=0;i<5;i++) if (load_bins[i]==0)
      `uvm_error("COVERAGE",$sformatf("missing load variant %0d",i))
    for (int i=0;i<3;i++) if (store_bins[i]==0)
      `uvm_error("COVERAGE",$sformatf("missing store width %0d",i))
    for (int i=0;i<9;i++) if (trap_bins[required_traps[i]]==0)
      `uvm_error("COVERAGE",$sformatf("missing trap cause %0d",required_traps[i]))
    for (int i=0;i<2;i++) begin
      if (branch_bins[i]==0)
        `uvm_error("COVERAGE",$sformatf("missing branch outcome %0d",i))
      if (wait_bins[i][0]==0 ||
          (wait_bins[i][1]+wait_bins[i][2]+wait_bins[i][3])==0)
        `uvm_error("COVERAGE",$sformatf("port %0d lacks immediate or delayed response",i))
    end
    // This core pauses fetch while a load is in flight, so adjacent load-use
    // instructions are serialized rather than producing a load-use ID stall.
    if (raw_bins==0 || load_use_bins==0 || raw_stall_cycles==0 ||
        interlock_cycles==0 || memory_wait_cycles==0)
      `uvm_error("COVERAGE","missing RAW stall, load-use dependency, or memory wait")
    for (int i=0;i<10;i++)
      `uvm_info("COVERAGE",$sformatf("opcode %02x count=%0d",required_ops[i],opcode_bins[required_ops[i]]),UVM_LOW)
    for (int i=0;i<5;i++)
      `uvm_info("COVERAGE",$sformatf("load variant %0d count=%0d",i,load_bins[i]),UVM_LOW)
    for (int i=0;i<3;i++)
      `uvm_info("COVERAGE",$sformatf("store width %0d count=%0d",i,store_bins[i]),UVM_LOW)
    for (int i=0;i<9;i++)
      `uvm_info("COVERAGE",$sformatf("trap cause %0d count=%0d",required_traps[i],trap_bins[required_traps[i]]),UVM_LOW)
    for (int i=0;i<2;i++)
      `uvm_info("COVERAGE",$sformatf("port %0d waits 0/1/2/3+ = %0d/%0d/%0d/%0d; branch outcome %0d=%0d",
        i,wait_bins[i][0],wait_bins[i][1],wait_bins[i][2],wait_bins[i][3],i,branch_bins[i]),UVM_LOW)
    `uvm_info("COVERAGE",$sformatf("retire dependencies: RAW=%0d load-use=%0d; observed stall cycles: RAW=%0d load-use=%0d memory=%0d (load-use is serialized by fetch)",
       raw_bins,load_use_bins,raw_stall_cycles,load_use_stall_cycles,memory_wait_cycles),UVM_LOW)
  endfunction
endclass

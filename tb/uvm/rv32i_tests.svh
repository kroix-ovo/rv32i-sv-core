// One suite keeps functional coverage across reset-separated scenarios while
// checking every case against fresh, independent memory/model state.
class rv32i_uvm_test extends uvm_test;
  virtual rv32i_core_if vif;
  rv32i_uvm_env env;
  int unsigned random_seed;
  string directed_hex;
  `uvm_component_utils(rv32i_uvm_test)
  function new(string name,uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env=rv32i_uvm_env::type_id::create("env",this);
    if (!uvm_config_db#(virtual rv32i_core_if)::get(this,"","vif",vif))
      `uvm_fatal("NO_VIF","test has no core interface")
    directed_hex="directed.hex";
    random_seed=1325;
    begin
      int seed_file, parsed;
      seed_file=$fopen("seed.txt","r");
      if (seed_file!=0) begin
        parsed=$fscanf(seed_file,"%d",random_seed);
        $fclose(seed_file);
        if (parsed!=1) `uvm_fatal("SEED","seed.txt must contain one decimal seed")
      end
    end
    uvm_config_db#(int)::set(this,"env.imem.driver","seed",random_seed ^ 32'h1a2b3c4d);
    uvm_config_db#(int)::set(this,"env.dmem.driver","seed",random_seed ^ 32'h5e6f7081);
  endfunction
  function logic [31:0] addi(int rd,int rs1,int imm);
    return {imm[11:0],rs1[4:0],3'b000,rd[4:0],7'h13};
  endfunction
  function logic [31:0] rtype(int rd,int rs1,int rs2,int funct3,int funct7=0);
    return {funct7[6:0],rs2[4:0],rs1[4:0],funct3[2:0],rd[4:0],7'h33};
  endfunction
  function logic [31:0] load_insn(int rd,int rs1,int imm,int funct3);
    return {imm[11:0],rs1[4:0],funct3[2:0],rd[4:0],7'h03};
  endfunction
  function logic [31:0] store_insn(int rs2,int rs1,int imm,int funct3);
    return {imm[11:5],rs2[4:0],rs1[4:0],funct3[2:0],imm[4:0],7'h23};
  endfunction
  function logic [31:0] branch_insn(int rs1,int rs2,int offset,int funct3);
    return {offset[12],offset[10:5],rs2[4:0],rs1[4:0],
            funct3[2:0],offset[4:1],offset[11],7'h63};
  endfunction
  function int unsigned next_random();
    random_seed=(random_seed*32'd1664525)+32'd1013904223;
    return random_seed & 32'h7fffffff;
  endfunction
  task automatic start_case(string label,bit should_trap=0,
                            logic [31:0] cause=0,logic [31:0] pc=0,
                            logic [31:0] tval=0);
    vif.rst_n=0;
    repeat (4) @(posedge vif.clk);
    @(negedge vif.clk);
    env.scoreboard.begin_scenario(should_trap,cause,pc,tval);
    vif.rst_n=1;
    `uvm_info("CASE",$sformatf("start %s",label),UVM_LOW)
  endtask
  task automatic wait_trap(string label,int limit=200);
    bit seen;
    seen=0;
    for (int cycle=0;cycle<limit;cycle++) begin
      @(posedge vif.clk); #1;
      if (env.scoreboard.trapped) begin seen=1; break; end
    end
    if (!seen) `uvm_fatal("TIMEOUT",$sformatf("%s: no trap, debug PC=%08x",label,vif.debug_pc))
    if (env.scoreboard.observed_traps!=1)
      `uvm_error("TRAP_COUNT",$sformatf("%s: observed %0d traps",label,
                   env.scoreboard.observed_traps))
    repeat (4) @(posedge vif.clk);
    `uvm_info("CASE",$sformatf("pass %s",label),UVM_LOW)
  endtask
  task automatic run_directed();
    bit seen;
    env.memory.clear(); env.memory.load_hex(directed_hex);
    start_case("directed RV32I program");
    seen=0;
    for (int cycle=0;cycle<20000;cycle++) begin
      @(posedge vif.clk); #1;
      if (vif.trap_valid) `uvm_fatal("DIRECTED_TRAP","unexpected directed-program trap")
      if (env.memory.read_word(32'h900)==32'hbad00001)
        `uvm_fatal("FAIL_SIGNATURE","directed program entered failure path")
      if (env.memory.read_word(32'h900)==32'h600d600d) begin
        seen=1; break;
      end
    end
    if (!seen) `uvm_fatal("TIMEOUT","directed program did not produce pass signature")
    repeat (5) @(posedge vif.clk);
    if (env.scoreboard.observed_retirements<100)
      `uvm_error("RETIRE_COUNT","directed program retired fewer than 100 instructions")
    if (env.scoreboard.data_done.size()!=0)
      `uvm_error("EXTRA_BUS","directed program left unmatched data transfers")
    `uvm_info("CASE",$sformatf("pass directed: %0d retirements",
       env.scoreboard.observed_retirements),UVM_LOW)
    vif.rst_n=0;
  endtask
  task automatic run_hazards();
    env.memory.clear();
    env.memory.put_word(0,addi(1,0,256));
    env.memory.put_word(4,addi(2,0,7));
    env.memory.put_word(8,addi(3,0,11));
    env.memory.put_word(12,rtype(4,2,3,0));
    env.memory.put_word(16,store_insn(4,1,0,2));
    env.memory.put_word(20,load_insn(5,1,0,2));
    env.memory.put_word(24,addi(6,5,1));
    env.memory.put_word(28,branch_insn(6,6,8,0));
    env.memory.put_word(32,addi(7,0,99));
    env.memory.put_word(36,addi(7,0,42));
    env.memory.put_word(40,32'h00100073);
    start_case("hazards and taken branch",1,3,40,0);
    wait_trap("hazards and taken branch",600);
    if (env.scoreboard.reference.regs[4]!==18 ||
        env.scoreboard.reference.regs[5]!==18 ||
        env.scoreboard.reference.regs[6]!==19 ||
        env.scoreboard.reference.regs[7]!==42 ||
        env.memory.read_word(256)!==18)
      `uvm_error("HAZARD_RESULT","RAW/load-use/branch result mismatch")
  endtask
  task automatic run_one_trap(string label,logic [31:0] first,
                              logic [31:0] second,bit has_second,
                              logic [31:0] cause,logic [31:0] pc,
                              logic [31:0] tval);
    env.memory.clear();
    for (int i=0;i<256;i++) env.memory.put_word(i*4,32'h00000013);
    env.memory.put_word(0,first);
    if (has_second) env.memory.put_word(4,second);
    start_case(label,1,cause,pc,tval);
    wait_trap(label,250);
  endtask
  task automatic run_traps();
    run_one_trap("illegal",32'hffffffff,0,0,2,0,32'hffffffff);
    run_one_trap("ecall",32'h00000073,0,0,11,0,0);
    run_one_trap("ebreak",32'h00100073,0,0,3,0,0);
    run_one_trap("jump alignment",32'h0020006f,0,0,0,0,2);
    run_one_trap("load alignment",addi(1,0,1),32'h0000a103,1,4,4,1);
    run_one_trap("store alignment",addi(1,0,1),32'h0020a023,1,6,4,1);
    run_one_trap("load access",32'h000020b7,32'h0000a103,1,5,4,32'h2000);
    run_one_trap("store access",32'h000020b7,32'h0020a023,1,7,4,32'h2000);
    run_one_trap("fetch access",32'h0000206f,0,0,1,32'h2000,32'h2000);
  endtask
  task automatic run_injected_faults();
    env.memory.clear();
    env.memory.put_word(0,addi(1,0,256));
    env.memory.put_word(4,load_insn(2,1,0,2));
    env.memory.dfault_enable=1; env.memory.dfault_addr=256;
    start_case("injected load fault",1,5,4,256);
    wait_trap("injected load fault");

    env.memory.clear();
    env.memory.put_word(0,addi(1,0,256));
    env.memory.put_word(4,store_insn(0,1,0,2));
    env.memory.dfault_enable=1; env.memory.dfault_addr=256;
    start_case("injected store fault",1,7,4,256);
    wait_trap("injected store fault");

    env.memory.clear();
    env.memory.put_word(0,addi(1,0,1));
    env.memory.put_word(4,addi(2,0,2));
    env.memory.ifault_enable=1; env.memory.ifault_addr=4;
    start_case("injected instruction fault",1,1,4,4);
    wait_trap("injected instruction fault");
  endtask
  task automatic run_reset();
    env.memory.clear();
    env.memory.put_word(0,addi(1,0,7));
    env.memory.put_word(4,addi(2,1,1));
    env.memory.put_word(8,32'h00100073);
    env.imem.driver.max_delay=3;
    start_case("reset during outstanding work");
    for (int cycle=0;cycle<50;cycle++) begin
      @(posedge vif.clk); #1;
      if (vif.imem_valid && !vif.imem_ready) break;
    end
    vif.rst_n=0;
    repeat (4) @(posedge vif.clk);
    start_case("restart after reset",1,3,8,0);
    wait_trap("restart after reset",150);
    if (env.scoreboard.reference.regs[2]!==8)
      `uvm_error("RESET_RESULT","program did not restart from reset PC")
  endtask
  task automatic run_random(int case_index);
    int unsigned initial_seed;
    int choice;
    initial_seed=random_seed;
    `uvm_info("RANDOM",$sformatf("case=%0d seed=%08x",case_index,initial_seed),UVM_LOW)
    env.memory.clear();
    env.memory.put_word(0,addi(1,0,256));
    env.memory.put_word(4,addi(2,0,next_random()%256));
    env.memory.put_word(8,addi(3,0,next_random()%256));
    for (int i=0;i<24;i++) begin
      choice=next_random()%4;
      case (choice)
        0: env.memory.put_word(12+i*4,addi(2,2,(next_random()%127)-63));
        1: env.memory.put_word(12+i*4,rtype(2,2,3,4)); // XOR
        2: env.memory.put_word(12+i*4,rtype(3,2,3,0)); // ADD
        3: env.memory.put_word(12+i*4,rtype(3,3,2,7)); // AND
      endcase
    end
    env.memory.put_word(108,store_insn(2,1,0,2));
    env.memory.put_word(112,load_insn(4,1,0,2));
    env.memory.put_word(116,addi(5,4,1));
    env.memory.put_word(120,branch_insn(5,5,8,0));
    env.memory.put_word(124,addi(6,0,99));
    env.memory.put_word(128,store_insn(5,1,4,2));
    env.memory.put_word(132,32'h00100073);
    start_case($sformatf("random %0d",case_index),1,3,132,0);
    wait_trap($sformatf("random %0d",case_index),1200);
    if (env.memory.read_word(256)!==env.scoreboard.reference.read_data(256,4) ||
        env.memory.read_word(260)!==env.scoreboard.reference.read_data(260,4))
      `uvm_error("RANDOM_RESULT",$sformatf("case=%0d seed=%08x",case_index,initial_seed))
  endtask
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("SEED",$sformatf("RV_SEED=%0d",random_seed),UVM_LOW)
    run_directed();
    run_hazards();
    run_traps();
    run_injected_faults();
    run_reset();
    for (int i=0;i<8;i++) run_random(i);
    env.scoreboard.report_coverage();
    if (uvm_report_server::get_server().get_severity_count(UVM_ERROR)==0 &&
        uvm_report_server::get_server().get_severity_count(UVM_FATAL)==0)
      `uvm_info("RV32I_UVM_PASS","all core UVM scenarios and coverage completed",UVM_NONE)
    phase.drop_objection(this);
  endtask
endclass

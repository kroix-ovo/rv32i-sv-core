// Independent, architectural RV32I interpreter. It sees retired instructions
// and its own memory image; it does not call the RTL decoder or read registers.
class rv32i_ref_model;
  logic [7:0] bytes[0:4095];
  logic [31:0] regs[0:31];
  logic [31:0] pc;
  int retired;

  function void reset_from(rv32i_memory source);
    for (int i = 0; i < 4096; i++) bytes[i] = source.bytes[i];
    for (int i = 0; i < 32; i++) regs[i] = 0;
    pc = 0;
    retired = 0;
  endfunction

  function logic [31:0] sext(logic [31:0] value, int width);
    logic signed [31:0] shifted;
    shifted = value << (32-width);
    return shifted >>> (32-width);
  endfunction

  function logic [31:0] read_data(logic [31:0] addr, int size);
    logic [31:0] value;
    value = 0;
    if (addr + size > 4096) return 0;
    for (int i = 0; i < size; i++) value[i*8 +: 8] = bytes[addr+i];
    return value;
  endfunction

  function void write_data(logic [31:0] addr, int size, logic [31:0] value);
    if (addr + size > 4096) return;
    for (int i = 0; i < size; i++) bytes[addr+i] = value[i*8 +: 8];
  endfunction

  // On a successful retirement, produce the bus transfer that instruction
  // must have completed, if any. Faulting instructions never enter here.
  function bit step(logic [31:0] insn, output rv32i_event expected_bus,
                    output string problem);
    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    int unsigned rd, rs1, rs2, size;
    logic [31:0] a, b, imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [31:0] next_pc, result, addr, value, shifted;
    bit writes, take, unsigned_load;
    expected_bus = null;
    problem = "";
    opcode = insn[6:0]; funct3 = insn[14:12]; funct7 = insn[31:25];
    rd = insn[11:7]; rs1 = insn[19:15]; rs2 = insn[24:20];
    a = regs[rs1]; b = regs[rs2];
    next_pc = pc + 4; result = 0; writes = 0;
    imm_i = sext({20'b0,insn[31:20]},12);
    imm_s = sext({20'b0,insn[31:25],insn[11:7]},12);
    imm_b = sext({19'b0,insn[31],insn[7],insn[30:25],insn[11:8],1'b0},13);
    imm_u = {insn[31:12],12'b0};
    imm_j = sext({11'b0,insn[31],insn[19:12],insn[20],insn[30:21],1'b0},21);
    case (opcode)
      7'h37: begin result = imm_u; writes = 1; end
      7'h17: begin result = pc + imm_u; writes = 1; end
      7'h6f: begin result = pc + 4; writes = 1; next_pc = pc + imm_j; end
      7'h67: begin
        if (funct3 != 0) begin problem = "invalid JALR"; return 0; end
        result = pc + 4; writes = 1; next_pc = (a + imm_i) & 32'hffff_fffe;
      end
      7'h63: begin
        case (funct3)
          0: take = a == b; 1: take = a != b;
          4: take = $signed(a) < $signed(b);
          5: take = $signed(a) >= $signed(b);
          6: take = a < b; 7: take = a >= b;
          default: begin problem = "invalid branch"; return 0; end
        endcase
        if (take) next_pc = pc + imm_b;
      end
      7'h03: begin
        case (funct3)
          0,4: size = 1; 1,5: size = 2; 2: size = 4;
          default: begin problem = "invalid load"; return 0; end
        endcase
        addr = a + imm_i;
        if ((addr & (size-1)) || addr + size > 4096) begin
          problem = "retired faulting load"; return 0;
        end
        expected_bus = rv32i_event::type_id::create("expected_load");
        expected_bus.kind = EV_DMEM; expected_bus.addr = addr;
        expected_bus.write = 0; expected_bus.wstrb = 0;
        expected_bus.rdata = read_data(addr & 32'hffff_fffc,4);
        value = read_data(addr,size);
        unsigned_load = funct3[2];
        result = unsigned_load ? value : sext(value,size*8);
        writes = 1;
      end
      7'h23: begin
        case (funct3)
          0: size = 1; 1: size = 2; 2: size = 4;
          default: begin problem = "invalid store"; return 0; end
        endcase
        addr = a + imm_s;
        if ((addr & (size-1)) || addr + size > 4096) begin
          problem = "retired faulting store"; return 0;
        end
        expected_bus = rv32i_event::type_id::create("expected_store");
        expected_bus.kind = EV_DMEM; expected_bus.addr = addr;
        expected_bus.write = 1;
        expected_bus.wstrb = ((1 << size)-1) << addr[1:0];
        expected_bus.wdata = b << (addr[1:0]*8);
        write_data(addr,size,b);
      end
      7'h13: begin
        writes = 1;
        case (funct3)
          0: result = a + imm_i;
          2: result = $signed(a) < $signed(imm_i);
          3: result = a < imm_i;
          4: result = a ^ imm_i;
          6: result = a | imm_i;
          7: result = a & imm_i;
          1: if (funct7 == 0) result = a << insn[24:20];
             else begin problem = "invalid SLLI"; return 0; end
          5: if (funct7 == 0) result = a >> insn[24:20];
             else if (funct7 == 7'h20) result = $signed(a) >>> insn[24:20];
             else begin problem = "invalid right shift"; return 0; end
        endcase
      end
      7'h33: begin
        writes = 1;
        case ({funct7,funct3})
          {7'h00,3'h0}: result = a + b;
          {7'h20,3'h0}: result = a - b;
          {7'h00,3'h1}: result = a << b[4:0];
          {7'h00,3'h2}: result = $signed(a) < $signed(b);
          {7'h00,3'h3}: result = a < b;
          {7'h00,3'h4}: result = a ^ b;
          {7'h00,3'h5}: result = a >> b[4:0];
          {7'h20,3'h5}: result = $signed(a) >>> b[4:0];
          {7'h00,3'h6}: result = a | b;
          {7'h00,3'h7}: result = a & b;
          default: begin problem = "invalid register ALU"; return 0; end
        endcase
      end
      7'h0f: begin
        if (funct3 != 0) begin problem = "invalid FENCE"; return 0; end
      end
      default: begin problem = "illegal instruction retired"; return 0; end
    endcase
    if (writes && rd != 0) regs[rd] = result;
    regs[0] = 0;
    pc = next_pc;
    retired++;
    return 1;
  endfunction
endclass

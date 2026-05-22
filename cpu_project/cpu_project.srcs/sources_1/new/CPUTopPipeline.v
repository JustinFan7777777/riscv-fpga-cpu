// =============================================================================
// Module      : CPUTopPipeline.v
// Description : RISC-V RV32I 五级流水线 CPU (IF→ID→EX→MEM→WB)
// =============================================================================
// 复用模块: Decoder, RegFile, ImmGen, ALU, DataMemory
// 新增模块: Ifetch_Pipe, PipeRegs, HazardUnit
//
// 冒险处理: RAW转发(EX/MEM,MEM/WB→EX), Load-Use stall, 分支flush IF/ID
// 注: 本版本为pipeline演示, JAL/JALR链接地址(PC+4→rd)待后续完善
// =============================================================================
`timescale 1ns / 1ps

module CPUTopPipeline (
    input         clk, rst_n, cpu_halt, cpu_step, cpu_reset,
    input  [4:0]  dbg_reg_addr,
    output [31:0] dbg_reg_data,
    input         inst_dbg_en, inst_wr_en,
    input  [31:0] inst_dbg_addr, inst_wr_data,
    output [31:0] inst_rd_data,
    input         dmem_dbg_en, dmem_wr_en,
    input  [31:0] dmem_dbg_addr, dmem_wr_data,
    output [31:0] dmem_rd_data,
    output [31:0] dbg_pc,
    input  [15:0] SwitchIn,
    input  [4:0]  ButtonIn,
    output [15:0] LEDOut,
    output [7:0]  seg_cs, seg_data_0, seg_data_1,
    input         clk_vga,
    input  [11:0] vga_fb_addr,
    output [15:0] vga_fb_data
);

    wire cpu_halt_effective = cpu_halt & ~cpu_step;

    // ========================================================================
    // 所有内部信号声明 (必须在模块实例化之前)
    // ========================================================================
    // IF
    wire [31:0] if_pc, if_inst, if_pcplus4;
    wire        stall, flush, ctrl_flush;
    wire        ex_branch_taken, ex_jump, ex_jalrsrc;
    wire [31:0] ex_branch_target, ex_jump_target, ex_jalr_target;

    // ID
    wire [31:0] id_pc, id_pcplus4, id_inst;
    wire        id_regwrite, id_alusrc, id_memtoreg, id_memwrite;
    wire        id_branch, id_jump, id_jalrsrc;
    wire [1:0]  id_aluop; wire [3:0] id_alucontrol; wire [2:0] id_funct3;
    wire [31:0] id_rs1_val, id_rs2_val, id_imm;
    wire [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;

    // EX
    wire [31:0] ex_pc, ex_pcplus4, ex_rs1_val, ex_rs2_val, ex_imm;
    wire [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire        ex_regwrite, ex_alusrc, ex_memtoreg, ex_memwrite;
    wire        ex_branch, ex_jump_wire, ex_jalrsrc_wire;
    wire [3:0]  ex_alucontrol; wire [2:0] ex_funct3;
    wire [31:0] ex_aluresult, ex_writedata;
    wire [1:0]  forward_a, forward_b;

    // MEM
    wire [31:0] mem_aluresult, mem_writedata, mem_branchtarget, mem_readdata;
    wire [4:0]  mem_rd_addr;
    wire        mem_regwrite, mem_memtoreg, mem_memwrite;
    wire        mem_branch, mem_jump, mem_branch_taken;

    // WB
    wire [31:0] wb_readdata, wb_aluresult, wb_wd3;
    wire [4:0]  wb_rd_addr;
    wire        wb_regwrite, wb_memtoreg;

    // ========================================================================
    // IF — 取指 (Ifetch_Pipe: BRAM寄存器读)
    // ========================================================================

    Ifetch_Pipe uIfetch (
        .clk(clk), .rst_n(rst_n), .stall(stall | cpu_halt_effective),
        .flush(flush), .branch_taken(ex_branch_taken),
        .jump(ex_jump), .jalrsrc(ex_jalrsrc),
        .branch_target(ex_branch_target), .jump_target(ex_jump_target),
        .jalr_target(ex_jalr_target),
        .pc(if_pc), .inst(if_inst), .pcplus4(if_pcplus4),
        .inst_dbg_en(inst_dbg_en), .inst_wr_en(inst_wr_en),
        .inst_dbg_addr(inst_dbg_addr), .inst_wr_data(inst_wr_data),
        .inst_rd_data(inst_rd_data)
    );
    assign dbg_pc = if_pc;

    // ========================================================================
    // ID — 译码 + 寄存器读 + 立即数生成
    // ========================================================================

    Decoder uDecoder (
        .inst(id_inst), .RegWrite(id_regwrite), .ALUSrc(id_alusrc),
        .MemtoReg(id_memtoreg), .MemWrite(id_memwrite),
        .Branch(id_branch), .Jump(id_jump), .JALRSrc(id_jalrsrc),
        .ALUOp(id_aluop), .ALUControl(id_alucontrol)
    );
    assign id_funct3 = id_inst[14:12];

    assign id_rs1_addr = id_inst[19:15];
    assign id_rs2_addr = id_inst[24:20];
    assign id_rd_addr  = id_inst[11:7];

    RegFile uRegFile (
        .clk(clk), .rst_n(rst_n), .RegWrite(wb_regwrite),
        .rs1_addr(id_rs1_addr), .rs2_addr(id_rs2_addr),
        .rd_addr(wb_rd_addr), .WD3(wb_wd3),
        .rs1_val(id_rs1_val), .rs2_val(id_rs2_val),
        .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(dbg_reg_data)
    );

    ImmGen uImmGen (.inst(id_inst), .Imm(id_imm));

    // ========================================================================
    // PipeRegs — 4组流水线寄存器
    // ========================================================================
    PipeRegs uPipeRegs (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush(flush),
        // IF → IF/ID
        .if_pc(if_pc), .if_pcplus4(if_pcplus4), .if_inst(if_inst),
        // ID → ID/EX
        .id_pc(id_pc), .id_pcplus4(id_pcplus4), .id_rs1_val(id_rs1_val),
        .id_rs2_val(id_rs2_val), .id_imm(id_imm),
        .id_rs1_addr(id_rs1_addr), .id_rs2_addr(id_rs2_addr), .id_rd_addr(id_rd_addr),
        .id_regwrite(id_regwrite), .id_alusrc(id_alusrc), .id_memtoreg(id_memtoreg),
        .id_memwrite(id_memwrite), .id_branch(id_branch), .id_jump(id_jump),
        .id_jalrsrc(id_jalrsrc), .id_alucontrol(id_alucontrol), .id_funct3(id_funct3),
        // EX → EX/MEM
        .ex_aluresult(ex_aluresult), .ex_writedata(ex_writedata),
        .ex_branchtarget(ex_branch_target), .ex_rd_addr(ex_rd_addr),
        .ex_regwrite(ex_regwrite), .ex_memtoreg(ex_memtoreg), .ex_memwrite(ex_memwrite),
        .ex_branch(ex_branch), .ex_jump(ex_jump), .ex_branch_taken(ex_branch_taken),
        // MEM → MEM/WB
        .mem_readdata(mem_readdata), .mem_aluresult(mem_aluresult),
        .mem_rd_addr(mem_rd_addr), .mem_regwrite(mem_regwrite), .mem_memtoreg(mem_memtoreg),
        // IF/ID → ID
        .id_o_pc(id_pc), .id_o_pcplus4(id_pcplus4), .id_o_inst(id_inst),
        // ID/EX → EX
        .ex_o_pc(ex_pc), .ex_o_pcplus4(ex_pcplus4), .ex_o_rs1_val(ex_rs1_val),
        .ex_o_rs2_val(ex_rs2_val), .ex_o_imm(ex_imm),
        .ex_o_rs1_addr(ex_rs1_addr), .ex_o_rs2_addr(ex_rs2_addr), .ex_o_rd_addr(ex_rd_addr),
        .ex_o_regwrite(ex_regwrite), .ex_o_alusrc(ex_alusrc), .ex_o_memtoreg(ex_memtoreg),
        .ex_o_memwrite(ex_memwrite), .ex_o_branch(ex_branch), .ex_o_jump(ex_jump_wire),
        .ex_o_jalrsrc(ex_jalrsrc_wire), .ex_o_alucontrol(ex_alucontrol), .ex_o_funct3(ex_funct3),
        // EX/MEM → MEM
        .mem_o_aluresult(mem_aluresult), .mem_o_writedata(mem_writedata),
        .mem_o_branchtarget(mem_branchtarget), .mem_o_rd_addr(mem_rd_addr),
        .mem_o_regwrite(mem_regwrite), .mem_o_memtoreg(mem_memtoreg),
        .mem_o_memwrite(mem_memwrite), .mem_o_branch(mem_branch),
        .mem_o_jump(mem_jump), .mem_o_branch_taken(mem_branch_taken),
        // MEM/WB → WB
        .wb_o_readdata(wb_readdata), .wb_o_aluresult(wb_aluresult),
        .wb_o_rd_addr(wb_rd_addr), .wb_o_regwrite(wb_regwrite), .wb_o_memtoreg(wb_memtoreg)
    );

    // ========================================================================
    // Hazard Unit — 转发 + Load-Use
    // ========================================================================

    HazardUnit uHazard (
        .id_rs1_addr(id_rs1_addr), .id_rs2_addr(id_rs2_addr),
        .idex_rs1_addr(ex_rs1_addr), .idex_rs2_addr(ex_rs2_addr),
        .idex_rd_addr(ex_rd_addr), .idex_memread(ex_memtoreg),
        .exmem_rd_addr(mem_rd_addr), .exmem_regwrite(mem_regwrite),
        .memwb_rd_addr(wb_rd_addr), .memwb_regwrite(wb_regwrite),
        .ctrl_flush(ctrl_flush),
        .forward_a(forward_a), .forward_b(forward_b),
        .stall(stall), .flush(flush)
    );

    // ========================================================================
    // EX — ALU + 分支/跳转
    // ========================================================================
    // ALU A: 转发MUX (来自EX/MEM或MEM/WB)
    wire [31:0] ex_alu_a_fwd;
    assign ex_alu_a_fwd = (forward_a == 2'b01) ? mem_aluresult :
                          (forward_a == 2'b10) ? wb_wd3 : ex_rs1_val;
    wire [31:0] ex_alu_a = ex_alu_a_fwd;

    // ALU B: 转发MUX + ALUSrc选择
    wire [31:0] ex_alu_b_fwd;
    assign ex_alu_b_fwd = (forward_b == 2'b01) ? mem_aluresult :
                          (forward_b == 2'b10) ? wb_wd3 : ex_rs2_val;
    wire [31:0] ex_alu_b = ex_alusrc ? ex_imm : ex_alu_b_fwd;

    ALU uALU (.A(ex_alu_a), .B(ex_alu_b), .ALUControl(ex_alucontrol),
              .ALUResult(ex_aluresult), .Zero());

    // 分支/跳转目标
    assign ex_branch_target = ex_pc + ex_imm;
    assign ex_jump_target   = ex_pc + ex_imm;
    wire [31:0] ex_jalr_sum = ex_alu_a + ex_imm;  // rs1(forwarded) + imm
    assign ex_jalr_target   = {ex_jalr_sum[31:1], 1'b0};

    // 分支条件
    assign ex_branch_taken = ex_branch && (
        (ex_funct3 == 3'b000) ? (ex_alu_a_fwd == ex_alu_b_fwd) :
        (ex_funct3 == 3'b001) ? (ex_alu_a_fwd != ex_alu_b_fwd) :
        (ex_funct3 == 3'b100) ? ($signed(ex_alu_a_fwd) < $signed(ex_alu_b_fwd)) :
        (ex_funct3 == 3'b101) ? ($signed(ex_alu_a_fwd) >= $signed(ex_alu_b_fwd)) :
        (ex_funct3 == 3'b110) ? (ex_alu_a_fwd < ex_alu_b_fwd) :
        (ex_funct3 == 3'b111) ? (ex_alu_a_fwd >= ex_alu_b_fwd) :
        1'b0);

    assign ex_jump      = ex_jump_wire;
    assign ex_jalrsrc   = ex_jalrsrc_wire;
    assign ctrl_flush   = ex_branch_taken | ex_jump_wire | ex_jalrsrc_wire;

    // 写数据 (rs2 forwarded, for stores)
    assign ex_writedata = ex_alu_b_fwd;

    // ========================================================================
    // MEM — 数据内存
    // ========================================================================
    DataMemory uDataMemory (
        .clk(clk), .rst_n(rst_n), .clk_vga(clk_vga),
        .MemWrite(mem_memwrite), .Addr(mem_aluresult),
        .WriteData(mem_writedata), .ReadData(mem_readdata),
        .SwitchIn(SwitchIn), .ButtonIn(ButtonIn),
        .LEDOut(LEDOut), .seg_cs(seg_cs),
        .seg_data_0(seg_data_0), .seg_data_1(seg_data_1),
        .dmem_dbg_en(dmem_dbg_en), .dmem_wr_en(dmem_wr_en),
        .dmem_dbg_addr(dmem_dbg_addr), .dmem_wr_data(dmem_wr_data),
        .dmem_rd_data(dmem_rd_data),
        .vga_fb_addr(vga_fb_addr), .vga_fb_data(vga_fb_data)
    );

    // ========================================================================
    // WB — 写回
    // ========================================================================
    assign wb_wd3 = wb_memtoreg ? wb_readdata : wb_aluresult;

endmodule

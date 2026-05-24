// =============================================================================
// Module      : PipeRegs.v
// Description : 五级流水线寄存器组 (IF/ID, ID/EX, EX/MEM, MEM/WB)
// =============================================================================
// 每个流水线寄存器在 clk 上升沿锁存上一级的输出, 包含数据信号和控制信号。
// stall=1 时冻结 IF/ID (Load-Use), flush_ifid=1 时清零 IF/ID (分支/跳转),
// flush_idex=1 时清零 ID/EX 插入气泡 (Load-Use 或 分支/跳转)。
// =============================================================================
`timescale 1ns / 1ps

module PipeRegs (
    input         clk, rst_n,
    input         stall,       // 1=冻结IF/ID + PC (Load-Use)
    input         flush_ifid,  // 1=清零IF/ID (分支/跳转, 清除错误取指)
    input         flush_idex,  // 1=清零ID/EX (插入气泡: Load-Use或分支/跳转)

    // IF 阶段输出 → IF/ID 输入
    input  [31:0] if_pc, if_pcplus4, if_inst,

    // ID 阶段输出 → ID/EX 输入
    input  [31:0] id_pc, id_pcplus4, id_rs1_val, id_rs2_val, id_imm,
    input  [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr,
    input         id_regwrite, id_alusrc, id_memtoreg, id_memwrite,
    input         id_branch, id_jump, id_jalrsrc,
    input  [3:0]  id_alucontrol,
    input  [2:0]  id_funct3,        // funct3 (用于EX阶段分支判断)
    input         id_lui,           // 1=LUI 指令 (ALU_A=0)
    input         id_auipc,         // 1=AUIPC 指令 (ALU_A=PC)

    // EX 阶段输出 → EX/MEM 输入
    input  [31:0] ex_aluresult, ex_writedata,
    input  [4:0]  ex_rd_addr,
    input         ex_regwrite, ex_memtoreg, ex_memwrite,

    // MEM 阶段输出 → MEM/WB 输入
    input  [31:0] mem_readdata, mem_aluresult,
    input  [4:0]  mem_rd_addr,
    input         mem_regwrite, mem_memtoreg,

    // ==== IF/ID 输出 (ID 阶段用) ====
    output [31:0] id_o_pc, id_o_pcplus4, id_o_inst,

    // ==== ID/EX 输出 (EX 阶段用) ====
    output [31:0] ex_o_pc, ex_o_pcplus4, ex_o_rs1_val, ex_o_rs2_val, ex_o_imm,
    output [4:0]  ex_o_rs1_addr, ex_o_rs2_addr, ex_o_rd_addr,
    output        ex_o_regwrite, ex_o_alusrc, ex_o_memtoreg, ex_o_memwrite,
    output        ex_o_branch, ex_o_jump, ex_o_jalrsrc,
    output [3:0]  ex_o_alucontrol,
    output [2:0]  ex_o_funct3,        // funct3 (用于EX分支判断)
    output        ex_o_lui,           // 1=LUI 指令
    output        ex_o_auipc,         // 1=AUIPC 指令

    // ==== EX/MEM 输出 (MEM 阶段用) ====
    output [31:0] mem_o_aluresult, mem_o_writedata,
    output [4:0]  mem_o_rd_addr,
    output        mem_o_regwrite, mem_o_memtoreg, mem_o_memwrite,

    // ==== MEM/WB 输出 (WB 阶段用) ====
    output [31:0] wb_o_readdata, wb_o_aluresult,
    output [4:0]  wb_o_rd_addr,
    output        wb_o_regwrite, wb_o_memtoreg
);

    // ========================================================================
    // IF/ID 寄存器
    // ========================================================================
    reg [31:0] ifid_pc, ifid_pcplus4, ifid_inst;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ifid_pc      <= 32'd0;
            ifid_pcplus4 <= 32'd0;
            ifid_inst    <= 32'd0;  // NOP after flush
        end else begin
            if (flush_ifid) begin
                ifid_inst    <= 32'd0;  // NOP (all zeros → default case in decoder)
                ifid_pc      <= 32'd0;
                ifid_pcplus4 <= 32'd0;
            end else if (!stall) begin
                ifid_pc      <= if_pc;
                ifid_pcplus4 <= if_pcplus4;
                ifid_inst    <= if_inst;
            end
        end
    end

    assign id_o_pc      = ifid_pc;
    assign id_o_pcplus4 = ifid_pcplus4;
    assign id_o_inst    = ifid_inst;

    // ========================================================================
    // ID/EX 寄存器
    // ========================================================================
    reg [31:0] idex_pc, idex_pcplus4, idex_rs1_val, idex_rs2_val, idex_imm;
    reg [4:0]  idex_rs1_addr, idex_rs2_addr, idex_rd_addr;
    reg        idex_regwrite, idex_alusrc, idex_memtoreg, idex_memwrite;
    reg        idex_branch, idex_jump, idex_jalrsrc;
    reg [3:0]  idex_alucontrol;
    reg [2:0]  idex_funct3;
    reg        idex_lui, idex_auipc;  // LUI/AUIPC 标志

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_idex) begin
            // 复位或插入气泡: 清零所有控制信号 (等效 NOP)
            idex_pc        <= 32'd0;
            idex_pcplus4   <= 32'd0;
            idex_rs1_val   <= 32'd0;
            idex_rs2_val   <= 32'd0;
            idex_imm       <= 32'd0;
            idex_rs1_addr  <= 5'd0;
            idex_rs2_addr  <= 5'd0;
            idex_rd_addr   <= 5'd0;
            idex_regwrite  <= 1'b0;
            idex_alusrc    <= 1'b0;
            idex_memtoreg  <= 1'b0;
            idex_memwrite  <= 1'b0;
            idex_branch    <= 1'b0;
            idex_jump      <= 1'b0;
            idex_jalrsrc   <= 1'b0;
            idex_alucontrol <= 4'd0;
            idex_funct3    <= 3'd0;
            idex_lui       <= 1'b0;
            idex_auipc     <= 1'b0;
        end else begin
            idex_pc        <= id_pc;
            idex_pcplus4   <= id_pcplus4;
            idex_rs1_val   <= id_rs1_val;
            idex_rs2_val   <= id_rs2_val;
            idex_imm       <= id_imm;
            idex_rs1_addr  <= id_rs1_addr;
            idex_rs2_addr  <= id_rs2_addr;
            idex_rd_addr   <= id_rd_addr;
            idex_regwrite  <= id_regwrite;
            idex_alusrc    <= id_alusrc;
            idex_memtoreg  <= id_memtoreg;
            idex_memwrite  <= id_memwrite;
            idex_branch    <= id_branch;
            idex_jump      <= id_jump;
            idex_jalrsrc   <= id_jalrsrc;
            idex_alucontrol <= id_alucontrol;
            idex_funct3    <= id_funct3;
            idex_lui       <= id_lui;
            idex_auipc     <= id_auipc;
        end
    end

    assign ex_o_pc         = idex_pc;
    assign ex_o_pcplus4    = idex_pcplus4;
    assign ex_o_rs1_val    = idex_rs1_val;
    assign ex_o_rs2_val    = idex_rs2_val;
    assign ex_o_imm        = idex_imm;
    assign ex_o_rs1_addr   = idex_rs1_addr;
    assign ex_o_rs2_addr   = idex_rs2_addr;
    assign ex_o_rd_addr    = idex_rd_addr;
    assign ex_o_regwrite   = idex_regwrite;
    assign ex_o_alusrc     = idex_alusrc;
    assign ex_o_memtoreg   = idex_memtoreg;
    assign ex_o_memwrite   = idex_memwrite;
    assign ex_o_branch     = idex_branch;
    assign ex_o_jump       = idex_jump;
    assign ex_o_jalrsrc    = idex_jalrsrc;
    assign ex_o_alucontrol = idex_alucontrol;
    assign ex_o_funct3     = idex_funct3;
    assign ex_o_lui        = idex_lui;
    assign ex_o_auipc      = idex_auipc;

    // ========================================================================
    // EX/MEM 寄存器
    // ========================================================================
    reg [31:0] exmem_aluresult, exmem_writedata;
    reg [4:0]  exmem_rd_addr;
    reg        exmem_regwrite, exmem_memtoreg, exmem_memwrite;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exmem_aluresult <= 32'd0;
            exmem_writedata <= 32'd0;
            exmem_rd_addr   <= 5'd0;
            exmem_regwrite  <= 1'b0;
            exmem_memtoreg  <= 1'b0;
            exmem_memwrite  <= 1'b0;
        end else begin
            exmem_aluresult <= ex_aluresult;
            exmem_writedata <= ex_writedata;
            exmem_rd_addr   <= ex_rd_addr;
            exmem_regwrite  <= ex_regwrite;
            exmem_memtoreg  <= ex_memtoreg;
            exmem_memwrite  <= ex_memwrite;
        end
    end

    assign mem_o_aluresult = exmem_aluresult;
    assign mem_o_writedata = exmem_writedata;
    assign mem_o_rd_addr   = exmem_rd_addr;
    assign mem_o_regwrite  = exmem_regwrite;
    assign mem_o_memtoreg  = exmem_memtoreg;
    assign mem_o_memwrite  = exmem_memwrite;

    // ========================================================================
    // MEM/WB 寄存器
    // ========================================================================
    reg [31:0] memwb_readdata, memwb_aluresult;
    reg [4:0]  memwb_rd_addr;
    reg        memwb_regwrite, memwb_memtoreg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memwb_readdata  <= 32'd0;
            memwb_aluresult <= 32'd0;
            memwb_rd_addr   <= 5'd0;
            memwb_regwrite  <= 1'b0;
            memwb_memtoreg  <= 1'b0;
        end else begin
            memwb_readdata  <= mem_readdata;
            memwb_aluresult <= mem_aluresult;
            memwb_rd_addr   <= mem_rd_addr;
            memwb_regwrite  <= mem_regwrite;
            memwb_memtoreg  <= mem_memtoreg;
        end
    end

    assign wb_o_readdata  = memwb_readdata;
    assign wb_o_aluresult = memwb_aluresult;
    assign wb_o_rd_addr   = memwb_rd_addr;
    assign wb_o_regwrite  = memwb_regwrite;
    assign wb_o_memtoreg  = memwb_memtoreg;

endmodule

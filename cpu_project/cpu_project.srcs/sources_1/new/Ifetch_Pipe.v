// =============================================================================
// Module      : Ifetch_Pipe.v
// Description : 流水线版取指模块 — PC + IMem (分布式RAM, 组合读, 零延迟)
// =============================================================================
// 与 BRAM 寄存器读版本的关键区别:
//   1. IMem 使用分布式 RAM (ram_style="distributed") + 组合读, 零周期延迟
//   2. 单一 PC 寄存器, 无需 pc_reg/pc_prev 对齐机制
//   3. 无需 flush_ifid 输入 — 流水线 flush 由 PipeRegs 层处理
//   4. PC 更新优先级: stall > branch/jump taken > PC+4
// =============================================================================
`timescale 1ns / 1ps

module Ifetch_Pipe #(
    parameter INIT_FILE = "../../../../assembly/batch_test.hex"
)(
    input         clk, rst_n,
    input         stall,         // 1=冻结PC (Load-Use或halt)
    input         branch_taken,  // 1=分支成立 (来自EX阶段)
    input         jump,          // 1=JAL跳转 (来自EX阶段)
    input         jalrsrc,       // 1=JALR跳转 (来自EX阶段)
    input  [31:0] branch_target, jump_target, jalr_target,

    output [31:0] pc,            // 当前PC (组合读, 与inst同步)
    output [31:0] inst,          // 当前指令 (组合读, 零延迟)
    output [31:0] pcplus4,       // PC+4 (JAL/JALR 链接地址)

    // Debug 接口
    input         inst_dbg_en, inst_wr_en,
    input  [31:0] inst_dbg_addr, inst_wr_data,
    output [31:0] inst_rd_data
);

    // IMem: 8KB 分布式 RAM (2048 × 32-bit), 组合读
    (* ram_style = "distributed" *)
    reg [31:0] imem [0:2047];

    // Debug 跨时钟域同步
    reg        inst_dbg_en_sync, inst_wr_en_sync;
    reg [31:0] inst_dbg_addr_sync, inst_wr_data_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_dbg_en_sync   <= 1'b0;
            inst_wr_en_sync    <= 1'b0;
            inst_dbg_addr_sync <= 32'b0;
            inst_wr_data_sync  <= 32'b0;
        end else begin
            inst_dbg_en_sync   <= inst_dbg_en;
            inst_wr_en_sync    <= inst_wr_en;
            inst_dbg_addr_sync <= inst_dbg_addr;
            inst_wr_data_sync  <= inst_wr_data;
        end
    end

    // 地址映射: PC 0x4000–0x5FFF → 物理 0x0000–0x07FF
    wire [13:0] imem_logical = inst_dbg_en_sync ? inst_dbg_addr_sync[15:2] : pc_reg[15:2];
    wire [10:0] imem_phys    = imem_logical[10:0];
    wire        imem_wea     = inst_dbg_en_sync & inst_wr_en_sync;

    // 同步写 (仅 Debug)
    always @(posedge clk) begin
        if (imem_wea)
            imem[imem_phys] <= inst_wr_data_sync;
    end

    // 组合读 (零延迟)
    assign inst_rd_data = imem[imem_phys];
    assign inst         = imem[imem_phys];

    // $readmemh 初始化
    parameter PC_RESET = 32'h00004000;
    localparam HEX_LOAD_OFFSET = 0;
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, imem, HEX_LOAD_OFFSET);
    end

    // =========================================================================
    // PC 寄存器 (单一寄存器, 与 inst 组合读天然同步)
    // =========================================================================
    reg [31:0] pc_reg;
    wire [31:0] pc_plus_4 = pc_reg + 32'd4;

    // Next-PC MUX: stall > 分支/跳转 > PC+4
    wire take_branch = branch_taken | jump | jalrsrc;
    wire [31:0] target = jalrsrc ? jalr_target :
                          jump   ? jump_target :
                                   branch_target;

    wire [31:0] next_pc;
    assign next_pc = stall       ? pc_reg :
                     take_branch ? target :
                                   pc_plus_4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_reg <= PC_RESET;
        else
            pc_reg <= next_pc;
    end

    assign pc      = pc_reg;
    assign pcplus4 = pc_plus_4;

endmodule

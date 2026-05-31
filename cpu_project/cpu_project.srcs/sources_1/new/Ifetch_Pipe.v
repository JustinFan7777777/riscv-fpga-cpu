// =============================================================================
// Module      : Ifetch_Pipe.v
// Description : 流水线版取指模块 — PC + IMem (BRAM 寄存器读)
// =============================================================================
// 与单周期版 Ifetch.v 的区别:
//   1. IMem 使用 BRAM (ram_style="block") + 寄存器读, 1 周期延迟由流水线吸收
//   2. PC 更新逻辑考虑 EX 阶段的分支/跳转信号 (延迟到达)
//   3. stall 冻结 PC (Load-Use hazard), flush_ifid 由 HazardUnit ctrl_flush 控制
//
// PC 更新优先级: stall > branch/jump taken > PC+4
// =============================================================================
`timescale 1ns / 1ps

module Ifetch_Pipe #(
    parameter INIT_FILE = "batch_test_pipeline.txt"
)(
    input         clk, rst_n,
    input         stall,         // 1=冻结PC (Load-Use)
    input         flush_ifid,    // 1=清零inst输出 (branch/jump taken → NOP)
    input         branch_taken,  // 1=分支成立 (来自EX阶段)
    input         jump,          // 1=JAL跳转 (来自EX阶段)
    input         jalrsrc,       // 1=JALR跳转 (来自EX阶段)
    input  [31:0] branch_target, jump_target, jalr_target,

    output [31:0] pc,             // 当前PC (用于AUIPC和Debug)
    output [31:0] inst,           // 当前指令 (已注册, 延迟1周期)
    output [31:0] pcplus4,        // PC+4

    // Debug 接口
    input         inst_dbg_en, inst_wr_en,
    input  [31:0] inst_dbg_addr, inst_wr_data,
    output [31:0] inst_rd_data
);

    // IMem: 8KB BRAM (2048 × 32-bit), 寄存器读
    // ram_style="block" + WRITE_MODE="READ_FIRST" 匹配 RTL 先读后写语义
    (* ram_style = "block", WRITE_MODE = "READ_FIRST" *)
    reg [31:0] imem [0:2047];

    // Debug 同步
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
    // 使用 pc_reg 而非 pc: inst_reg 需提前读取下一条指令, 而 pc 输出的
    // 是 pc_prev (与 inst_reg 对齐的 PC), 用于 IF/ID 阶段
    wire [13:0] imem_logical = inst_dbg_en_sync ? inst_dbg_addr_sync[15:2] : pc_reg[15:2];
    wire [10:0] imem_phys    = imem_logical[10:0];
    wire        imem_wea     = inst_dbg_en_sync & inst_wr_en_sync;

    // BRAM 寄存器读 (与组合读不同: inst_reg 延迟1周期)
    // 同步复位 inst_reg 消除仿真 X, 不影响 BRAM 推断 (imem 数组无复位)
    reg [31:0] inst_reg;
    always @(posedge clk) begin
        if (!rst_n) begin
            inst_reg <= 32'd0;  // NOP
        end else begin
            if (imem_wea)
                imem[imem_phys] <= inst_wr_data_sync;
            inst_reg <= imem[imem_phys];
        end
    end

    // PC 寄存器: pc_reg=超前取指地址, pc_prev=与 inst_reg 对齐的指令PC
    reg [31:0] pc_reg, pc_prev;

    // Debug 读使用 inst_reg (同步寄存器读), 避免组合读破坏 BRAM 推断
    assign inst_rd_data = inst_reg;
    assign inst         = flush_ifid ? 32'd0 : inst_reg;
    // pcplus4: 当前指令的 PC+4, 用于 JAL/JALR 链接地址
    assign pcplus4      = pc_prev + 32'd4;
    parameter PC_RESET = 32'h00004000;

    localparam HEX_LOAD_OFFSET = 0;
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, imem, HEX_LOAD_OFFSET);
    end

    wire [31:0] pc_plus_4 = pc_reg + 32'd4;

    // Next-PC MUX: stall > branch_target > JALR > JAL > branch > PC+4
    wire take_branch = branch_taken | jump | jalrsrc;
    wire [31:0] target = jalrsrc ? jalr_target :
                          jump   ? jump_target :
                                   branch_target;

    wire [31:0] next_pc;
    assign next_pc = stall       ? pc_reg :        // 冻结
                     take_branch ? target :        // 分支/跳转
                                   pc_plus_4;      // 顺序执行

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_reg  <= PC_RESET;
            pc_prev <= PC_RESET;
        end else begin
            pc_reg  <= next_pc;
            pc_prev <= pc_reg;  // 保存当前 inst_reg 对应的 PC, 使 PC 与 inst 对齐
        end
    end

    // 输出与 inst 对齐的 PC (pc_prev), 而非已超前的 pc_reg
    assign pc = pc_prev;

endmodule

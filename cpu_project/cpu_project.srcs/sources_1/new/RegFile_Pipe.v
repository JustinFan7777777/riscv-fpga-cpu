// =============================================================================
// Module      : RegFile_Pipe.v
// Description : 32 x 32-bit Register File for RISC-V RV32I (流水线 CPU 用)
// =============================================================================
// 与单周期版 RegFile.v 的区别:
//   1. negedge 写: 在下一拍 posedge 之前完成, 消除流水线 RAW 的 NBA 竞争
//   2. bypass 旁路: WB 阶段正在写入 rd 且 ID 读同一寄存器时, 直接用 WD3
// =============================================================================
`timescale 1ns / 1ps

module RegFile_Pipe (
    input         clk,          // CPU 时钟 (12.5MHz)
    input         rst_n,        // 异步复位 (低有效)
    input         RegWrite,     // 写使能: 1=将WD3写入rd寄存器
    input  [4:0]  rs1_addr,     // 读口1地址 (来自 inst[19:15])
    input  [4:0]  rs2_addr,     // 读口2地址 (来自 inst[24:20])
    input  [4:0]  rd_addr,      // 写口地址 (来自 inst[11:7])
    input  [31:0] WD3,          // 写数据 (来自 ALU结果 或 内存读出)
    output [31:0] rs1_val,      // 读口1数据
    output [31:0] rs2_val,      // 读口2数据

    // Debug: 寄存器读取端口
    input  [4:0]  dbg_reg_addr, // Debug 选中的寄存器编号
    output [31:0] dbg_reg_data  // Debug 读出的寄存器值
);

    // 32个32-bit寄存器 (x0~x31)
    reg [31:0] regFile [0:31];
    integer i;  // 复位循环变量

    // ===========================
    // 双读口 (组合逻辑) + 写后读旁路
    // ===========================
    wire rs1_bypass = RegWrite && (rd_addr == rs1_addr) && (rs1_addr != 5'd0);
    wire rs2_bypass = RegWrite && (rd_addr == rs2_addr) && (rs2_addr != 5'd0);

    assign rs1_val = (rs1_addr == 5'd0) ? 32'b0 :
                     rs1_bypass         ? WD3  : regFile[rs1_addr];

    assign rs2_val = (rs2_addr == 5'd0) ? 32'b0 :
                     rs2_bypass         ? WD3  : regFile[rs2_addr];

    // Debug 读口 (同样加旁路)
    wire dbg_bypass = RegWrite && (rd_addr == dbg_reg_addr) && (dbg_reg_addr != 5'd0);
    assign dbg_reg_data = (dbg_reg_addr == 5'd0) ? 32'b0 :
                          dbg_bypass              ? WD3  : regFile[dbg_reg_addr];

    // ===========================
    // 写口 (negedge clk, negedge rst_n 异步复位)
    // ===========================
    // negedge 写: 在 posedge (ID/EX 锁存) 之前完成, 使下一拍 ID 读到新值
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regFile[i] <= 32'd0;
        end else begin
            if (RegWrite && (rd_addr != 5'd0)) begin
                regFile[rd_addr] <= WD3;
            end
        end
    end

endmodule

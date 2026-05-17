// =============================================================================
// Module      : RegFile.v
// Description : 32 x 32-bit Register File for RISC-V RV32I
// =============================================================================
//
// ================================ 中文说明 ================================
// 【功能】RISC-V 32x32 寄存器堆 —— 两读一写，x0 硬连线为 0。
//         同时提供 Debug 调试读口 (dbg_reg_addr → dbg_reg_data)。
//
// 【在 CPU 数据通路中的位置】
//                    ┌──▶ 读口1 (rs1_val) ──▶ ALU A端口
//   Decoder(rs1,rs2)─┤
//                    └──▶ 读口2 (rs2_val) ──▶ MUX ──▶ ALU B端口
//
//   写回: MEM/WB阶段 → RegWrite=1 → rd 被写入 WD3
//
// 【Debug 口】
//   dbg_reg_addr[4:0] — DebugController 选中的寄存器编号
//   dbg_reg_data[31:0] — 对应寄存器的值 (组合逻辑直出, 可随时读取)
//   0号寄存器读取返回0 (与RISC-V规范一致)
//
// 【RISC-V 寄存器约定 (ABI名仅供汇编编程参考, 硬件不关心)】
//   x0=zero, x1=ra, x2=sp, x3=gp, x4=tp, x5-7=t0-2
//   x8=s0/fp, x9=s1, x10-17=a0-7, x18-27=s2-11, x28-31=t3-6
// =============================================================================
`timescale 1ns / 1ps

module RegFile (
    input         clk,          // CPU 时钟 (25MHz)
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

    // ===========================
    // 双读口 (组合逻辑, 非阻塞)
    // ===========================
    // rs1_val: x0永远返回0, 其余寄存器直出
    assign rs1_val = (rs1_addr == 5'd0) ? 32'b0 : regFile[rs1_addr];

    // rs2_val: x0永远返回0, 其余寄存器直出
    assign rs2_val = (rs2_addr == 5'd0) ? 32'b0 : regFile[rs2_addr];

    // ===========================
    // Debug 读口 (组合逻辑)
    // ===========================
    // DebugController 随时可以读任意寄存器, 不影响CPU正常执行
    assign dbg_reg_data = (dbg_reg_addr == 5'd0) ? 32'b0 : regFile[dbg_reg_addr];

    // ===========================
    // 写口 (时序逻辑, 上升沿写入)
    // ===========================
    // 注意: x0 寄存器虽然写入端口开放, 但读口永远返回0, 所以即使写了x0也不影响读值
    // 这符合 RISC-V 规范 (x0 硬连线为0)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位: 清空所有寄存器 (实际FPGA上也可不清理, 但初始化便于调试)
            integer i;
            for (i = 0; i < 32; i = i + 1)
                regFile[i] <= 32'd0;
        end else begin
            if (RegWrite && (rd_addr != 5'd0)) begin
                regFile[rd_addr] <= WD3;
            end
        end
    end

endmodule

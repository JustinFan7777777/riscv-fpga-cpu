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
    // 双读口 (组合逻辑, 非阻塞) + 写后读旁路
    // ===========================
    // 旁路: WB 阶段 RegWrite=1 且 rd==rs 时, 直接用 WD3, 不等 negedge 写入
    // 解决流水线中 load→use 的 NBA 时序竞争:
    //   posedge: ID/EX 锁存时 regFile 还未更新, 旁路直接给 WD3
    wire rs1_bypass = RegWrite && (rd_addr == rs1_addr) && (rs1_addr != 5'd0);
    wire rs2_bypass = RegWrite && (rd_addr == rs2_addr) && (rs2_addr != 5'd0);

    assign rs1_val = (rs1_addr == 5'd0) ? 32'b0 :
                     rs1_bypass         ? WD3  : regFile[rs1_addr];

    assign rs2_val = (rs2_addr == 5'd0) ? 32'b0 :
                     rs2_bypass         ? WD3  : regFile[rs2_addr];

    // Debug 读口 (组合逻辑, 同样加旁路)
    wire dbg_bypass = RegWrite && (rd_addr == dbg_reg_addr) && (dbg_reg_addr != 5'd0);
    assign dbg_reg_data = (dbg_reg_addr == 5'd0) ? 32'b0 :
                          dbg_bypass              ? WD3  : regFile[dbg_reg_addr];

    // ===========================
    // 写口 (时序逻辑, negedge clk 写入, negedge rst_n 异步复位)
    // ===========================
    // 使用 negedge: 写入在 posedge (ID/EX锁存) 之前完成,
    // 避免流水线中 load→use 场景下 WB 写入和 ID 读取的 NBA 竞争。
    //   例: lw t1; add t3, t1, t2 → add 在 EX 时能从 RegFile 读到 lw 结果
    // RISC-V规范: x0 硬连线为0, 写操作对x0无效
    // 复位: for循环将32个寄存器全部清零 (综合为32个触发器复位)
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

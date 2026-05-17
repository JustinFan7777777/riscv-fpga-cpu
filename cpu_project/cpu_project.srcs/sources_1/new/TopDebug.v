// =============================================================================
// Module      : TopDebug.v
// Description : Project Top-Level — CPU + Debug Controller + UART + Clock Divider
// =============================================================================
//
// ================================ 中文说明 ================================
// 【功能】工程顶层模块 —— 集成 RISC-V CPU、Debug 调试控制器、UART 串口收发、
//         时钟分频器、外设 IO，是整个 FPGA 项目的唯一顶层。
//
// 【内部结构 (4个主要组件)】
//                          TopDebug
//   ┌────────────────────────────────────────────────────────────┐
//   │                                                            │
//   │  100MHz ──▶ ClockDivider(/4) ──▶ BUFG ──▶ 25MHz CPU clk   │
//   │                                                            │
//   │  uart_rxd ──▶ UartRx ──(rx_data)──▶ DebugController        │
//   │                                       │    │    │          │
//   │  uart_txd ◀── UartTx ◀──(tx_data)──┘    │    │          │
//   │                                          │    │          │
//   │              DebugController ──(cpu_halt,cpu_step,cpu_reset)│
//   │              DebugController ──(dbg_reg_addr)──▶           │
//   │              DebugController ──(inst_dbg_*)──▶   CPUTop    │
//   │              DebugController ──(dmem_dbg_*)──▶   (CPU)     │
//   │                                          │    │          │
//   │  SwitchIn ◀── 拨码开关 ◀───────────────────────┘          │
//   │  ButtonIn ◀── 按键 ◀─────────────────────────────────       │
//   │  LEDOut   ──▶ LED ◀────────────────────────────────        │
//   │  SegOut   ──▶ 数码管 ◀─────────────────────────────        │
//   │                                                            │
//   └────────────────────────────────────────────────────────────┘
//
// 【时钟方案】
//   系统时钟: 100MHz (EGO1 板载晶振, 引脚 P17)
//   CPU 时钟: 25MHz  (100MHz / 4)
//   分频方式: 2-bit 计数器 (~clk_div2, ~clk_div4)
//   BUFG: 将分频后的时钟推上全局时钟树, 保证低skew
//   DebugController 和 UART 直接使用 100MHz 系统时钟
//
// 【复位方案】
//   物理复位: EGO1 板载按钮 (引脚 P15, 按下=低电平)
//   软复位: DebugController 发出的 cpu_reset 脉冲
//   组合: rst_n_combined = rst_n & ~cpu_reset
//   (任意一个复位源触发都会复位整个 CPU)
//
// 【EGO1 引脚映射 (在 XDC 约束文件中定义)】
//   clk      : P17  (100MHz)
//   rst_n    : P15  (按钮, 按下=低)
//   uart_rxd : N5   (FPGA←PC, 相当于FPGA的输入)
//   uart_txd : T4   (FPGA→PC, 相当于FPGA的输出)
//   开关      : 8位 (R1, P2, P3, P4, P5, R6, T1, U2)
//   LED      : 8位 (F6, G4, G3, J4, J3, J2, K2, K1)
//   按键      : 5位 (R17, R15, V1, U4, U1)
//   数码管    : 8位段选 + 4位位选
//
// 【使用流程速查】
//   1. Vivado 创建工程 cpu_project, 添加所有 .v 源文件
//   2. 创建 XDC 约束文件, 映射上述引脚
//   3. 编译生成 TopDebug.bit
//   4. 烧录到 EGO1 开发板
//   5. PC 连接 USB 串口, 打开 Python 脚本调试
//      或使用传统开关/LED 方式验证
// =============================================================================
`timescale 1ns / 1ps

module TopDebug (
    input         clk,          // 100MHz 系统时钟 (EGO1: P17)
    input         rst_n,        // 物理复位按钮, 低有效 (EGO1: P15)

    // UART 串口
    input         uart_rxd,     // FPGA 接收引脚 (EGO1: N5)
    output        uart_txd,     // FPGA 发送引脚 (EGO1: T4)

    // 外设 IO (宽度可据EGO1实际硬件调整)
    input  [31:0] SwitchIn,     // 拨码开关 (高16位恒为0)
    input  [31:0] ButtonIn,     // 按键输入 (高27位恒为0)
    output [31:0] LEDOut,       // LED 输出 (高24位恒为0)
    output [31:0] SegOut        // 数码管输出 ({24'b0, 段选[7:0]})
);

    // ===========================
    // 时钟分频: 100MHz → 25MHz
    // ===========================
    // 2-bit 计数器: bit0=50MHz, bit1=25MHz
    reg [1:0] clk_div;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_div <= 2'd0;
        else
            clk_div <= clk_div + 2'd1;
    end

    // clk_div[1]: 100MHz / 4 = 25MHz
    wire clk_25mhz = clk_div[1];

    // BUFG: 全局时钟 Buffer (Vivado 综合时会自动识别并推上全局时钟树)
    // 将分频后的25MHz信号提升为高质量低skew全局时钟
    wire cpu_clk;
    BUFG BUFG_cpu_clk (
        .O(cpu_clk),      // 全局时钟输出 (低skew)
        .I(clk_25mhz)     // 分频时钟输入 (高skew)
    );

    // ===========================
    // 复位合并: 物理复位 OR 软复位
    // ===========================
    wire cpu_reset;
    wire rst_n_combined = rst_n & ~cpu_reset;

    // ===========================
    // UART 收发器
    // ===========================
    wire [7:0] rx_data;
    wire       rx_valid;
    wire [7:0] tx_data;
    wire       tx_start;
    wire       tx_busy;

    UartRx #(
        .CLK_FREQ(100_000_000),
        .BAUD(115200)
    ) uUartRx (
        .clk     (clk),
        .rst_n   (rst_n),        // UART使用原始物理复位
        .rx_pin  (uart_rxd),
        .rx_data (rx_data),
        .rx_valid(rx_valid)
    );

    UartTx #(
        .CLK_FREQ(100_000_000),
        .BAUD(115200)
    ) uUartTx (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_data (tx_data),
        .tx_start(tx_start),
        .tx_busy (tx_busy),
        .tx_pin  (uart_txd)
    );

    // ===========================
    // Debug 控制器
    // ===========================
    wire        cpu_halt;
    wire        cpu_step;
    // cpu_reset already declared above (for reset combining)
    wire [4:0]  dbg_reg_addr;
    wire [31:0] dbg_reg_data;
    wire [31:0] dbg_pc;
    wire        inst_dbg_en,   inst_wr_en;
    wire [31:0] inst_dbg_addr, inst_wr_data, inst_rd_data;
    wire        dmem_dbg_en,   dmem_wr_en;
    wire [31:0] dmem_dbg_addr, dmem_wr_data, dmem_rd_data;

    DebugController uDebugCtrl (
        .clk           (clk),           // 100MHz
        .rst_n         (rst_n),
        // UART interface
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .tx_data       (tx_data),
        .tx_start      (tx_start),
        .tx_busy       (tx_busy),
        // CPU control
        .cpu_halt      (cpu_halt),
        .cpu_step      (cpu_step),
        .cpu_reset     (cpu_reset),
        // Register read
        .dbg_reg_addr  (dbg_reg_addr),
        .dbg_reg_data  (dbg_reg_data),
        // Instruction memory debug
        .inst_dbg_en   (inst_dbg_en),
        .inst_wr_en    (inst_wr_en),
        .inst_dbg_addr (inst_dbg_addr),
        .inst_wr_data  (inst_wr_data),
        .inst_rd_data  (inst_rd_data),
        // Data memory debug
        .dmem_dbg_en   (dmem_dbg_en),
        .dmem_wr_en    (dmem_wr_en),
        .dmem_dbg_addr (dmem_dbg_addr),
        .dmem_wr_data  (dmem_wr_data),
        .dmem_rd_data  (dmem_rd_data),
        // PC
        .dbg_pc        (dbg_pc)
    );

    // ===========================
    // CPU 实例化
    // ===========================
    CPUTop uCPUTop (
        .clk           (cpu_clk),        // 25MHz BUFG输出
        .rst_n         (rst_n_combined), // 合并后的复位

        // Debug: CPU 控制
        .cpu_halt      (cpu_halt),
        .cpu_step      (cpu_step),
        .cpu_reset     (cpu_reset),

        // Debug: 寄存器
        .dbg_reg_addr  (dbg_reg_addr),
        .dbg_reg_data  (dbg_reg_data),

        // Debug: 指令内存
        .inst_dbg_en   (inst_dbg_en),
        .inst_wr_en    (inst_wr_en),
        .inst_dbg_addr (inst_dbg_addr),
        .inst_wr_data  (inst_wr_data),
        .inst_rd_data  (inst_rd_data),

        // Debug: 数据内存
        .dmem_dbg_en   (dmem_dbg_en),
        .dmem_wr_en    (dmem_wr_en),
        .dmem_dbg_addr (dmem_dbg_addr),
        .dmem_wr_data  (dmem_wr_data),
        .dmem_rd_data  (dmem_rd_data),

        // Debug: PC
        .dbg_pc        (dbg_pc),

        // 外设 IO
        .SwitchIn      (SwitchIn),
        .ButtonIn      (ButtonIn),
        .LEDOut        (LEDOut),
        .SegOut        (SegOut)
    );

endmodule

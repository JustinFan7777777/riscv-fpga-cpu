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
//   clk        : P17 (100MHz)
//   rst_n      : P15 (按钮, 按下=低)
//   uart_rxd   : N5  (FPGA←PC)
//   uart_txd   : T4  (FPGA→PC)
//   开关(左8)   : sw_pin[7:0]  = P5,P4,P3,P2,R2,M4,N4,R1
//   开关(右8)   : dip_pin[7:0] = U3,U2,V2,V5,V4,R3,T3,T5
//   LED(16个)  : led_pin[15:0]
//   按键(5个)   : btn_pin[4:0] = R11,R17,R15,V1,U4
//   数码管      : seg_cs[7:0](位选) + seg_data_0[7:0](段选0-3) + seg_data_1[7:0](段选4-7)
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

    // 外设 IO (宽度匹配 EGO1 开发板实际硬件)
    input  [15:0] SwitchIn,     // 拨码开关: [7:0]=sw_pin(左8), [15:8]=dip_pin(右8)
    input  [4:0]  ButtonIn,     // 按键: btn_pin[4:0] (5个按键)
    output [15:0] LEDOut,       // LED: led_pin[15:0] (16个LED)
    output [7:0]  seg_cs,       // 数码管位选: seg_cs_pin[7:0] (8位, 共阳极=低有效)
    output [7:0]  seg_data_0,   // 数码管段选组0: seg_data_0_pin[7:0] (对应左4位)
    output [7:0]  seg_data_1    // 数码管段选组1: seg_data_1_pin[7:0] (对应右4位)
);

    // ===========================
    // 时钟分频: 100MHz → 25MHz
    // ===========================
    // 2-bit 自由运行计数器:
    //   clk_div[0]: 每周期翻转 → 50MHz (占空比50%)
    //   clk_div[1]: 每2周期翻转 → 25MHz (占空比50%)
    // 取 clk_div[1] 作为CPU时钟源
    reg [2:0] clk_div;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_div <= 2'd0;
        else
            clk_div <= clk_div + 2'd1;
    end

    // clk_div[1]: 100MHz / 4 = 25MHz
    wire clk_25mhz = clk_div[2];

    // BUFG: 全局时钟 Buffer (Xilinx 原语)
    // 分频器输出的 clk_25mhz 是普通逻辑信号 (高skew),
    // 经过 BUFG 后推上 FPGA 全局时钟树 (低skew), 才能可靠驱动所有触发器
    // 不加 BUFG 会导致各模块时钟到达时间不一致 → setup/hold 违规
    wire cpu_clk;
    BUFG BUFG_cpu_clk (
        .O(cpu_clk),      // 全局时钟输出 (低skew)
        .I(clk_25mhz)     // 分频时钟输入 (高skew)
    );

    // ===========================
    // 复位合并: 物理复位 OR 软复位
    // ===========================
    // rst_n:          EGO1板载按键P15 (按下=低, 物理复位)
    // cpu_reset:      DebugController 发出的软复位脉冲 (CMD_RESET=0x01)
    // rst_n_combined: 任意一个有效 → CPU复位
    // 注: UART和DebugController用 rst_n (不复位调试通道), CPU用 rst_n_combined
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
        .seg_cs        (seg_cs),
        .seg_data_0    (seg_data_0),
        .seg_data_1    (seg_data_1)
    );

endmodule

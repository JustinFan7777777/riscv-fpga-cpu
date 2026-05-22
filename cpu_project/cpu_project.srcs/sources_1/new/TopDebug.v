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
//   │  100MHz ──▶ ClockDivider(/8) ──▶ BUFG ──▶ 12.5MHz CPU clk  │
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
//   CPU 时钟: 12.5MHz (100MHz / 8)
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
    output [7:0]  seg_data_1,   // 数码管段选组1: seg_data_1_pin[7:0] (对应右4位)

    // VGA 显示接口 (640×480@60Hz 文本模式, 12-bit 色彩)
    output        vga_hs,       // VGA 水平同步 (EGO1: D7)
    output        vga_vs,       // VGA 垂直同步 (EGO1: C4)
    output [3:0]  vga_r,        // VGA 红色通道 (EGO1: vga_data_pin[3:0] = F5,C6,C5,B7)
    output [3:0]  vga_g,        // VGA 绿色通道 (EGO1: vga_data_pin[7:4] = B6,A6,A5,D8)
    output [3:0]  vga_b         // VGA 蓝色通道 (EGO1: vga_data_pin[11:8] = C7,E6,E5,E7)

    // CPU 模式选择 (Bonus: Pipeline)
    // 0 = 单周期 (CPUTop), 1 = 五级流水线 (CPUTopPipeline)
    // 用 SwitchIn[15] (右8拨码开关最高位) 控制, 上电默认单周期
);

    // ===========================
    // 时钟分频: 100MHz → 12.5MHz
    // ===========================
    // 3-bit 自由运行计数器:
    //   clk_div[0]: 每周期翻转 → 50MHz
    //   clk_div[1]: 每2周期翻转 → 25MHz
    //   clk_div[2]: 每4周期翻转 → 12.5MHz
    // 取 clk_div[2] 作为CPU时钟源 (保证组合BRAM读路径时序收敛)
    reg [2:0] clk_div;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clk_div <= 3'd0;
        else
            clk_div <= clk_div + 3'd1;
    end

    // clk_div[2]: 100MHz / 8 = 12.5MHz
    wire clk_12_5mhz = clk_div[2];

    // clk_div[1]: 100MHz / 4 = 25MHz (VGA 像素时钟)
    wire clk_25mhz = clk_div[1];

    // BUFG: 全局时钟 Buffer (Xilinx 原语)
    // 分频器输出是普通逻辑信号 (高skew), 经过 BUFG 推上全局时钟树 (低skew)
    wire cpu_clk;
    BUFG BUFG_cpu_clk (
        .O(cpu_clk),         // 全局时钟输出 (低skew)
        .I(clk_12_5mhz)      // 分频时钟输入 (高skew)
    );

    // VGA 像素时钟 BUFG: 25MHz 低skew 全局时钟
    wire vga_clk;
    BUFG BUFG_vga_clk (
        .O(vga_clk),         // VGA 像素时钟 (25MHz, 低skew)
        .I(clk_25mhz)        // 来自 clk_div[1] (100MHz/4)
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
    wire [31:0] dbg_reg_data;       // → DebugController (来自MUX)
    wire [31:0] dbg_pc;             // → DebugController (来自MUX)
    wire        inst_dbg_en,   inst_wr_en;
    wire [31:0] inst_dbg_addr, inst_wr_data;
    wire [31:0] inst_rd_data;       // → DebugController (来自MUX)
    wire        dmem_dbg_en,   dmem_wr_en;
    wire [31:0] dmem_dbg_addr, dmem_wr_data;
    wire [31:0] dmem_rd_data;       // → DebugController (来自MUX)

    // 双CPU Debug响应线
    wire [31:0] single_dbg_reg, single_inst_rd, single_dmem_rd, single_dbg_pc;
    wire [31:0] pipe_dbg_reg,   pipe_inst_rd,   pipe_dmem_rd,   pipe_dbg_pc;

    DebugController uDebugCtrl (
        .clk           (clk),           // 100MHz
        .rst_n         (rst_n),
        // UART interface
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .tx_data       (tx_data),
        .tx_start      (tx_start),
        .tx_busy       (tx_busy),
        // CPU control — 同时发给两个CPU
        .cpu_halt      (cpu_halt),
        .cpu_step      (cpu_step),
        .cpu_reset     (cpu_reset),
        // Register read — MUX选择活跃CPU
        .dbg_reg_addr  (dbg_reg_addr),
        .dbg_reg_data  (dbg_reg_data),
        // Instruction memory debug — 写同时发给两CPU, 读MUX
        .inst_dbg_en   (inst_dbg_en),
        .inst_wr_en    (inst_wr_en),
        .inst_dbg_addr (inst_dbg_addr),
        .inst_wr_data  (inst_wr_data),
        .inst_rd_data  (inst_rd_data),
        // Data memory debug — 写同时发给两CPU, 读MUX
        .dmem_dbg_en   (dmem_dbg_en),
        .dmem_wr_en    (dmem_wr_en),
        .dmem_dbg_addr (dmem_dbg_addr),
        .dmem_wr_data  (dmem_wr_data),
        .dmem_rd_data  (dmem_rd_data),
        // PC
        .dbg_pc        (dbg_pc)
    );

    // ===========================
    // CPU 内部连线 (单周期 + 流水线)
    // ===========================
    wire [15:0] single_LED, pipe_LED;
    wire [7:0]  single_sc, single_s0, single_s1;
    wire [7:0]  pipe_sc, pipe_s0, pipe_s1;

    // ===========================
    // 单周期 CPU 实例化
    // ===========================
    CPUTop uCPUTop (
        .clk           (cpu_clk),
        .rst_n         (rst_n_combined),
        .cpu_halt      (cpu_halt),
        .cpu_step      (cpu_step),
        .cpu_reset     (cpu_reset),
        .dbg_reg_addr  (dbg_reg_addr),
        .dbg_reg_data  (single_dbg_reg),
        .inst_dbg_en   (inst_dbg_en),
        .inst_wr_en    (inst_wr_en),
        .inst_dbg_addr (inst_dbg_addr),
        .inst_wr_data  (inst_wr_data),
        .inst_rd_data  (single_inst_rd),
        .dmem_dbg_en   (dmem_dbg_en),
        .dmem_wr_en    (dmem_wr_en),
        .dmem_dbg_addr (dmem_dbg_addr),
        .dmem_wr_data  (dmem_wr_data),
        .dmem_rd_data  (single_dmem_rd),
        .dbg_pc        (single_dbg_pc),
        .SwitchIn      (SwitchIn),
        .ButtonIn      (ButtonIn),
        .LEDOut        (single_LED),
        .seg_cs        (single_sc),
        .seg_data_0    (single_s0),
        .seg_data_1    (single_s1),
        .clk_vga       (vga_clk),
        .vga_fb_addr   (vga_fb_addr),
        .vga_fb_data   (vga_fb_single)
    );

    // ===========================
    // 流水线 CPU 实例化 (Bonus)
    // ===========================
    CPUTopPipeline uCPUPipe (
        .clk(cpu_clk), .rst_n(rst_n_combined),
        .cpu_halt(cpu_halt), .cpu_step(cpu_step), .cpu_reset(cpu_reset),
        .dbg_reg_addr(dbg_reg_addr),
        .dbg_reg_data(pipe_dbg_reg),           // 流水线Debug读
        .inst_dbg_en(inst_dbg_en), .inst_wr_en(inst_wr_en),
        .inst_dbg_addr(inst_dbg_addr), .inst_wr_data(inst_wr_data),
        .inst_rd_data(pipe_inst_rd),           // 流水线Debug读
        .dmem_dbg_en(dmem_dbg_en), .dmem_wr_en(dmem_wr_en),
        .dmem_dbg_addr(dmem_dbg_addr), .dmem_wr_data(dmem_wr_data),
        .dmem_rd_data(pipe_dmem_rd),           // 流水线Debug读
        .dbg_pc(pipe_dbg_pc),                  // 流水线Debug读
        .SwitchIn(SwitchIn), .ButtonIn(ButtonIn),
        .LEDOut(pipe_LED), .seg_cs(pipe_sc),
        .seg_data_0(pipe_s0), .seg_data_1(pipe_s1),
        .clk_vga(vga_clk), .vga_fb_addr(vga_fb_addr), .vga_fb_data(vga_fb_pipe)
    );

    // ===========================
    // 输出 MUX: 单周期 vs 流水线
    // ===========================
    wire cpu_mode;
    assign cpu_mode = SwitchIn[15];  // 0=单周期, 1=流水线
    // 外设输出 MUX
    assign LEDOut      = cpu_mode ? pipe_LED      : single_LED;
    assign seg_cs      = cpu_mode ? pipe_sc       : single_sc;
    assign seg_data_0  = cpu_mode ? pipe_s0       : single_s0;
    assign seg_data_1  = cpu_mode ? pipe_s1       : single_s1;
    assign vga_fb_data = cpu_mode ? vga_fb_pipe   : vga_fb_single;

    // Debug 读响应 MUX (Pipeline要求: 暂停观察寄存器)
    // Debug写信号(inst_dbg_en/wr, dmem_dbg_en/wr)同时发给两个CPU,
    // 确保两个IMem/DMem内容一致。
    assign dbg_reg_data = cpu_mode ? pipe_dbg_reg   : single_dbg_reg;
    assign inst_rd_data = cpu_mode ? pipe_inst_rd   : single_inst_rd;
    assign dmem_rd_data = cpu_mode ? pipe_dmem_rd   : single_dmem_rd;
    assign dbg_pc       = cpu_mode ? pipe_dbg_pc    : single_dbg_pc;

    // ===========================
    // VGA 帧缓冲互连线
    // ===========================
    // DataMemory 内含 VGA 帧缓冲双端口 BRAM:
    //   Port A: CPU 写入 (negedge cpu_clk)
    //   Port B: VGA 读出 (posedge vga_clk)
    // 数据流: VGA(fb_addr) → DataMemory(vga_fb_addr)
    //         DataMemory(vga_fb_data) → VGA(fb_data)
    wire [11:0] vga_fb_addr;          // VGA → DataMemory: 帧缓冲读地址 (0~2399)
    wire [15:0] vga_fb_single;        // 单周期CPU → VGA: 帧缓冲读数据
    wire [15:0] vga_fb_pipe;          // 流水线CPU → VGA: 帧缓冲读数据
    wire [15:0] vga_fb_data;          // MUX后 → VGA: 帧缓冲读数据

    // ===========================
    // VGA 控制器实例化
    // ===========================
    // VGA 模块运行于 25MHz 像素时钟域, 通过帧缓冲 BRAM Port B 读取数据
    VGA uVGA (
        .clk_pix   (vga_clk),        // 25MHz 像素时钟
        .rst_n     (rst_n),          // 物理复位 (VGA 不复位CPU调试功能)
        .fb_addr   (vga_fb_addr),    // → DataMemory: 帧缓冲读地址
        .fb_data   (vga_fb_data),    // ← DataMemory: 帧缓冲读数据
        .vga_hs    (vga_hs),         // → EGO1: 水平同步
        .vga_vs    (vga_vs),         // → EGO1: 垂直同步
        .vga_r     (vga_r),          // → EGO1: 红色 [3:0]
        .vga_g     (vga_g),          // → EGO1: 绿色 [3:0]
        .vga_b     (vga_b)           // → EGO1: 蓝色 [3:0]
    );

endmodule

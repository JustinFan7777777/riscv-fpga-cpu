// =============================================================================
// Module      : DataMemory.v
// Description : Data Memory + MMIO for RISC-V RV32I
// =============================================================================
//
// ================================ 中文说明 ================================
// 【功能】数据内存模块 —— 包含数据 BRAM 和 MMIO(内存映射I/O)地址译码。
//         支持 CPU 正常 load/store 和 Debug 调试读写。
//
// 【在 CPU 数据通路中的位置】
//   ALU结果(地址) ──▶ DataMemory ──▶ 读数据 → MUX(MemtoReg) → RegFile写回
//   RegFile(rs2数据) ──▶ DataMemory(写入)
//
// 【地址空间布局 (哈佛架构, 与IMem物理分离)】
//   0x0000_0000 - 0x0000_FFFF : 数据内存 DMem (64KB BRAM)
//   0xFFFF_0000 - 0xFFFF_0003 : SwitchIn[15:0] 开关输入 (只读)
//   0xFFFF_0004 - 0xFFFF_0007 : ButtonIn[4:0]  按键输入 (只读)
//   0xFFFF_0008 - 0xFFFF_000B : LEDOut[15:0]   LED 输出 (读/写)
//   0xFFFF_000C - 0xFFFF_000F : seg_cs[7:0]    数码管位选 (读/写)
//   0xFFFF_0010 - 0xFFFF_0013 : seg_data_0[7:0] 数码管段选组0 (读/写)
//   0xFFFF_0014 - 0xFFFF_0017 : seg_data_1[7:0] 数码管段选组1 (读/写)
//   例如: 在汇编中 lw x1, 0(x31) 其中 x31=0xFFFF0000 → 读到开关值
//         在汇编中 sw x1, 8(x31) 其中 x31=0xFFFF0000 → 写到 LED
//
// 【MMIO 译码规则】
//   地址最高 16-bit == 0xFFFF → MMIO 访问, 其余→DMem BRAM 访问
//   MMIO地址的低4位决定具体外设: [3:0]=0→开关, 4→按键, 8→LED, C→数码管
//
// 【Debug 端口说明】
//   与 Ifetch 的 Debug 口完全对称:
//   dmem_dbg_en   : 1=Debug接管数据内存访问
//   dmem_wr_en    : 1=Debug写使能
//   dmem_dbg_addr : Debug访问的字节地址
//   dmem_wr_data  : Debug写入数据
//   dmem_rd_data  : Debug读出的数据
//
//   当 dmem_dbg_en=1 时, 地址/写使能/写数据全部由DebugController控制,
//   CPU的正常load/store被旁路。
// =============================================================================
`timescale 1ns / 1ps

module DataMemory (
    input         clk,              // CPU 时钟 (12.5MHz)
    input         rst_n,            // 异步复位 (低有效)
    input         clk_vga,          // VGA 像素时钟 (25MHz, 来自 TopDebug 的 clk_div[1] + BUFG)

    // CPU 正常访存接口
    input         MemWrite,         // 1=写数据内存 (来自Decoder)
    input  [31:0] Addr,             // 字节地址 (来自ALU结果)
    input  [31:0] WriteData,        // 待写入数据 (来自rs2)
    output [31:0] ReadData,         // 读出数据 (送到 MemtoReg MUX)

    // 外设 IO 接口 (宽度匹配 EGO1 开发板)
    input  [15:0] SwitchIn,         // 拨码开关: [7:0]=sw_pin, [15:8]=dip_pin
    input  [4:0]  ButtonIn,         // 按键: [4:0]=btn_pin
    output [15:0] LEDOut,           // LED: [15:0]=led_pin
    output [7:0]  seg_cs,           // 数码管位选 (8位, 共阳极=低有效)
    output [7:0]  seg_data_0,       // 数码管段选组0 (左4位)
    output [7:0]  seg_data_1,        // 数码管段选组1 (右4位)

    // Debug: 数据内存读写端口
    input         dmem_dbg_en,      // 1=Debug模式访问数据内存
    input         dmem_wr_en,       // 1=Debug写使能
    input  [31:0] dmem_dbg_addr,    // Debug 字节地址
    input  [31:0] dmem_wr_data,     // Debug 写入数据
    output [31:0] dmem_rd_data,     // Debug 读出数据

    // VGA 帧缓冲读口 (连接 VGA.v 模块, 运行于 clk_vga 时钟域)
    input  [11:0] vga_fb_addr,      // VGA 读地址 (0~2399, 字地址)
    output [15:0] vga_fb_data       // VGA 读数据 ([7:0]=ASCII, [15:8]=颜色属性)
);

    // 数据内存 BRAM: 16384 x 32-bit = 64KB
    (* ram_style = "block" *)
    reg [31:0] mem [0:16383];

    // IO 外设寄存器 (MMIO中可读可写, 宽度匹配 EGO1 实际硬件)
    reg [15:0] led_reg;        // 16 个 LED
    reg [7:0]  seg_cs_reg;     // 数码管位选 (8位)
    reg [7:0]  seg_data0_reg;  // 数码管段选组0
    reg [7:0]  seg_data1_reg;  // 数码管段选组1

    // ==========================================================================
    // VGA 帧缓冲 BRAM — 真双端口 (True Dual-Port)
    // ==========================================================================
    // 规格: 2400 × 16-bit (80列 × 30行), 占用约 1.5 个 BRAM36
    //   Port A (CPU 侧): posedge clk (12.5MHz) — CPU 通过 MMIO 写入/读取
    //   Port B (VGA 侧): posedge clk_vga (25MHz) — VGA 控制器扫描读出
    //   注: Port A 使用 posedge (非 negedge) 是因为 Xilinx TDP BRAM 要求
    //   两端口均为 posedge 才能正确推断为 Block RAM
    // 每字: [7:0]=ASCII 码, [11:8]=前景色(I+R+G+B), [15:12]=背景色(I+R+G+B)

    (* ram_style = "block", WRITE_MODE = "READ_FIRST" *)
    reg [15:0] vga_fb_mem [0:2399];      // 80×30 = 2400 个字符位
    // WRITE_MODE="READ_FIRST": 同时读写同一地址时返回旧值, 匹配仿真语义

    // ---- Debug 同步寄存器 (声明在先, 供后续逻辑使用) ----
    reg         dmem_dbg_en_sync,   dmem_wr_en_sync;
    reg [31:0] dmem_dbg_addr_sync, dmem_wr_data_sync;

    // ---- CPU 侧读写信号 ----
    wire        vga_fb_we_cpu;            // CPU 写使能 (MMIO 区域命中 + MemWrite)
    wire [11:0] vga_fb_waddr;            // CPU 读/写字地址 (0~2399)
    reg  [15:0] vga_fb_cpu_rdata;        // CPU 读数据寄存器

    // VGA 帧缓冲 MMIO 地址范围检测
    // 范围: 0xFFFF_0100 – 0xFFFF_13BF (2400字 × 2字节 = 4800字节)
    wire isVGA_CPU = (Addr[31:16] == 16'hFFFF) &&
                     (Addr[15:0] >= 16'h0100) && (Addr[15:0] <= 16'h13BF);
    wire isVGA_DBG = (dmem_dbg_addr_sync[31:16] == 16'hFFFF) &&
                     (dmem_dbg_addr_sync[15:0] >= 16'h0100) &&
                     (dmem_dbg_addr_sync[15:0] <= 16'h13BF);

    // 字地址计算: (字节地址 - 0xFFFF_0100) >> 1
    //   Addr[12:1] = 字节地址[12:1]
    //   fb_word_idx = Addr[12:1] - 128  (因为 0x0100 >> 1 = 128)
    assign vga_fb_waddr = Addr[12:1] - 12'd128;

    // CPU 写使能: 非 Debug 模式、MemWrite 有效、且地址命中 VGA 帧缓冲
    assign vga_fb_we_cpu = ~dmem_dbg_en_sync && MemWrite && isVGA_CPU;

    // ---- Port A: CPU 侧 (posedge clk, 12.5MHz) ----
    // 使用 posedge 而非 negedge: Xilinx 真双端口 BRAM 要求两端口均为 posedge
    // 才能正确推断为 BRAM, 避免回退到 LUT RAM 耗尽 LUT 资源。
    // 读优先写: 先读后写, 确保读返回旧值 (read-before-write 语义)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vga_fb_cpu_rdata <= 16'd0;
        end else begin
            // 先读 (返回旧值, 即使同一周期有写操作)
            vga_fb_cpu_rdata <= vga_fb_mem[vga_fb_waddr];
            // 后写
            if (vga_fb_we_cpu)
                vga_fb_mem[vga_fb_waddr] <= WriteData[15:0];
        end
    end

    // ---- Port B: VGA 侧 (posedge clk_vga, 25MHz) — 只读 ----
    reg [15:0] vga_fb_data_reg;
    always @(posedge clk_vga) begin
        vga_fb_data_reg <= vga_fb_mem[vga_fb_addr];
    end
    assign vga_fb_data = vga_fb_data_reg;

    // ===========================
    // 跨时钟域同步 Debug 信号 (negedge clk: 与CPU时钟错半拍, 改善时序)
    // ===========================
    // DebugController@100MHz → CPU@12.5MHz, 打一拍同步消除亚稳态
    // 使用 negedge: Debug写发生在clk下降沿, BRAM在上升沿之前有半拍setup
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_dbg_en_sync   <= 1'b0;
            dmem_wr_en_sync    <= 1'b0;
            dmem_dbg_addr_sync <= 32'b0;
            dmem_wr_data_sync  <= 32'b0;
        end else begin
            dmem_dbg_en_sync   <= dmem_dbg_en;
            dmem_wr_en_sync    <= dmem_wr_en;
            dmem_dbg_addr_sync <= dmem_dbg_addr;
            dmem_wr_data_sync  <= dmem_wr_data;
        end
    end

    // ===========================
    // MMIO 地址译码 — 两级译码
    // ===========================
    // 第一级: Addr[31:16]==0xFFFF → 外设区域, 否则→DMem BRAM
    // 第二级: Addr[3:0] 选具体外设, 见下方映射表
    wire isMMIO_CPU = (Addr[31:16] == 16'hFFFF);
    wire isMMIO_DBG = (dmem_dbg_addr_sync[31:16] == 16'hFFFF);

    // CPU 侧 MMIO 读 (返回32bit值, 外设位宽不足的零扩展填满)
    // 注: LW指令始终取32-bit, 所以需要将窄外设零扩展
    // 优先级: 传统外设 (Addr[3:0]) > VGA 帧缓冲 (Addr[15:0] in 0x0100~0x13BF) > 0
    wire [31:0] mmio_read_cpu;
    assign mmio_read_cpu = (Addr[3:0] == 4'h0)  ? {16'b0, SwitchIn}         :  // 0xFFFF0000: 开关
                           (Addr[3:0] == 4'h4)  ? {27'b0, ButtonIn}         :  // 0xFFFF0004: 按键
                           (Addr[3:0] == 4'h8)  ? {16'b0, led_reg}          :  // 0xFFFF0008: LED
                           (Addr[3:0] == 4'hC)  ? {24'b0, seg_cs_reg}       :  // 0xFFFF000C: 数码管位选
                           (Addr[3:0] == 4'h10) ? {24'b0, seg_data0_reg}    :  // 0xFFFF0010: 数码管段选0
                           (Addr[3:0] == 4'h14) ? {24'b0, seg_data1_reg}    :  // 0xFFFF0014: 数码管段选1
                           isVGA_CPU             ? {16'b0, vga_fb_cpu_rdata} :  // VGA帧缓冲 (CPU读)
                           32'd0;

    // MMIO 写 (CPU侧: posedge clk 触发)
    // MemWrite=1 且 isMMIO=1 时, 根据地址写对应外设寄存器
    wire mmio_we_cpu = MemWrite && isMMIO_CPU;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_reg       <= 16'd0;
            seg_cs_reg    <= 8'd0;
            seg_data0_reg <= 8'd0;
            seg_data1_reg <= 8'd0;
        end else begin
            if (mmio_we_cpu) begin
                if (Addr[3:0] == 4'h8)  led_reg       <= WriteData[15:0];
                if (Addr[3:0] == 4'hC)  seg_cs_reg    <= WriteData[7:0];
                if (Addr[3:0] == 4'h10) seg_data0_reg <= WriteData[7:0];
                if (Addr[3:0] == 4'h14) seg_data1_reg <= WriteData[7:0];
            end
        end
    end

    // ===========================
    // DMem BRAM: 地址/数据 MUX (Debug 还是 CPU)
    // ===========================
    // dmem_dbg_en_sync=1 → DebugController 接管: 地址/写使能/写数据全由Debug侧控制
    // dmem_dbg_en_sync=0 → CPU 正常访问: MemWrite且非MMIO时写BRAM
    wire [31:0] uram_addr_mux = dmem_dbg_en_sync ? dmem_dbg_addr_sync : Addr;
    wire uram_wea = dmem_dbg_en_sync ? dmem_wr_en_sync : (MemWrite && !isMMIO_CPU);
    wire [31:0] uram_din = dmem_dbg_en_sync ? dmem_wr_data_sync : WriteData;

    // BRAM 同步读 (negedge: 与IMem的posedge错开半拍, 分散FPGA内部BRAM访问峰值)
    reg [31:0] mem_read_data;
    always @(negedge clk) begin
        if (uram_wea)
            mem[uram_addr_mux[15:2]] <= uram_din;
        mem_read_data <= mem[uram_addr_mux[15:2]];
    end

    // ===========================
    // 读数据 MUX: DMem BRAM 还是 MMIO
    // ===========================
    // CPU读: isMMIO → 外设值(零扩展) : BRAM读出值
    // Debug读: 只读BRAM, MMIO区域返回0 (调试场景主要访问数据区)
    assign ReadData     = isMMIO_CPU ? mmio_read_cpu  : mem_read_data;
    assign dmem_rd_data = isMMIO_DBG ? 32'd0          : mem_read_data;

    // 输出到外设 (直连 EGO1 引脚, 组合逻辑)
    assign LEDOut     = led_reg;
    assign seg_cs     = seg_cs_reg;
    assign seg_data_0 = seg_data0_reg;
    assign seg_data_1 = seg_data1_reg;

endmodule

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
//   0x0000_0000 - 0x0000_3FFF : 数据内存 DMem (16KB BRAM)
//   0xFFFF_0000 - 0xFFFF_0003 : 开关输入 (只读, 32-bit)
//   0xFFFF_0004 - 0xFFFF_0007 : 按键输入 (只读, 32-bit)
//   0xFFFF_0008 - 0xFFFF_000B : LED 输出   (读/写, 32-bit)
//   0xFFFF_000C - 0xFFFF_000F : 数码管输出 (读/写, 32-bit)
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
    input         clk,              // CPU 时钟 (25MHz)
    input         rst_n,            // 异步复位 (低有效)
    // CPU 正常访存接口
    input         MemWrite,         // 1=写数据内存 (来自Decoder)
    input  [31:0] Addr,             // 字节地址 (来自ALU结果)
    input  [31:0] WriteData,        // 待写入数据 (来自rs2)
    output [31:0] ReadData,         // 读出数据 (送到 MemtoReg MUX)

    // 外设 IO 接口 (直连 FPGA 引脚)
    input  [31:0] SwitchIn,         // 拨码开关输入值
    input  [31:0] ButtonIn,         // 按键输入值
    output [31:0] LEDOut,           // LED输出值
    output [31:0] SegOut,           // 数码管输出值

    // Debug: 数据内存读写端口
    input         dmem_dbg_en,      // 1=Debug模式访问数据内存
    input         dmem_wr_en,       // 1=Debug写使能
    input  [31:0] dmem_dbg_addr,    // Debug 字节地址
    input  [31:0] dmem_wr_data,     // Debug 写入数据
    output [31:0] dmem_rd_data      // Debug 读出数据
);

    // 数据内存 BRAM: 4096 x 32-bit = 16KB
    (* ram_style = "block" *)
    reg [31:0] mem [0:4095];

    // LED 和 数码管 寄存器 (MMIO中可读可写的外设)
    reg [31:0] led_reg;
    reg [31:0] seg_reg;

    // ===========================
    // 跨时钟域同步 Debug 信号
    // ===========================
    reg         dmem_dbg_en_sync,   dmem_wr_en_sync;
    reg [31:0] dmem_dbg_addr_sync, dmem_wr_data_sync;

    always @(negedge clk or negedge rst_n) begin  // 注意: negedge clk
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
    // MMIO 地址译码
    // ===========================
    // isMMIO: 地址[31:16] == 16'hFFFF → 外设访问
    wire isMMIO_CPU = (Addr[31:16] == 16'hFFFF);
    wire isMMIO_DBG = (dmem_dbg_addr_sync[31:16] == 16'hFFFF);

    // CPU 侧 MMIO 读
    wire [31:0] mmio_read_cpu;
    assign mmio_read_cpu = (Addr[3:0] == 4'h0) ? SwitchIn  :   // 0xFFFF0000: 开关
                           (Addr[3:0] == 4'h4) ? ButtonIn  :   // 0xFFFF0004: 按键
                           (Addr[3:0] == 4'h8) ? led_reg   :   // 0xFFFF0008: LED
                           (Addr[3:0] == 4'hC) ? seg_reg   :   // 0xFFFF000C: 数码管
                           32'd0;

    // MMIO 写 (CPU侧)
    // 只有 MemWrite=1 且地址命中MMIO时才写外设寄存器
    wire mmio_we_cpu = MemWrite && isMMIO_CPU;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led_reg <= 32'd0;
            seg_reg <= 32'd0;
        end else begin
            if (mmio_we_cpu) begin
                if (Addr[3:0] == 4'h8)  led_reg <= WriteData;
                if (Addr[3:0] == 4'hC)  seg_reg <= WriteData;
            end
        end
    end

    // ===========================
    // DMem BRAM: 地址 MUX (Debug 还是 CPU)
    // ===========================
    wire [31:0] uram_addr_mux = dmem_dbg_en_sync ? dmem_dbg_addr_sync : Addr;
    wire uram_wea = dmem_dbg_en_sync ? dmem_wr_en_sync : (MemWrite && !isMMIO_CPU);
    wire [31:0] uram_din = dmem_dbg_en_sync ? dmem_wr_data_sync : WriteData;

    // BRAM 读写 (同步读)
    reg [31:0] mem_read_data;
    always @(negedge clk) begin  // 下降沿: 与CPU时钟错半拍, 为时序优化
        if (uram_wea)
            mem[uram_addr_mux[13:2]] <= uram_din;
        mem_read_data <= mem[uram_addr_mux[13:2]];
    end

    // ===========================
    // 读数据 MUX: DMem BRAM 还是 MMIO
    // ===========================
    assign ReadData    = isMMIO_CPU ? mmio_read_cpu  : mem_read_data;
    assign dmem_rd_data = isMMIO_DBG ? 32'd0          : mem_read_data;
    // Note: Debug读MMIO暂返回0, 实际调试场景主要读DMem数据区

    // 输出到外设
    assign LEDOut = led_reg;
    assign SegOut = seg_reg;

endmodule

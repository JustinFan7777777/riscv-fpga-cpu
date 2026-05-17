// =============================================================================
// Module      : Ifetch.v
// Description : Instruction Fetch (PC + Instruction Memory) for RISC-V RV32I
// =============================================================================
//
// ================================ 中文说明 ================================
// 【功能】取指模块 —— 包含程序计数器(PC)和指令内存(BRAM)。
//         每个时钟周期从 IMem 取出一条 32-bit 指令送给 Decoder。
//         支持 CPU 正常取指 AND Debug 调试读写指令内存。
//
// 【在 CPU 数据通路中的位置】
//   PC ──▶ IMem(addr) ──▶ inst(输出到Decoder)
//     ▲
//     └── Next-PC逻辑: PC+4 / Branch目标 / JAL目标 / JALR目标
//
// 【PC 更新逻辑 (Next-PC MUX, 优先级从高到低)】
//   1. cpu_halt=1   → PC保持不变 (调试器暂停了CPU)
//   2. cpu_reset=1   → PC归零
//   3. JALR=1       → PC = rs1 + imm (寄存器跳转, 最低位清零对齐)
//   4. Jump=1       → PC = PC + imm (JAL跳转)
//   5. Branch=1且条件满足 → PC = PC + imm (条件分支)
//   6. 以上都不满足 → PC = PC + 4 (顺序执行)
//
// 【指令内存 (IMem)】
//   - 使用 BRAM (Block RAM, 综合为FPGA片上块RAM)
//   - 大小: 64KB (16384 x 32-bit words), 对应14-bit 字地址 (addr[15:2])
//   - 使用 $readmemh 初始化, hex文件路径由参数 INIT_FILE 指定
//   - 同步读: 地址给入后, 下个时钟沿输出数据 (BRAM硬件特性)
//   - Debug 口: 当 inst_dbg_en=1时, 地址/写使能/写数据由DebugController接管
//
// 【Debug 端口说明 (来自/去向 DebugController)】
//   inst_dbg_en   : 1=Debug模式访问指令内存 (读或写)
//   inst_wr_en    : 1=Debug写使能 (仅在 inst_dbg_en=1 时有效)
//   inst_dbg_addr : Debug访问的字节地址
//   inst_wr_data  : Debug要写入的数据
//   inst_rd_data  : Debug读出的数据 (送回DebugController)
//
// 【跨时钟域同步】
//   CPU跑25MHz, DebugController跑100MHz. 所有 debug 输入信号在CPU时钟
//   域内打一拍 (_sync后缀) 后再使用, 避免亚稳态。
//
// 【IMem 包含的 .hex 文件地址映射】
//   $readmemh 读取 hex 文件, 文件中每行 8 位十六进制数(32bit).
//   文件第1行写入 mem[0], 第2行写入 mem[1], 依次类推.
//   所以汇编器应该把代码从地址 0x0000 开始排放 (或按需调整).
// =============================================================================
`timescale 1ns / 1ps

module Ifetch #(
    parameter INIT_FILE = "../assembly/batch_test.hex"  // hex 初始化文件路径
)(
    input         clk,              // CPU 时钟 (25MHz)
    input         rst_n,            // 异步复位 (低有效)
    input         cpu_halt,         // 1=暂停PC更新 (调试器控制)
    input         cpu_reset,        // 1=复位PC (调试软复位)
    input         PCSrc,            // 1=使用分支目标地址 (Branch且条件满足)
    input         Jump,             // 1=JAL跳转 (PC+imm)
    input         JALRSrc,          // 1=JALR跳转 (rs1+imm)
    input  [31:0] BranchTarget,     // 分支目标地址 = PC + imm (由B-type立即数算得)
    input  [31:0] JumpTarget,       // JAL 跳转目标 = PC + imm
    input  [31:0] JALRTarget,       // JALR 跳转目标 = rs1 + imm (LSB清零)
    output [31:0] PC,               // 当前 PC 值 (送给外部用于 AUIPC 和 Debug 读取)
    output [31:0] inst,             // 当前指令 (送给 Decoder)
    output [31:0] PCPlus4,          // PC+4 (送给 JAL/JALR 的链接地址)

    // Debug: 指令内存读写端口
    input         inst_dbg_en,      // 1=Debug模式访问指令内存
    input         inst_wr_en,       // 1=Debug写使能
    input  [31:0] inst_dbg_addr,    // Debug 字节地址
    input  [31:0] inst_wr_data,     // Debug 写入数据
    output [31:0] inst_rd_data      // Debug 读出数据
);

    // 指令内存 BRAM: 16384 x 32-bit = 64KB
    // (* ram_style = "block" *) 强制 Vivado 综合为 Block RAM
    (* ram_style = "block" *)
    reg [31:0] mem [0:16383];

    // ===========================
    // 跨时钟域同步 Debug 信号
    // ===========================
    // 原因: DebugController 跑 100MHz, CPU 跑 25MHz
    // 直接接可能产生 setup/hold 时序违规
    reg        inst_dbg_en_sync,   inst_wr_en_sync;
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

    // ===========================
    // IMem 地址 MUX: Debug地址 还是 正常PC地址
    // ===========================
    // PC是字节地址, IMem是32-bit字地址 → PC[15:2]取14-bit字地址
    // Debug地址同样是字节地址 → inst_dbg_addr_sync[15:2]
    wire [13:0] imem_addr = inst_dbg_en_sync ? inst_dbg_addr_sync[15:2] : PC[15:2];
    wire        imem_wea  = inst_dbg_en_sync & inst_wr_en_sync;

    // ===========================
    // BRAM 实例化 (同步读: 本周期给地址, 下周期数据才到 mem_dout)
    // ===========================
    // FPGA Block RAM 硬件特性: 读延迟1个时钟周期 (不能组合读)
    // 因此单周期CPU实际CPI=2 (取指1拍 + 执行1拍), 但指令吞吐仍是1条/周期
    // Debug写: imem_wea=1时本周期写入 inst_wr_data_sync
    // Debug读: mem_dout在下周期反映新地址, inst_rd_data直连mem_dout
    reg [31:0] mem_dout;
    always @(posedge clk) begin
        if (imem_wea)
            mem[imem_addr] <= inst_wr_data_sync;
        mem_dout <= mem[imem_addr];
    end

    // IMem 读取数据: Debug读和正常取指共用
    assign inst_rd_data = mem_dout;
    assign inst         = mem_dout;

    // ===========================
    // 使用 $readmemh 初始化指令内存
    // ===========================
    // Vivado 综合时读取 hex 文件写入 BRAM 初始值.
    // difftest 差分测试框架默认从 IMem 字节地址 0x4000 开始放置指令,
    // 对应 mem 的字地址 = 0x4000 / 4 = 4096, 所以从 mem[4096] 开始加载.
    localparam HEX_LOAD_OFFSET = PC_RESET >> 2;
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem, HEX_LOAD_OFFSET);
    end

    // ===========================
    // Program Counter (PC)
    // ===========================
    reg [31:0] pcReg;

    // 计算各种 Next-PC
    wire [31:0] PC_Plus_4 = pcReg + 32'd4;

    parameter PC_RESET = 32'h00004000;  // difftest要求PC从0x4000开始

    // Next-PC MUX (优先级从高到低, 用串联三元运算符实现)
    //   1. cpu_halt   → PC保持不变 (调试器暂停CPU)
    //   2. cpu_reset  → PC回到0x4000 (硬件复位或调试软复位)
    //   3. JALRSrc    → PC = rs1+imm, LSB清零 (JALR寄存器跳转)
    //   4. Jump       → PC = PC+imm (JAL跳转)
    //   5. PCSrc      → PC = PC+imm (条件分支满足)
    //   6. default    → PC = PC+4 (顺序执行)
    // 注: PCSrc = Branch && BranchTaken, 由CPUTop计算后传入
    wire [31:0] NextPC;
    assign NextPC = cpu_halt              ? pcReg :       // halt: 暂停
                    (cpu_reset)          ? PC_RESET :     // reset: 回到0x4000
                    JALRSrc              ? JALRTarget :  // JALR
                    Jump                 ? JumpTarget :  // JAL
                    PCSrc                 ? BranchTarget :// 条件分支满足
                                           PC_Plus_4;   // 默认: 顺序执行

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pcReg <= PC_RESET;  // difftest要求PC从0x4000开始
        end else begin
            pcReg <= NextPC;
        end
    end

    assign PC      = pcReg;
    assign PCPlus4 = PC_Plus_4;

endmodule

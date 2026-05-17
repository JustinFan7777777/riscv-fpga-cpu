// =============================================================================
// Module      : CPUTop.v
// Description : RISC-V RV32I Single-Cycle CPU Top-Level
// =============================================================================
//
// ================================ 中文说明 ================================
// 【功能】RISC-V RV32I 单周期 CPU 顶层模块 —— 将所有数据通路子模块连接起来,
//         形成一条完整的单周期指令执行通路, 并集成 Debug 调试接口。
//
// 【内部结构 (6个子模块)】
//   ┌─────────┐     ┌──────────┐     ┌───────────┐
//   │ Ifetch  │────▶│ Decoder  │────▶│ RegFile   │
//   │ (PC+IMem)│    │ +ImmGen  │     │ 32x32     │
//   └─────────┘     └──────────┘     └───────────┘
//         │               │                │
//         │ PC            │ control        │ rs1_val, rs2_val
//         ▼               ▼                ▼
//   ┌──────────┐    ┌──────────┐    ┌──────────┐
//   │ Next-PC  │    │ ALU      │◀───│ MUXes    │
//   │ Logic    │    │ (4-bit)  │    │(srcA/srcB)│
//   └──────────┘    └──────────┘    └──────────┘
//                          │
//                          │ ALUResult
//                          ▼
//                    ┌──────────┐    ┌──────────┐
//                    │DataMemory│───▶│ MemtoReg │──▶ RegFile WD3
//                    │(DMem+MMIO)│   │  MUX     │
//                    └──────────┘    └──────────┘
//
// 【单周期数据通路 (一条指令在一个时钟周期内完成)】
//   1. Ifetch: PC → IMem → inst 输出
//   2. Decoder: inst → 控制信号(RegWrite,ALUSrc,MemWrite,ALUOp...)
//   3. RegFile: rs1,rs2 → rs1_val, rs2_val
//   4. ImmGen: inst → 32-bit 立即数
//   5. MUX(ALUSrcA): 选择 ALU A端口输入 (rs1_val / 0 / PC)
//   6. MUX(ALUSrc):  选择 ALU B端口输入 (rs2_val / 立即数)
//   7. ALU: A op B → ALUResult + Zero 标志
//   8. DataMemory: ALUResult为地址, rs2_val为写数据 → ReadData
//   9. MUX(MemtoReg): 选择写回数据 (ALUResult / ReadData) → WD3
//   10.RegFile: 若 RegWrite=1, 将 WD3 写入 rd
//   11.Next-PC 逻辑: 根据 Branch/Jump/JALR/halt 决定下个 PC
//   所有以上步骤在单个 25MHz 时钟周期内完成.
//
// 【Debug 端口 (全部直通到 TopDebug)】
//   DebugController 可以直接读寄存器、读/写指令内存、读/写数据内存,
//   以及通过 cpu_halt/cpu_step/cpu_reset 控制 CPU 执行.
//
// 【输入/输出端口分类】
//   A) 时钟和复位
//   B) Debug 控制: cpu_halt, cpu_step, cpu_reset
//   C) Debug 寄存器: dbg_reg_addr → dbg_reg_data
//   D) Debug 指令内存: inst_dbg_* → inst_rd_data
//   E) Debug 数据内存: dmem_dbg_* → dmem_rd_data
//   F) Debug PC: dbg_pc
//   G) 外设 IO: SwitchIn, ButtonIn, LEDOut, SegOut
// =============================================================================
`timescale 1ns / 1ps

module CPUTop (
    input         clk,              // CPU 时钟 (25MHz, 来自TopDebug的BUFG输出)
    input         rst_n,            // 异步复位 (低有效, 已合并物理复位和软复位)

    // Debug: CPU 控制
    input         cpu_halt,         // 1=暂停CPU (来自DebugController)
    input         cpu_step,         // 1=单步放行一个周期 (当cpu_halt=1时)
    input         cpu_reset,        // 1=调试软复位 (来自DebugController)

    // Debug: 寄存器读取
    input  [4:0]  dbg_reg_addr,     // Debug 选中的寄存器编号
    output [31:0] dbg_reg_data,     // Debug 读出的寄存器值

    // Debug: 指令内存读写
    input         inst_dbg_en,      // 1=Debug访问指令内存
    input         inst_wr_en,       // 1=Debug写使能
    input  [31:0] inst_dbg_addr,    // Debug 字节地址
    input  [31:0] inst_wr_data,     // Debug 写入数据
    output [31:0] inst_rd_data,     // Debug 读出数据

    // Debug: 数据内存读写
    input         dmem_dbg_en,      // 1=Debug访问数据内存
    input         dmem_wr_en,       // 1=Debug写使能
    input  [31:0] dmem_dbg_addr,    // Debug 字节地址
    input  [31:0] dmem_wr_data,     // Debug 写入数据
    output [31:0] dmem_rd_data,     // Debug 读出数据

    // Debug: PC 读出口
    output [31:0] dbg_pc,           // 当前PC值 (送给DebugController)

    // 外设 IO (直连FPGA引脚)
    input  [31:0] SwitchIn,         // 拨码开关
    input  [31:0] ButtonIn,         // 按键
    output [31:0] LEDOut,           // LED
    output [31:0] SegOut            // 数码管
);

    // ===========================
    // 内部信号定义
    // ===========================
    // Ifetch 输出
    wire [31:0] PC, PCPlus4, inst;

    // Decoder 输出
    wire        RegWrite, ALUSrc, MemtoReg, MemWrite;
    wire        Branch, Jump, JALRSrc;
    wire [1:0]  ALUOp;
    wire [3:0]  ALUControl;

    // RegFile 输出
    wire [31:0] rs1_val, rs2_val;

    // ImmGen 输出
    wire [31:0] Imm;

    // ALU 输入选择
    wire [31:0] ALU_A, ALU_B;

    // ALU 输出
    wire [31:0] ALUResult;
    wire        Zero;

    // DataMemory 输出
    wire [31:0] ReadData;

    // 写回数据
    wire [31:0] WD3;

    // 分支控制
    wire        BranchTaken;

    // Next-PC
    wire [31:0] JumpTarget, BranchTarget, JALRTarget;
    wire        PCSrc;
    wire        cpu_halt_effective;  // 实际生效的 halt 信号

    // ===========================
    // 子模块实例化
    // ===========================

    // --- Ifetch: 取指 (PC + 指令内存) ---
    Ifetch #(
        .INIT_FILE("../assembly/batch_test.hex")
    ) uIfetch (
        .clk          (clk),
        .rst_n        (rst_n),
        .cpu_halt     (cpu_halt_effective),
        .cpu_reset    (cpu_reset),
        .PCSrc        (PCSrc),
        .Jump         (Jump),
        .JALRSrc      (JALRSrc),
        .BranchTarget (BranchTarget),
        .JumpTarget   (JumpTarget),
        .JALRTarget   (JALRTarget),
        .PC           (PC),
        .inst         (inst),
        .PCPlus4      (PCPlus4),
        // Debug
        .inst_dbg_en  (inst_dbg_en),
        .inst_wr_en   (inst_wr_en),
        .inst_dbg_addr(inst_dbg_addr),
        .inst_wr_data (inst_wr_data),
        .inst_rd_data (inst_rd_data)
    );

    // --- Decoder: 译码 + 控制信号生成 ---
    Decoder uDecoder (
        .inst       (inst),
        .RegWrite   (RegWrite),
        .ALUSrc     (ALUSrc),
        .MemtoReg   (MemtoReg),
        .MemWrite   (MemWrite),
        .Branch     (Branch),
        .Jump       (Jump),
        .JALRSrc    (JALRSrc),
        .ALUOp      (ALUOp),
        .ALUControl (ALUControl)
    );

    // --- ImmGen: 立即数生成 ---
    ImmGen uImmGen (
        .inst (inst),
        .Imm  (Imm)
    );

    // --- RegFile: 寄存器堆 ---
    RegFile uRegFile (
        .clk           (clk),
        .rst_n         (rst_n),
        .RegWrite      (RegWrite),
        .rs1_addr      (inst[19:15]),
        .rs2_addr      (inst[24:20]),
        .rd_addr       (inst[11:7]),
        .WD3           (WD3),
        .rs1_val       (rs1_val),
        .rs2_val       (rs2_val),
        // Debug
        .dbg_reg_addr  (dbg_reg_addr),
        .dbg_reg_data  (dbg_reg_data)
    );

    // ===========================
    // ALU 输入 MUX
    // ===========================
    // ALUSrcA: 选择 ALU A 输入
    //   LUI:  A=0  (rd = 0 + imm = imm)
    //   AUIPC: A=PC (rd = PC + imm)
    //   其他:  A=rs1_val
    wire isLUI   = (inst[6:0] == 7'b0110111);
    wire isAUIPC = (inst[6:0] == 7'b0010111);

    assign ALU_A = isLUI   ? 32'd0   :
                   isAUIPC ? PC      :
                             rs1_val;

    // ALUSrc: 选择 ALU B 输入
    //   0: rs2_val (R-type, B-type)
    //   1: Imm     (I-type, S-type, U-type, J-type)
    assign ALU_B = ALUSrc ? Imm : rs2_val;

    // --- ALU: 算数逻辑单元 ---
    ALU uALU (
        .A          (ALU_A),
        .B          (ALU_B),
        .ALUControl (ALUControl),
        .ALUResult  (ALUResult),
        .Zero       (Zero)
    );

    // --- DataMemory: 数据内存 + MMIO ---
    DataMemory uDataMemory (
        .clk           (clk),
        .rst_n         (rst_n),
        .MemWrite      (MemWrite),
        .Addr          (ALUResult),
        .WriteData     (rs2_val),
        .ReadData      (ReadData),
        .SwitchIn      (SwitchIn),
        .ButtonIn      (ButtonIn),
        .LEDOut        (LEDOut),
        .SegOut        (SegOut),
        // Debug
        .dmem_dbg_en   (dmem_dbg_en),
        .dmem_wr_en    (dmem_wr_en),
        .dmem_dbg_addr (dmem_dbg_addr),
        .dmem_wr_data  (dmem_wr_data),
        .dmem_rd_data  (dmem_rd_data)
    );

    // ===========================
    // 写回数据 MUX (MemtoReg)
    // ===========================
    // 0: ALUResult → 大部分指令
    // 1: ReadData  → Load 指令
    assign WD3 = MemtoReg ? ReadData : ALUResult;

    // ===========================
    // 分支条件判断
    // ===========================
    wire [2:0] funct3 = inst[14:12];
    assign BranchTaken = (funct3 == 3'b000) ? (rs1_val == rs2_val) :                       // BEQ
                         (funct3 == 3'b001) ? (rs1_val != rs2_val) :                       // BNE
                         (funct3 == 3'b100) ? ($signed(rs1_val) < $signed(rs2_val)) :      // BLT
                         (funct3 == 3'b101) ? ($signed(rs1_val) >= $signed(rs2_val)) :     // BGE
                         (funct3 == 3'b110) ? (rs1_val < rs2_val) :                        // BLTU
                         (funct3 == 3'b111) ? (rs1_val >= rs2_val) :                       // BGEU
                         1'b0;

    // PCSrc: 当 Branch 指令且条件满足时才跳转
    assign PCSrc = Branch && BranchTaken;

    // ===========================
    // Next-PC 地址计算
    // ===========================
    assign BranchTarget = PC + Imm;      // B-type: PC + 分支偏移
    assign JumpTarget   = PC + Imm;      // J-type: PC + JAL偏移
    // JALR: (rs1 + imm) 且最低位清零 (RISC-V 要求2字节对齐)
    assign JALRTarget   = {rs1_val + Imm}[31:1], 1'b0;

    // ===========================
    // cpu_halt 与 cpu_step 合并逻辑
    // ===========================
    // cpu_step 优先级高于 cpu_halt:
    //   当 cpu_halt=1 且 cpu_step=1 → CPU 放行一个周期 (单步)
    //   当 cpu_halt=1 且 cpu_step=0 → CPU 暂停
    //   当 cpu_halt=0           → CPU 全速运行
    assign cpu_halt_effective = cpu_halt & ~cpu_step;

    // ===========================
    // Debug PC 输出
    // ===========================
    assign dbg_pc = PC;

endmodule

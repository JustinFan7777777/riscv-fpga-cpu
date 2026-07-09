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
//   所有以上步骤在单个 12.5MHz 时钟周期内完成.
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
    input         clk,              // CPU 时钟 (12.5MHz, 来自TopDebug的BUFG输出)
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

    // 外设 IO (宽度匹配 EGO1 开发板)
    input  [15:0] SwitchIn,         // 拨码开关: [7:0]=左8, [15:8]=右8
    input  [4:0]  ButtonIn,         // 按键: [4:0]=5个按键
    output [15:0] LEDOut,           // LED: [15:0]=16个LED
    output [7:0]  seg_cs,           // 数码管位选 (8位, 共阳极=低有效)
    output [7:0]  seg_data_0,       // 数码管段选组0 (左4位数字)
    output [7:0]  seg_data_1,       // 数码管段选组1 (右4位数字)

    // VGA 像素时钟 (直通 DataMemory 帧缓冲 Port B)
    input         clk_vga,          // 25MHz VGA 像素时钟

    // VGA 帧缓冲接口 (直通 DataMemory ↔ VGA)
    input  [11:0] vga_fb_addr,      // VGA → DataMemory: 帧缓冲读地址
    output [15:0] vga_fb_data       // DataMemory → VGA: 帧缓冲读数据
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
    wire [31:0] jalr_sum;               // JALR加法中间结果
    wire        PCSrc;
    wire        cpu_halt_effective;  // 实际生效的 halt 信号
    wire        cpu_write_enable;    // halt 时禁止重复写回同一条指令

    // ===========================
    // 子模块实例化
    // ===========================

    // --- Ifetch: 取指 (PC + 指令内存) ---
    // INIT_FILE 使用 Ifetch.v 默认值 "batch_test.txt" (与verilog同目录)
    Ifetch uIfetch (
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
        .RegWrite      (RegWrite && cpu_write_enable),
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
    // ALUSrcA: 选择 ALU A 端口输入 (3选1)
    //   LUI:   A=0       → ALUResult = 0 + imm = imm (加载立即数)
    //   AUIPC: A=PC      → ALUResult = PC + imm (PC相对寻址)
    //   其他:   A=rs1_val → ALUResult = rs1 OP rs2/imm (正常运算)
    // 注: 此处用 opcode 直接判断, 而非 Decoder 信号, 因为 LUI/AUIPC 的
    //      ALU A 选择与 I-type/R-type 不同, 需要独立的快速译码
    // ===== INCLASS_MUX_A: 现场设计 — 如需新ALU_A来源，在此MUX添加分支 =====
    // 模板: wire isNEW = (inst[6:0] == 7'bXXXXXXX);
    //       assign ALU_A = ... ? ... : isNEW ? new_source : rs1_val;
    wire isLUI   = (inst[6:0] == 7'b0110111);
    wire isAUIPC = (inst[6:0] == 7'b0010111);

    assign ALU_A = isLUI   ? 32'd0   :
                   isAUIPC ? PC      :
                             rs1_val;

    // ALUSrc: 选择 ALU B 端口输入 (2选1)
    //   0: rs2_val → R-type(寄存器-寄存器运算), B-type(分支比较)
    //   1: Imm     → I-type(立即数运算), S-type(存储偏移), U-type, J-type
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
        .clk_vga       (clk_vga),
        .MemWrite      (MemWrite && cpu_write_enable),
        .Addr          (ALUResult),
        .WriteData     (rs2_val),
        .ReadData      (ReadData),
        .SwitchIn      (SwitchIn),
        .ButtonIn      (ButtonIn),
        .LEDOut        (LEDOut),
        .seg_cs        (seg_cs),
        .seg_data_0    (seg_data_0),
        .seg_data_1    (seg_data_1),
        // Debug
        .dmem_dbg_en   (dmem_dbg_en),
        .dmem_wr_en    (dmem_wr_en),
        .dmem_dbg_addr (dmem_dbg_addr),
        .dmem_wr_data  (dmem_wr_data),
        .dmem_rd_data  (dmem_rd_data),
        // VGA 帧缓冲读口 (Port B, 25MHz)
        .vga_fb_addr   (vga_fb_addr),
        .vga_fb_data   (vga_fb_data)
    );

    // ===========================
    // 写回数据 MUX (3选1: PC+4 / ReadData / ALUResult)
    // ===========================
    // JAL/JALR: 需要把返回地址(PC+4)保存到rd → 选通PCPlus4
    //   - Jump=1(JAL)或JALRSrc=1(JALR)时, JALWDSrc=1
    //   - 优先级最高, 因为MemtoReg可能同时为1(虽然实际不会)
    // Load:     需要把内存读出的数据写回rd → 选通ReadData
    //   - MemtoReg=1, 由Decoder根据opcode=0000011设置
    // 其他:      ALU计算结果直接写回rd → 选通ALUResult
    //   - R-type, I-type ALU, U-type, 等
    // ===== INCLASS_MUX_WD3: 现场设计 — 如需新WD3来源，在此MUX添加分支 =====
    // 优先级: JAL/JALR(PC+4) > Load(ReadData) > 默认(ALUResult)
    wire JALWDSrc = Jump | JALRSrc;
    assign WD3 = JALWDSrc ? PCPlus4 :
                 MemtoReg ? ReadData : ALUResult;

    // ===========================
    // 分支条件判断 (组合逻辑, 与ALU并行)
    // ===========================
    // 根据 funct3 对 rs1_val 和 rs2_val 做比较, 产生 BranchTaken
    // 注: 不使用 ALU 的 Zero 标志, 而是直接在CPUTop做比较 —
    //     这样可以并行进行, 不依赖ALU结果, 路径更短
    wire [2:0] funct3 = inst[14:12];
    assign BranchTaken = (funct3 == 3'b000) ? (rs1_val == rs2_val) :                       // BEQ
                         (funct3 == 3'b001) ? (rs1_val != rs2_val) :                       // BNE
                         (funct3 == 3'b100) ? ($signed(rs1_val) < $signed(rs2_val)) :      // BLT
                         (funct3 == 3'b101) ? ($signed(rs1_val) >= $signed(rs2_val)) :     // BGE
                         (funct3 == 3'b110) ? (rs1_val < rs2_val) :                        // BLTU
                         (funct3 == 3'b111) ? (rs1_val >= rs2_val) :                       // BGEU
                         1'b0;

    // PCSrc: 1=条件分支且条件满足 → Ifetch 使用 BranchTarget 作为 NextPC
    //       Branch=1(Decoder判定当前是B-type), BranchTaken=1(比较结果成立)
    assign PCSrc = Branch && BranchTaken;

    // ===========================
    // Next-PC 地址计算 (三种跳转目标地址)
    // ===========================
    // BranchTarget: B-type PC相对跳转 → PC + 符号扩展立即数
    assign BranchTarget = PC + Imm;
    // JumpTarget:   J-type JAL跳转 → PC + 符号扩展立即数
    assign JumpTarget   = PC + Imm;
    // JALRTarget:   I-type JALR跳转 → (rs1 + 符号扩展立即数), 最低位清零
    //   RISC-V规范要求JALR目标地址的LSB=0(2字节对齐), 用中间wire jalr_sum
    //   避免Vivado 2017.4不支持表达式part-select的语法限制
    assign jalr_sum     = rs1_val + Imm;
    assign JALRTarget   = {jalr_sum[31:1], 1'b0};

    // ===========================
    // cpu_halt 与 cpu_step 合并逻辑
    // ===========================
    // DebugController 发出 cpu_halt(想暂停) 和 cpu_step(单步脉冲):
    //   cpu_halt=0          → CPU 全速运行 (正常运行模式)
    //   cpu_halt=1, step=1  → cpu_halt_effective=0, CPU放行一拍 (单步)
    //   cpu_halt=1, step=0  → cpu_halt_effective=1, PC冻结   (暂停)
    // 注: cpu_step是一个持续8个100MHz周期的脉冲, 刚好覆盖1个12.5MHz CPU周期
    assign cpu_halt_effective = cpu_halt & ~cpu_step;
    assign cpu_write_enable = ~cpu_halt_effective;

    // ===========================
    // Debug PC 输出
    // ===========================
    assign dbg_pc = PC;

endmodule

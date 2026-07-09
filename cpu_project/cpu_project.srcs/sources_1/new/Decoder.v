// =============================================================================
// Module      : Decoder.v
// Description : Instruction Decoder + Control Unit for RISC-V RV32I
// =============================================================================
//
// ================================ 中文说明 ================================
// 【功能】RISC-V RV32I 指令译码器 —— 根据 32-bit 指令码生成所有数据通路控制信号。
//         包含两个子模块: 主译码器(Main Decoder) + ALU译码器(ALU Decoder)。
//
// 【在 CPU 数据通路中的位置】
//   Ifetch(inst) ──▶ Decoder ──▶ 控制信号散布到整个数据通路
//                      │
//                      ├──▶ RegFile: RegWrite, rs1_addr, rs2_addr, rd_addr
//                      ├──▶ ALU:     ALUControl[3:0]
//                      ├──▶ MUXes:   ALUSrc, MemtoReg
//                      ├──▶ DMem:    MemWrite
//                      └──▶ PC:      Branch, Jump, JALRSrc
//
// 【主译码器输出 (Main Decoder)】
//   信号      | 作用
//   RegWrite  | 1=写寄存器堆
//   ALUSrc    | 0=ALU B端口来自rs2, 1=ALU B端口来自立即数
//   MemtoReg  | 0=写回数据来自ALU结果, 1=写回数据来自内存
//   MemWrite  | 1=写数据内存
//   Branch    | 1=条件分支(BEQ/BNE等), PC可被分支目标覆盖
//   Jump      | 1=JAL跳转, PC=PC+imm
//   JALRSrc   | 1=JALR跳转, PC=rs1+imm
//   ALUOp[1:0]| 传给ALU译码器,决定运算子类型: 00=加法类 01=分支(减法) 10=R-type 11=I-type-ALU
//
// 【ALU译码器 (ALU Decoder)】
//   根据 ALUOp + funct3 + funct7[5] 生成 4-bit ALUControl:
//   ALUControl[3:0] → ALU的10种运算之一 (见 ALU.v 说明)
//   ALUOp=00时无条件为ADD(用于lw/sw/lui/auipc/jal的地址计算)
//   ALUOp=01时为SUB(用于分支比较)
//   ALUOp=10时根据funct3+funct7[5]查表(R-type指令)
//   ALUOp=11时根据funct3查表(I-type ALU指令, funct7[5]用于SRAI区别)
//
// 【指令编码速查 (RISC-V RV32I opcode)】
//   opcode[6:0] | 指令类型    | 举例
//   0110011      | R-type     | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
//                                MUL (RV32M subset)
//   0010011      | I-type ALU | ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU
//   0000011      | I-type Load| LW, LH, LHU, LB, LBU
//   0100011      | S-type     | SW, SH, SB
//   1100011      | B-type     | BEQ, BNE, BLT, BGE, BLTU, BGEU
//   0110111      | U-type LUI | LUI
//   0010111      | U-type AUIPC| AUIPC
//   1101111      | J-type     | JAL
//   1100111      | I-type Jump| JALR
//
// 【funct3 编码速查】
//   funct3 | ALU运算 | R-type指令 | I-type指令
//   000    | ADD/SUB | ADD/SUB    | ADDI
//   001    | SLL     | SLL        | SLLI
//   010    | SLT     | SLT        | SLTI
//   011    | SLTU    | SLTU       | SLTIU
//   100    | XOR     | XOR        | XORI
//   101    | SRL/SRA | SRL/SRA    | SRLI/SRAI (由funct7[5]区分)
//   110    | OR      | OR         | ORI
//   111    | AND     | AND        | ANDI
//
//   SPECIAL: funct7[5]=1 时 ADD→SUB, SRL→SRA, SRLI→SRAI
//            funct7=0000001 且 funct3=000 时 ADD→MUL
// =============================================================================
`timescale 1ns / 1ps

module Decoder (
    input  [31:0] inst,         // 32-bit 指令码
    output        RegWrite,     // 寄存器写使能
    output        ALUSrc,       // ALU B端口选择: 0=rs2, 1=立即数
    output        MemtoReg,     // 写回数据选择: 0=ALU结果, 1=内存数据
    output        MemWrite,     // 数据内存写使能
    output        Branch,       // 条件分支指令
    output        Jump,         // JAL 跳转
    output        JALRSrc,      // JALR 跳转
    output [1:0]  ALUOp,        // ALU操作类型 (传给ALU Decoder)
    output [3:0]  ALUControl    // ALU控制码 (直接连ALU)
);

    // ===========================
    // 从指令中提取字段
    // ===========================
    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire       funct7_5 = inst[30]; // funct7第5位,用于区分ADD/SUB, SRL/SRA
    wire       is_mul = (inst[31:25] == 7'b0000001) && (funct3 == 3'b000);

    // ===========================
    // 主译码器
    // ===========================
    // 根据 opcode 生成 8 个控制信号:
    //   RegWrite (写寄存器), ALUSrc (0=rs2, 1=立即数),
    //   MemtoReg (0=ALU结果, 1=内存数据), MemWrite (写内存),
    //   Branch (条件分支), Jump (JAL跳转), JALRSrc (JALR跳转),
    //   ALUOp[1:0] (传给ALU译码器):
    //     00=ADD类(lw/sw/lui/auipc/jal/jalr地址计算)
    //     01=SUB(分支比较用)
    //     10=R-type(查funct3+funct7)
    //     11=I-type ALU(查funct3)
    reg  regwrite_r, alusrc_r, memtoreg_r, memwrite_r;
    reg  branch_r, jump_r, jalrsrc_r;
    reg [1:0] aluop_r;

    always @(*) begin
        case (opcode)
            // R-type: ADD, SUB, MUL, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
            // 数据流: RegFile(rs1,rs2) → ALU → RegFile(rd)
            // ALUSrc=0 → ALU_B=rs2; ALUOp=10 → 查funct3+funct7
            7'b0110011: begin
                regwrite_r = 1'b1;    // 写回寄存器
                alusrc_r   = 1'b0;    // B端口来自rs2
                memtoreg_r = 1'b0;    // 写回数据来自ALU
                memwrite_r = 1'b0;    // 不写内存
                branch_r   = 1'b0;    // 非分支
                jump_r     = 1'b0;
                jalrsrc_r  = 1'b0;
                aluop_r    = 2'b10;   // R-type: ALU操作由funct3+funct7决定
            end

            // I-type ALU: ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU
            // 数据流: RegFile(rs1) + ImmGen → ALU → RegFile(rd)
            // ALUSrc=1 → ALU_B=立即数; ALUOp=11 → 查funct3
            7'b0010011: begin
                regwrite_r = 1'b1;
                alusrc_r   = 1'b1;    // B端口来自立即数
                memtoreg_r = 1'b0;
                memwrite_r = 1'b0;
                branch_r   = 1'b0;
                jump_r     = 1'b0;
                jalrsrc_r  = 1'b0;
                aluop_r    = 2'b11;   // I-type ALU: ALU操作由funct3决定
            end

            // I-type Load: LW, LH, LHU, LB, LBU
            // 数据流: RegFile(rs1)+ImmGen → ALU(ADD计算地址) → DMem(读) → RegFile(rd)
            // ALUOp=00 → 无条件ADD; MemtoReg=1 → WD3来自内存而非ALU
            7'b0000011: begin
                regwrite_r = 1'b1;    // 写回寄存器
                alusrc_r   = 1'b1;    // B端口来自立即数 (地址偏移)
                memtoreg_r = 1'b1;    // 写回数据来自内存!
                memwrite_r = 1'b0;    // 读内存,不写
                branch_r   = 1'b0;
                jump_r     = 1'b0;
                jalrsrc_r  = 1'b0;
                aluop_r    = 2'b00;   // 地址计算用ADD
            end

            // S-type Store: SW, SH, SB
            // 数据流: RegFile(rs1)+ImmGen → ALU(ADD计算地址) → DMem(写rs2值)
            // RegWrite=0 → 不写寄存器; MemWrite=1 → 写内存
            7'b0100011: begin
                regwrite_r = 1'b0;    // 不写寄存器
                alusrc_r   = 1'b1;    // B端口来自立即数 (地址偏移)
                memtoreg_r = 1'b0;    // 不写回 (don't care)
                memwrite_r = 1'b1;    // 写内存!
                branch_r   = 1'b0;
                jump_r     = 1'b0;
                jalrsrc_r  = 1'b0;
                aluop_r    = 2'b00;   // 地址计算用ADD
            end

            // B-type Branch: BEQ, BNE, BLT, BGE, BLTU, BGEU
            // 数据流: RegFile(rs1,rs2) → 比较 → PC条件跳转
            // RegWrite=0 → 分支不写寄存器; Branch=1 → 使能条件跳转
            // 注: 实际比较在CPUTop中用funct3直接完成, ALU减法结果未使用
            7'b1100011: begin
                regwrite_r = 1'b0;    // 分支不写寄存器
                alusrc_r   = 1'b0;    // B端口来自rs2 (做比较)
                memtoreg_r = 1'b0;
                memwrite_r = 1'b0;
                branch_r   = 1'b1;    // 条件分支!
                jump_r     = 1'b0;
                jalrsrc_r  = 1'b0;
                aluop_r    = 2'b01;   // 分支比较用减法
            end

            // U-type LUI: 加载高位立即数
            // 数据流: 0 + ImmGen → ALU → RegFile(rd)
            // 注: CPUTop中ALUSrcA检测到LUI时选通0作为ALU_A, 所以A+B=0+imm=imm
            7'b0110111: begin
                regwrite_r = 1'b1;
                alusrc_r   = 1'b1;
                memtoreg_r = 1'b0;
                memwrite_r = 1'b0;
                branch_r   = 1'b0;
                jump_r     = 1'b0;
                jalrsrc_r  = 1'b0;
                aluop_r    = 2'b00;   // ADD: 0 + imm = imm
            end

            // U-type AUIPC: PC+立即数
            // 数据流: PC + ImmGen → ALU → RegFile(rd)
            // 注: CPUTop中ALUSrcA检测到AUIPC时选通PC作为ALU_A
            7'b0010111: begin
                regwrite_r = 1'b1;
                alusrc_r   = 1'b1;
                memtoreg_r = 1'b0;
                memwrite_r = 1'b0;
                branch_r   = 1'b0;
                jump_r     = 1'b0;
                jalrsrc_r  = 1'b0;
                aluop_r    = 2'b00;   // ADD: PC + imm
            end

            // J-type JAL: 跳转并链接
            // 数据流: PC → Ifetch.NextPC(PC+imm); PC+4 → RegFile(rd)
            // Jump=1 → Next-PC使用JumpTarget; WD3=PC+4 (由CPUTop的JALWDSrc控制)
            7'b1101111: begin
                regwrite_r = 1'b1;    // JAL写回PC+4到rd
                alusrc_r   = 1'b1;
                memtoreg_r = 1'b0;
                memwrite_r = 1'b0;
                branch_r   = 1'b0;
                jump_r     = 1'b1;    // JAL跳转! PC=PC+imm
                jalrsrc_r  = 1'b0;
                aluop_r    = 2'b00;
            end

            // I-type JALR: 寄存器跳转并链接
            // 数据流: rs1+imm → Ifetch.NextPC; PC+4 → RegFile(rd)
            // JALRSrc=1 → Next-PC使用JALRTarget; WD3=PC+4
            7'b1100111: begin
                regwrite_r = 1'b1;    // JALR写回PC+4到rd
                alusrc_r   = 1'b1;
                memtoreg_r = 1'b0;
                memwrite_r = 1'b0;
                branch_r   = 1'b0;
                jump_r     = 1'b0;
                jalrsrc_r  = 1'b1;    // JALR跳转! PC=rs1+imm (LSB清零)
                aluop_r    = 2'b00;
            end

            // ===== INCLASS_MAIN: 现场设计 — 新opcode分支插在此注释上方 =====
            // 模板 (复制上方类似指令格式修改):
            // 7'bXXXXXXX: begin  // ← 教师给的opcode
            //     regwrite_r = 1'bX; alusrc_r = 1'bX; memtoreg_r = 1'bX;
            //     memwrite_r = 1'bX; branch_r = 1'bX; jump_r = 1'bX;
            //     jalrsrc_r = 1'bX;  aluop_r = 2'bXX;
            // end
            // ALUOp速查: 00=强制ADD  01=强制SUB  10=R-type(查funct表)  11=I-type-ALU(查funct表)
            // 非法或未定义指令: 全部控制信号置0 = NOP
            default: begin
                regwrite_r = 1'b0;
                alusrc_r   = 1'b0;
                memtoreg_r = 1'b0;
                memwrite_r = 1'b0;
                branch_r   = 1'b0;
                jump_r     = 1'b0;
                jalrsrc_r  = 1'b0;
                aluop_r    = 2'b00;
            end
        endcase
    end

    // 输出主译码器信号
    assign RegWrite = regwrite_r;
    assign ALUSrc   = alusrc_r;
    assign MemtoReg = memtoreg_r;
    assign MemWrite = memwrite_r;
    assign Branch   = branch_r;
    assign Jump     = jump_r;
    assign JALRSrc  = jalrsrc_r;
    assign ALUOp    = aluop_r;

    // ===========================
    // ALU 译码器
    // ===========================
    reg [3:0] alucontrol_r;

    always @(*) begin
        case (ALUOp)
            2'b00: alucontrol_r = 4'b0000;  // ADD (lw/sw/lui/auipc/jal/jalr地址计算)

            2'b01: alucontrol_r = 4'b0001;  // SUB (用于分支比较, 产生Zero标志)

            2'b10: begin  // R-type: 根据funct3和funct7[5]决定运算
                // ===== INCLASS_ALU_R: 现场设计 — R-type新运算改此funct3表中对应行 =====
                // 模式: 3'bXXX: alucontrol_r = funct7_5 ? 4'b新编码 : 4'b旧编码;
                case (funct3)
                    3'b000: alucontrol_r = is_mul ? 4'b1010 : (funct7_5 ? 4'b0001 : 4'b0000); // MUL : SUB : ADD
                    3'b001: alucontrol_r = 4'b0101; // SLL
                    3'b010: alucontrol_r = 4'b1000; // SLT
                    3'b011: alucontrol_r = 4'b1001; // SLTU
                    3'b100: alucontrol_r = 4'b0100; // XOR
                    3'b101: alucontrol_r = funct7_5 ? 4'b0111 : 4'b0110; // SRA : SRL
                    3'b110: alucontrol_r = 4'b0011; // OR
                    3'b111: alucontrol_r = 4'b0010; // AND
                    default:alucontrol_r = 4'b0000;
                endcase
            end

            2'b11: begin  // I-type ALU: 根据funct3决定运算
                // ===== INCLASS_ALU_I: 现场设计 — I-type新运算改此funct3表中对应行 =====
                case (funct3)
                    3'b000: alucontrol_r = 4'b0000; // ADDI
                    3'b001: alucontrol_r = 4'b0101; // SLLI
                    3'b010: alucontrol_r = 4'b1000; // SLTI
                    3'b011: alucontrol_r = 4'b1001; // SLTIU
                    3'b100: alucontrol_r = 4'b0100; // XORI
                    3'b101: alucontrol_r = funct7_5 ? 4'b0111 : 4'b0110; // SRAI : SRLI
                    3'b110: alucontrol_r = 4'b0011; // ORI
                    3'b111: alucontrol_r = 4'b0010; // ANDI
                    default:alucontrol_r = 4'b0000;
                endcase
            end

            default: alucontrol_r = 4'b0000;
        endcase
    end

    assign ALUControl = alucontrol_r;

endmodule

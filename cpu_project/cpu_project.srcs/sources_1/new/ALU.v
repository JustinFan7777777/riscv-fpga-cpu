// =============================================================================
// Module      : ALU.v
// Description : 32-bit Arithmetic Logic Unit for RISC-V RV32I
// =============================================================================
//
// ================================ 中文说明 ================================
// 【功能】RISC-V RV32I 算术逻辑单元 —— 根据 ALUControl 信号对两个 32-bit
//        操作数执行加/减/与/或/异或/移位/比较等操作，输出计算结果和 Zero 标志。
//
// 【在 CPU 数据通路中的位置】
//   RegFile(rs1) ──▶ ALU A端口 ──┐
//   RegFile(rs2)  ──▶ MUX ───────▶ ALU B端口 ──▶ 运算 ──▶ ALUResult (写回RegFile)
//   ImmGen输出 ─────▶ MUX (ALUSrc选择)
//   Decoder ────────▶ ALUControl[3:0] (选择做什么运算)
//
// 【支持的运算 (ALUControl 编码)】
//   0000: ADD  加       0011: OR   位或      0110: SRL  逻辑右移
//   0001: SUB  减       0100: XOR  位异或    0111: SRA  算术右移
//   0010: AND  位与     0101: SLL  逻辑左移  1000: SLT  有符号比较
//                                            1001: SLTU 无符号比较
//
// 【操作数说明】
//   - 移位指令(SLL/SRL/SRA)只使用 B[4:0] 低5位作为移位量 (RISC-V 规范)
//   - SLT: 将A,B视作有符号数，A<B则结果为1，否则0
//   - SLTU: 将A,B视作无符号数，A<B则结果为1，否则0
//   - SUB指令由 funct7[5]=1 配合 funct3=000 来区分 (ADD的funct7[5]=0)
//
// 【Zero 标志】
//   当 ALUResult == 0 时 Zero=1，供 Branch 指令判断用 (BEQ/BNE等)
// =============================================================================
`timescale 1ns / 1ps

module ALU (
    input  [31:0] A,          // 操作数1 (来自 rs1)
    input  [31:0] B,          // 操作数2 (来自 rs2 或立即数，由ALUSrc选择)
    input  [ 3:0] ALUControl, // ALU 控制码: 选择哪种运算
    output reg [31:0] ALUResult, // 运算结果
    output        Zero        // 结果为0标志 (供Branch指令使用)
);

    // Zero 标志: 组合逻辑, 当 ALUResult==0 时拉高
    // 注: 当前CPUTop中分支判断使用直接比较(rs1==rs2等), 未使用此Zero标志;
    //     保留Zero作为备用的零检测输出, 供未来可能的优化或调试使用
    assign Zero = (ALUResult == 32'd0);

    // ===========================
    // ISA 扩展: 组合逻辑函数 (POPCNT / CLZ / CTZ)
    // ===========================

    // popcount: 32-bit 分治法, 5 级加法树, 纯组合逻辑
    function [31:0] popcount;
        input [31:0] x;
        reg [31:0] t;
        begin
            t = (x & 32'h55555555) + ((x >> 1) & 32'h55555555);
            t = (t & 32'h33333333) + ((t >> 2) & 32'h33333333);
            t = (t & 32'h0F0F0F0F) + ((t >> 4) & 32'h0F0F0F0F);
            t = (t & 32'h00FF00FF) + ((t >> 8) & 32'h00FF00FF);
            t = (t & 32'h0000FFFF) + ((t >> 16) & 32'h0000FFFF);
            popcount = t;
        end
    endfunction

    // clz: Count Leading Zeros — 二分查找最高位的1
    // clz(0)=32 (全零输入特殊处理)
    function [31:0] clz;
        input [31:0] x;
        reg [31:0] n;
        begin
            if (x == 32'd0) begin
                clz = 32'd32;
            end else begin
                n = 32'd0;
                if (x[31:16] == 16'd0) begin n = n + 16; x = x << 16; end
                if (x[31:24] == 8'd0)  begin n = n + 8;  x = x << 8;  end
                if (x[31:28] == 4'd0)  begin n = n + 4;  x = x << 4;  end
                if (x[31:30] == 2'd0)  begin n = n + 2;  x = x << 2;  end
                if (x[31] == 1'b0)     begin n = n + 1;                 end
                clz = n;
            end
        end
    endfunction

    // ctz: Count Trailing Zeros — 位反转 + CLZ
    function [31:0] ctz;
        input [31:0] x;
        reg [31:0] rev;
        integer i;
        begin
            rev = 32'd0;
            for (i = 0; i < 32; i = i + 1)
                rev = {rev[30:0], x[i]};
            ctz = clz(rev);
        end
    endfunction

    // ALU 主运算逻辑
    always @(*) begin
        case (ALUControl)
            4'b0000: ALUResult = A + B;                   // ADD  / ADDI  / AUIPC
            4'b0001: ALUResult = A - B;                   // SUB
            4'b0010: ALUResult = A & B;                   // AND  / ANDI
            4'b0011: ALUResult = A | B;                   // OR   / ORI
            4'b0100: ALUResult = A ^ B;                   // XOR  / XORI
            4'b0101: ALUResult = A << B[4:0];             // SLL  / SLLI (移位量仅低5位)
            4'b0110: ALUResult = A >> B[4:0];             // SRL  / SRLI (逻辑右移)
            4'b0111: ALUResult = $signed(A) >>> B[4:0];   // SRA  / SRAI (算术右移)
            4'b1000: ALUResult = ($signed(A) < $signed(B)) ? 32'd1 : 32'd0;  // SLT / SLTI
            4'b1001: ALUResult = (A < B) ? 32'd1 : 32'd0;                   // SLTU / SLTIU
            // ===== INCLASS_ALU: 现场设计 — 新ALU运算插在此注释下方 =====
            // ===== ISA 扩展: 硬件加速指令 (funct7=0000001) =====
            // POPCNT — 统计A中1的个数 (分治法, 5级组合逻辑)
            4'b1010: ALUResult = popcount(A);
            // CLZ — 统计前导零个数 (优先编码器)
            4'b1011: ALUResult = clz(A);
            // CTZ — 统计尾部零个数 (位反转 + CLZ)
            4'b1100: ALUResult = ctz(A);
            // 可用编码: 4'b1101 ~ 4'b1111
            default: ALUResult = 32'd0;  // 未定义操作，输出0 (安全默认值)
        endcase
    end

endmodule

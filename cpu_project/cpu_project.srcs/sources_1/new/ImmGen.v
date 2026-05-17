// =============================================================================
// Module      : ImmGen.v
// Description : Immediate Generator for RISC-V RV32I
// =============================================================================
//
// ================================ 中文说明 ================================
// 【功能】从 32-bit 指令码中提取立即数并做符号扩展/高位补零，输出 32-bit 结果。
//
// 【在 CPU 数据通路中的位置】
//   指令码 (来自Ifetch的输出inst) ──▶ ImmGen ──▶ MUX(ALUSrc) ──▶ ALU B端口
//   ImmGen 的输出可能作为: ALU的第二个操作数(I-type)、存储偏移(S-type)、
//   分支偏移(B-type)、PC+imm(JAL/JALR)、或高位立即数(LUI/AUIPC)。
//
// 【RISC-V 六种立即数格式 (名字对应其所在指令类型)】
//   类型  | 指令举例  | 立即数在 inst 中的位分布
//   I-type | ADDI, LW  | inst[31:20] → 符号扩展到32bit
//   S-type | SW        | inst[31:25]拼接inst[11:7] → 符号扩展
//   B-type | BEQ       | inst[31]|inst[7]|inst[30:25]|inst[11:8] 末尾补0 → 符号扩展
//   U-type | LUI       | inst[31:12] 左移12位 (低12位补0)
//   J-type | JAL       | inst[31]|inst[19:12]|inst[20]|inst[30:21] 末尾补0 → 符号扩展
//   I-jump | JALR      | inst[31:20] → 符号扩展 (与I-type相同)
//
//   注意: B-type和J-type的立即数最低位总是0(16-bit对齐), 所以硬件编码时省略了bit0.
//         ImmGen会自动在末尾补0.
//
// 【输入】
//   inst[31:0] — 当前正在译码的 32-bit RISC-V 指令
//
// 【输出】
//   Imm[31:0] — 32-bit 立即数 (已符号扩展或补零)
// =============================================================================
`timescale 1ns / 1ps

module ImmGen (
    input  [31:0] inst,     // 32-bit 指令码
    output [31:0] Imm       // 32-bit 立即数输出
);

    reg [31:0] imm_reg;

    // 根据 opcode[6:0] 判断立即数格式
    always @(*) begin
        case (inst[6:0])
            // I-type: opcode = 0010011 (ADDI/SLLI/ANDI等), 0000011 (LW等), 1100111 (JALR)
            //   imm[11:0] = inst[31:20], 符号扩展到32bit
            7'b0010011,   // I-type ALU
            7'b0000011,   // I-type load (LW/LH/LB等)
            7'b1100111:   // I-type jump (JALR)
                imm_reg = {{20{inst[31]}}, inst[31:20]};

            // S-type: opcode = 0100011 (SW/SH/SB)
            //   imm[11:5] = inst[31:25], imm[4:0] = inst[11:7]
            7'b0100011:
                imm_reg = {{20{inst[31]}}, inst[31:25], inst[11:7]};

            // B-type: opcode = 1100011 (BEQ/BNE/BLT等)
            //   imm[12|10:5|4:1|11] 对应 inst[31|30:25|11:8|7]
            //   末尾补0（指令地址是2字节对齐，硬件中imm[0]=0）
            7'b1100011:
                imm_reg = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};

            // U-type: opcode = 0110111 (LUI), 0010111 (AUIPC)
            //   imm[31:12] = inst[31:12], 低12位补0
            7'b0110111,   // LUI
            7'b0010111:   // AUIPC
                imm_reg = {inst[31:12], 12'b0};

            // J-type: opcode = 1101111 (JAL)
            //   imm[20|10:1|11|19:12] 对应 inst[31|21|30|20|19:12]
            //   末尾补0
            7'b1101111:
                imm_reg = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

            // 默认: 视为I-type (安全fallback)
            default:
                imm_reg = {{20{inst[31]}}, inst[31:20]};
        endcase
    end

    assign Imm = imm_reg;

endmodule

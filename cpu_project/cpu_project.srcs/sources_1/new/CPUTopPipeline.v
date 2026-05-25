// =============================================================================
// Module      : CPUTopPipeline.v
// Description : RISC-V RV32I 五级流水线 CPU 顶层 (IF→ID→EX→MEM→WB)
// =============================================================================
//
// ================================ 中文说明 ================================
// 【功能】五级流水线 RISC-V CPU 顶层模块, 复用单周期的 Decoder/RegFile/ImmGen/
//        ALU/DataMemory 子模块, 新增 Ifetch_Pipe(取指)/PipeRegs(流水线寄存器)/
//        HazardUnit(冒险处理) 三个模块, 串联成完整五级流水线。
//
// 【五级流水线结构】
//   时钟周期:   T1        T2        T3        T4        T5        T6 ...
//   ─────────────────────────────────────────────────────────────────────
//   IF   :  inst1 →  inst2 →  inst3 →  inst4 →  inst5 →  inst6 → ...
//   ID   :           inst1 →  inst2 →  inst3 →  inst4 →  inst5 → ...
//   EX   :                    inst1 →  inst2 →  inst3 →  inst4 → ...
//   MEM  :                             inst1 →  inst2 →  inst3 → ...
//   WB   :                                      inst1 →  inst2 → ...
//
//   同一时刻有 5 条指令在不同阶段执行 (T5 时: inst5在IF, inst4在ID,
//   inst3在EX, inst2在MEM, inst1在WB), 每条指令 5 个周期完成。
//   CPI ≈ 1 (理想情况), 吞吐量是单周期的 5 倍。
//
// 【各阶段职责】
//   IF  (取指): PC → IMem (BRAM寄存器读) → inst, 计算 PC+4
//   ID  (译码): inst → Decoder(控制信号) + RegFile(读rs1/rs2) + ImmGen(立即数)
//   EX  (执行): ALU(运算) + 分支/跳转目标计算 + 分支条件判断
//   MEM (访存): DataMemory(读/写数据内存, MMIO, VGA帧缓冲)
//   WB  (写回): 选择写回数据(ALU结果或内存值) → RegFile(写rd)
//
// 【流水线寄存器 (PipeRegs.v)】
//   每个阶段之间有一组 D 触发器, 在时钟上升沿锁存上一级的输出:
//     IF/ID  : PC+4, inst
//     ID/EX  : 控制信号, rs1/rs2值, 立即数, PC
//     EX/MEM : ALU结果, 写数据(rs2), 分支/跳转信息
//     MEM/WB : 内存读出, ALU结果, 写回控制
//
// 【数据冒险 (Data Hazard / RAW) — 由 HazardUnit 处理】
//   情况: 指令A 写入寄存器 rd, 紧接着指令B 读取同一个寄存器
//   解决: 转发 (Forwarding) — 不等指令A 写回寄存器, 直接从流水线后级
//         "偷"数据给前级用
//   例: add x1, x2, x3    (写x1, 结果在EX/MEM)
//        sub x4, x1, x5    (读x1, 需要EX阶段的值)
//        → HazardUnit 检测到冲突, 把 EX/MEM.ALUResult 直接转发到
//          sub 的 ALU 输入, 省去等待 WB 写回的一拍
//
// 【Load-Use 冒险 — 必须暂停】
//   情况: lw 指令后紧跟一条使用加载值的指令
//   例: lw  x1, 0(x2)     (x1在MEM阶段才读出)
//        add x3, x1, x4    (x1在EX阶段就要用, 来不及!)
//   解决: Stall 1 周期 — 冻结 IF/ID 寄存器, 在 ID/EX 插入一条 NOP,
//        等 lw 的数据从 MEM 回来后再继续
//
// 【控制冒险 (Control Hazard)】
//   情况: 分支指令在 EX 阶段才知道跳不跳, 但 IF 已经取了两条后续指令
//   解决: 假设不跳转 (Predict Not Taken) — 如果分支成立, 把 IF/ID
//         寄存器清零 (flush_ifid → NOP), 相当于那两条错误指令作废,
//         PC 更新为分支目标。代价: 1 周期 penalty。
//
// 【与单周期 CPU 的对比】
//   CPUTop (单周期): 每条指令 1 个长周期完成全部 5 步, CPI=1, 时钟慢
//   CPUTopPipeline:  5 条指令重叠执行, CPI≈1, 但每周期只需完成 1 步,
//                    时钟可以更快, 吞吐量提升 ~5 倍
//
// 【模块实例化清单】
//   Ifetch_Pipe  : 取指 (BRAM 寄存器读, 1 周期延迟由流水线吸收)
//   Decoder      : 译码 + 控制信号 (复用单周期)
//   RegFile      : 寄存器堆 32×32 (复用)
//   ImmGen       : 立即数生成 (复用)
//   PipeRegs     : 4 组流水线寄存器 (新增)
//   HazardUnit   : 转发控制 + Load-Use 检测 (新增)
//   ALU          : 算术逻辑单元 (复用, 含 POPCNT/CLZ/CTZ)
//   DataMemory   : 数据内存 + MMIO + VGA 帧缓冲 (复用)
//
// 【调试接口】
//   与单周期共用一套 Debug 信号 (dbg_reg, inst_dbg, dmem_dbg, dbg_pc),
//   由 TopDebug 层根据 cpu_mode 做 MUX 选择活跃 CPU。
// =============================================================================
`timescale 1ns / 1ps

module CPUTopPipeline (
    input         clk, rst_n, cpu_halt, cpu_step, cpu_reset,
    input  [4:0]  dbg_reg_addr,
    output [31:0] dbg_reg_data,
    input         inst_dbg_en, inst_wr_en,
    input  [31:0] inst_dbg_addr, inst_wr_data,
    output [31:0] inst_rd_data,
    input         dmem_dbg_en, dmem_wr_en,
    input  [31:0] dmem_dbg_addr, dmem_wr_data,
    output [31:0] dmem_rd_data,
    output [31:0] dbg_pc,
    input  [15:0] SwitchIn,
    input  [4:0]  ButtonIn,
    output [15:0] LEDOut,
    output [7:0]  seg_cs, seg_data_0, seg_data_1,
    input         clk_vga,
    input  [11:0] vga_fb_addr,
    output [15:0] vga_fb_data
);

    wire cpu_halt_effective = cpu_halt & ~cpu_step;

    // 复位预热: 复位后 inst_reg 需 1 拍从 BRAM 加载首条指令,
    // 此期间冻结 IF/ID 防止捕获 NOP。仅影响 IF 取指, 不影响已流水化的 NOP。
    reg reset_stall;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reset_stall <= 1'b1;
        else
            reset_stall <= 1'b0;
    end

    // BRAM 读延迟补偿: ctrl_flush 延长 1 拍兜住 inst_reg 中已超前的指令。
    // BRAM 有 1 周期读延迟, inst_reg 比标准 IF 阶段多超前一条指令。
    // 分支在 EX 时, flush_ifid 清除 IF/ID(PC+8), 但 PC+12 已在 inst_reg
    // 中且 1 拍后才出现, 此时 ctrl_flush 已结束 → flush_ifid_delay 兜底。
    reg flush_ifid_delay;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            flush_ifid_delay <= 1'b0;
        else
            flush_ifid_delay <= ctrl_flush;
    end

    // ========================================================================
    // 所有内部信号声明 (必须在模块实例化之前)
    // ========================================================================
    // IF
    wire [31:0] if_pc, if_inst, if_pcplus4;
    wire        stall, flush_ifid, flush_idex, ctrl_flush;
    wire        ex_branch_taken, ex_jump, ex_jalrsrc;
    wire [31:0] ex_branch_target, ex_jump_target, ex_jalr_target;

    // 延长后的 IF 刷新: HazardUnit 原始输出 + 延迟 1 拍的 ctrl_flush
    wire flush_ifid_ext = flush_ifid | flush_ifid_delay;

    // ID
    wire [31:0] id_pc, id_pcplus4, id_inst;
    wire        id_regwrite, id_alusrc, id_memtoreg, id_memwrite;
    wire        id_branch, id_jump, id_jalrsrc;
    wire [3:0]  id_alucontrol; wire [2:0] id_funct3;
    wire [31:0] id_rs1_val, id_rs2_val, id_imm;
    wire [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;

    // EX
    wire [31:0] ex_pc, ex_pcplus4, ex_rs1_val, ex_rs2_val, ex_imm;
    wire [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd_addr;
    wire        ex_regwrite, ex_alusrc, ex_memtoreg, ex_memwrite;
    wire        ex_branch, ex_jump_wire, ex_jalrsrc_wire;
    wire        ex_lui, ex_auipc;      // LUI/AUIPC 标志 (经ID/EX传入)
    wire [3:0]  ex_alucontrol; wire [2:0] ex_funct3;
    wire [31:0] ex_alu_raw, ex_writedata;
    wire [1:0]  forward_a, forward_b;  // ALU输入选择: 00=rs值, 01=EX/MEM转发, 10=MEM/WB转发

    // MEM
    wire [31:0] mem_aluresult, mem_writedata, mem_readdata;
    wire [4:0]  mem_rd_addr;
    wire        mem_regwrite, mem_memtoreg, mem_memwrite;

    // WB
    wire [31:0] wb_readdata, wb_aluresult, wb_wd3;
    wire [4:0]  wb_rd_addr;
    wire        wb_regwrite, wb_memtoreg;

    // ========================================================================
    // IF — 取指 (Ifetch_Pipe: BRAM寄存器读)
    // ========================================================================

    Ifetch_Pipe uIfetch (
        .clk(clk), .rst_n(rst_n), .stall(stall | cpu_halt_effective | reset_stall),
        .flush_ifid(flush_ifid_ext), .branch_taken(ex_branch_taken),
        .jump(ex_jump), .jalrsrc(ex_jalrsrc),
        .branch_target(ex_branch_target), .jump_target(ex_jump_target),
        .jalr_target(ex_jalr_target),
        .pc(if_pc), .inst(if_inst), .pcplus4(if_pcplus4),
        .inst_dbg_en(inst_dbg_en), .inst_wr_en(inst_wr_en),
        .inst_dbg_addr(inst_dbg_addr), .inst_wr_data(inst_wr_data),
        .inst_rd_data(inst_rd_data)
    );
    assign dbg_pc = if_pc;

    // ========================================================================
    // ID — 译码 + 寄存器读 + 立即数生成
    // ========================================================================

    Decoder uDecoder (
        .inst(id_inst), .RegWrite(id_regwrite), .ALUSrc(id_alusrc),
        .MemtoReg(id_memtoreg), .MemWrite(id_memwrite),
        .Branch(id_branch), .Jump(id_jump), .JALRSrc(id_jalrsrc),
        .ALUControl(id_alucontrol)
    );
    assign id_funct3 = id_inst[14:12];

    assign id_rs1_addr = id_inst[19:15];
    assign id_rs2_addr = id_inst[24:20];
    assign id_rd_addr  = id_inst[11:7];

    RegFile uRegFile (
        .clk(clk), .rst_n(rst_n), .RegWrite(wb_regwrite),
        .rs1_addr(id_rs1_addr), .rs2_addr(id_rs2_addr),
        .rd_addr(wb_rd_addr), .WD3(wb_wd3),
        .rs1_val(id_rs1_val), .rs2_val(id_rs2_val),
        .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(dbg_reg_data)
    );

    ImmGen uImmGen (.inst(id_inst), .Imm(id_imm));

    // LUI/AUIPC 检测 (用于 EX 阶段 ALU_A 选择)
    // 单周期 CPUTop 用 inst 直接判断, 流水线需把此信息传到 EX 阶段
    wire id_isLUI   = (id_inst[6:0] == 7'b0110111);
    wire id_isAUIPC = (id_inst[6:0] == 7'b0010111);

    // ========================================================================
    // PipeRegs — 4组流水线寄存器
    // ========================================================================
    PipeRegs uPipeRegs (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush_ifid(flush_ifid_ext), .flush_idex(flush_idex),
        // IF → IF/ID
        .if_pc(if_pc), .if_pcplus4(if_pcplus4), .if_inst(if_inst),
        // ID → ID/EX
        .id_pc(id_pc), .id_pcplus4(id_pcplus4), .id_rs1_val(id_rs1_val),
        .id_rs2_val(id_rs2_val), .id_imm(id_imm),
        .id_rs1_addr(id_rs1_addr), .id_rs2_addr(id_rs2_addr), .id_rd_addr(id_rd_addr),
        .id_regwrite(id_regwrite), .id_alusrc(id_alusrc), .id_memtoreg(id_memtoreg),
        .id_memwrite(id_memwrite), .id_branch(id_branch), .id_jump(id_jump),
        .id_jalrsrc(id_jalrsrc), .id_alucontrol(id_alucontrol), .id_funct3(id_funct3),
        .id_lui(id_isLUI), .id_auipc(id_isAUIPC),
        // EX → EX/MEM
        .ex_aluresult(ex_alu_result), .ex_writedata(ex_writedata),
        .ex_rd_addr(ex_rd_addr),
        .ex_regwrite(ex_regwrite), .ex_memtoreg(ex_memtoreg), .ex_memwrite(ex_memwrite),
        // MEM → MEM/WB
        .mem_readdata(mem_readdata), .mem_aluresult(mem_aluresult),
        .mem_rd_addr(mem_rd_addr), .mem_regwrite(mem_regwrite), .mem_memtoreg(mem_memtoreg),
        // IF/ID → ID
        .id_o_pc(id_pc), .id_o_pcplus4(id_pcplus4), .id_o_inst(id_inst),
        // ID/EX → EX
        .ex_o_pc(ex_pc), .ex_o_pcplus4(ex_pcplus4), .ex_o_rs1_val(ex_rs1_val),
        .ex_o_rs2_val(ex_rs2_val), .ex_o_imm(ex_imm),
        .ex_o_rs1_addr(ex_rs1_addr), .ex_o_rs2_addr(ex_rs2_addr), .ex_o_rd_addr(ex_rd_addr),
        .ex_o_regwrite(ex_regwrite), .ex_o_alusrc(ex_alusrc), .ex_o_memtoreg(ex_memtoreg),
        .ex_o_memwrite(ex_memwrite), .ex_o_branch(ex_branch), .ex_o_jump(ex_jump_wire),
        .ex_o_jalrsrc(ex_jalrsrc_wire), .ex_o_alucontrol(ex_alucontrol), .ex_o_funct3(ex_funct3),
        .ex_o_lui(ex_lui), .ex_o_auipc(ex_auipc),
        // EX/MEM → MEM
        .mem_o_aluresult(mem_aluresult), .mem_o_writedata(mem_writedata),
        .mem_o_rd_addr(mem_rd_addr),
        .mem_o_regwrite(mem_regwrite), .mem_o_memtoreg(mem_memtoreg),
        .mem_o_memwrite(mem_memwrite),
        // MEM/WB → WB
        .wb_o_readdata(wb_readdata), .wb_o_aluresult(wb_aluresult),
        .wb_o_rd_addr(wb_rd_addr), .wb_o_regwrite(wb_regwrite), .wb_o_memtoreg(wb_memtoreg)
    );

    // ========================================================================
    // Hazard Unit — 转发 + Load-Use
    // ========================================================================

    HazardUnit uHazard (
        .id_rs1_addr(id_rs1_addr), .id_rs2_addr(id_rs2_addr),
        .idex_rs1_addr(ex_rs1_addr), .idex_rs2_addr(ex_rs2_addr),
        .idex_rd_addr(ex_rd_addr), .idex_memread(ex_memtoreg),
        .exmem_rd_addr(mem_rd_addr), .exmem_regwrite(mem_regwrite),
        .memwb_rd_addr(wb_rd_addr), .memwb_regwrite(wb_regwrite),
        .ctrl_flush(ctrl_flush),
        .forward_a(forward_a), .forward_b(forward_b),
        .stall(stall), .flush_ifid(flush_ifid), .flush_idex(flush_idex)
    );

    // ========================================================================
    // EX — ALU + 分支/跳转
    // ========================================================================
    // ALU A: 转发MUX (来自EX/MEM或MEM/WB) + LUI/AUIPC 选择
    wire [31:0] ex_alu_a_fwd;
    assign ex_alu_a_fwd = (forward_a == 2'b01) ? mem_aluresult :
                          (forward_a == 2'b10) ? wb_wd3 : ex_rs1_val;
    // LUI → ALU_A=0, AUIPC → ALU_A=PC (覆盖转发, 因inst[19:15]在U-type不是rs1)
    wire [31:0] ex_alu_a = ex_lui ? 32'd0 :
                           ex_auipc ? ex_pc : ex_alu_a_fwd;

    // ALU B: 转发MUX + ALUSrc选择
    wire [31:0] ex_alu_b_fwd;
    assign ex_alu_b_fwd = (forward_b == 2'b01) ? mem_aluresult :
                          (forward_b == 2'b10) ? wb_wd3 : ex_rs2_val;
    wire [31:0] ex_alu_b = ex_alusrc ? ex_imm : ex_alu_b_fwd;

    ALU uALU (.A(ex_alu_a), .B(ex_alu_b), .ALUControl(ex_alucontrol),
              .ALUResult(ex_alu_raw), .Zero());

    // JAL/JALR 的写回值是 PC+4 (返回地址), 而非 ALU 算出的跳转目标
    wire [31:0] ex_alu_result = (ex_jump_wire | ex_jalrsrc_wire) ? ex_pcplus4 : ex_alu_raw;

    // 分支/跳转目标
    assign ex_branch_target = ex_pc + ex_imm;
    assign ex_jump_target   = ex_pc + ex_imm;
    // JALR 跳转目标 = rs1 + imm (JALR不是LUI/AUIPC, 直接用转发后的rs1)
    wire [31:0] ex_jalr_sum = ex_alu_a_fwd + ex_imm;
    assign ex_jalr_target   = {ex_jalr_sum[31:1], 1'b0};

    // 分支条件
    assign ex_branch_taken = ex_branch && (
        (ex_funct3 == 3'b000) ? (ex_alu_a_fwd == ex_alu_b_fwd) :
        (ex_funct3 == 3'b001) ? (ex_alu_a_fwd != ex_alu_b_fwd) :
        (ex_funct3 == 3'b100) ? ($signed(ex_alu_a_fwd) < $signed(ex_alu_b_fwd)) :
        (ex_funct3 == 3'b101) ? ($signed(ex_alu_a_fwd) >= $signed(ex_alu_b_fwd)) :
        (ex_funct3 == 3'b110) ? (ex_alu_a_fwd < ex_alu_b_fwd) :
        (ex_funct3 == 3'b111) ? (ex_alu_a_fwd >= ex_alu_b_fwd) :
        1'b0);

    assign ex_jump      = ex_jump_wire;
    assign ex_jalrsrc   = ex_jalrsrc_wire;
    assign ctrl_flush   = ex_branch_taken | ex_jump_wire | ex_jalrsrc_wire;

    // 写数据 (rs2 forwarded, for stores)
    assign ex_writedata = ex_alu_b_fwd;

    // ========================================================================
    // MEM — 数据内存
    // ========================================================================
    DataMemory uDataMemory (
        .clk(clk), .rst_n(rst_n), .clk_vga(clk_vga),
        .MemWrite(mem_memwrite), .Addr(mem_aluresult),
        .WriteData(mem_writedata), .ReadData(mem_readdata),
        .SwitchIn(SwitchIn), .ButtonIn(ButtonIn),
        .LEDOut(LEDOut), .seg_cs(seg_cs),
        .seg_data_0(seg_data_0), .seg_data_1(seg_data_1),
        .dmem_dbg_en(dmem_dbg_en), .dmem_wr_en(dmem_wr_en),
        .dmem_dbg_addr(dmem_dbg_addr), .dmem_wr_data(dmem_wr_data),
        .dmem_rd_data(dmem_rd_data),
        .vga_fb_addr(vga_fb_addr), .vga_fb_data(vga_fb_data)
    );

    // ========================================================================
    // WB — 写回
    // ========================================================================
    assign wb_wd3 = wb_memtoreg ? wb_readdata : wb_aluresult;

endmodule

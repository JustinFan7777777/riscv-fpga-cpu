// =============================================================================
// Module      : HazardUnit.v
// Description : 流水线冒险检测 + 数据转发 + Load-Use 暂停
// =============================================================================
// 数据冒险 (RAW):
//   - 从 EX/MEM 转发到 EX 阶段 ALU 输入 (优先级最高, 最新数据)
//   - 从 MEM/WB 转发到 EX 阶段 ALU 输入 (次优先)
//
// Load-Use 冒险:
//   - 检测 ID/EX.MemRead && (ID/EX.rd == IF/ID.rs1 || == IF/ID.rs2)
//   - stall=1 冻结 IF/ID 和 PC, flush_idex=1 清零 ID/EX (插入 NOP 气泡)
//
// 控制冒险:
//   - 由 CPUTopPipeline 在 EX 阶段检测 branch_taken/jump/jalrsrc 后 flush IF/ID 和 ID/EX
//   - flush_ifid=1 清零 IF/ID (清除错误取指), flush_idex=1 清零 ID/EX (插入气泡)
// =============================================================================
`timescale 1ns / 1ps

module HazardUnit (
    // ID 阶段 (用于 Load-Use 检测)
    input  [4:0]  id_rs1_addr, id_rs2_addr,

    // ID/EX 阶段 (当前在 EX 执行的指令)
    input  [4:0]  idex_rs1_addr, idex_rs2_addr, idex_rd_addr,
    input         idex_memread,   // 1=当前指令是 Load

    // EX/MEM 阶段 (上一指令在 MEM 阶段)
    input  [4:0]  exmem_rd_addr,
    input         exmem_regwrite,
    input         exmem_memread,   // 1=EX/MEM中的指令是Load

    // MEM/WB 阶段 (上上指令在 WB 阶段)
    input  [4:0]  memwb_rd_addr,
    input         memwb_regwrite,

    // 控制冒险 stall/flush (来自 CPUTopPipeline)
    input         ctrl_flush,     // 分支跳转时的 flush

    // ==== 转发控制 ====
    output [1:0]  forward_a,      // ALU A 口选择: 00=rs1_val, 01=EX/MEM, 10=MEM/WB
    output [1:0]  forward_b,      // ALU B 口选择: 00=rs2_val, 01=EX/MEM, 10=MEM/WB

    // ==== 流水线控制 ====
    output        stall,          // 1=冻结IF/ID + PC (Load-Use)
    output        flush_ifid,     // 1=清零IF/ID (分支/跳转, 清除错误取指)
    output        flush_idex      // 1=清零ID/EX (插入气泡: Load-Use或分支/跳转)
);

    // ========================================================================
    // 转发检测: EX 阶段需要的数据是否在 EX/MEM 或 MEM/WB 中
    // ========================================================================
    // 注意: Load 在 MEM 阶段时 exmem_aluresult 是访存地址而非数据,
    // 正确的加载值要等到 WB 阶段, 因此 !exmem_memread 禁止从 MEM 阶段的 Load 转发。
    // Forward A (ALU input A ← rs1)
    wire fwd_a_exmem = exmem_regwrite && !exmem_memread
                       && (exmem_rd_addr != 5'd0)
                       && (exmem_rd_addr == idex_rs1_addr);
    wire fwd_a_memwb = memwb_regwrite && (memwb_rd_addr != 5'd0)
                       && !(exmem_regwrite && !exmem_memread
                            && (exmem_rd_addr != 5'd0)
                            && (exmem_rd_addr == idex_rs1_addr))
                       && (memwb_rd_addr == idex_rs1_addr);

    assign forward_a = fwd_a_exmem ? 2'b01 :
                       fwd_a_memwb ? 2'b10 :
                       2'b00;

    // Forward B (ALU input B ← rs2)
    wire fwd_b_exmem = exmem_regwrite && !exmem_memread
                       && (exmem_rd_addr != 5'd0)
                       && (exmem_rd_addr == idex_rs2_addr);
    wire fwd_b_memwb = memwb_regwrite && (memwb_rd_addr != 5'd0)
                       && !(exmem_regwrite && !exmem_memread
                            && (exmem_rd_addr != 5'd0)
                            && (exmem_rd_addr == idex_rs2_addr))
                       && (memwb_rd_addr == idex_rs2_addr);

    assign forward_b = fwd_b_exmem ? 2'b01 :
                       fwd_b_memwb ? 2'b10 :
                       2'b00;

    // ========================================================================
    // Load-Use 冒险检测
    // ========================================================================
    // RegFile 的 negedge 写 + 旁路确保 Load 数据在 1 拍 stall 后立即可用
    wire load_use = idex_memread
                    && ((idex_rd_addr == id_rs1_addr) || (idex_rd_addr == id_rs2_addr))
                    && (idex_rd_addr != 5'd0);

    assign stall = load_use;
    assign flush_ifid = ctrl_flush;
    assign flush_idex = load_use | ctrl_flush;

endmodule

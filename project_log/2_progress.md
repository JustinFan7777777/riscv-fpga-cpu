# 基于CPU的SOC项目进度跟踪表

> 截止日期：5月19日实验课交给老师 | 小组编号参考：CS202_2026s_Project_Team_Table

---

## 项目分工

| 姓名 | 学号 | 项目中的任务 | 当前进度 |
|------|------|-------------|---------|
| 范晓乐 | 12412307 | CPU Verilog 代码设计开发、工程搭建、模块集成、代码审查 | 100% |
| 刘一骏 | 12411922 | 汇编代码(batch_test.asm)编写、RARS 模拟验证 | 100% |
| 陈俊希 | 12411025 | Vivado 综合实现、EGO1 上板测试、差分测试(difftest) | 进行中 |

---

## 代码规范

| 项目 | 内容 |
|------|------|
| 结构化设计 | **是** |
| 顶层模块名 | TopDebug |
| CPU 模块名 | CPUTop |
| CPU 内子模块名 | Ifetch, Decoder, ImmGen, RegFile, ALU, DataMemory |
| 命名规范 | 子模块名大写(ALU, CPUTop)，参数化常量用大写(PC_RESET, MEM_WAIT_CYCLES)，端口名采用驼峰规则(RegWrite, MemtoReg, ALUSrc) |
| 有注释 | **是** — 每个 .v 文件头部有完整中文功能说明，关键逻辑有行内注释 |
| 符号化常量 | Ifetch 模块使用 PC_RESET(PC复位地址), HEX_LOAD_OFFSET(hex加载偏移), INIT_FILE(hex文件路径)；DebugController 使用 CMD_PING/CMD_RESET 等命令码常量；Decoder 使用 opcode 硬编码分支 |

---

## CPU 特性

| 项目 | 内容 |
|------|------|
| 架构类型 | **单周期** (Single-cycle) |
| 流水线 | 不涉及 |
| CPU 时钟 | **25 MHz** (系统时钟 100MHz / 4 + BUFG) |
| ISA 类型 | **RISC-V** (RV32I) |
| 存储方案 | **哈佛结构** (指令内存 IMem 64KB + 数据内存 DMem 64KB，物理分离) |

### 指令集合（RV32I 基础整数指令）

**已实现并可验证（覆盖 10 个基础 Case 全部需求）：**

| 类型 | 指令 | 条数 |
|------|------|------|
| R-type | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU | 10 |
| I-type ALU | ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU | 9 |
| Load | LW | 1 |
| Store | SW | 1 |
| B-type | BEQ, BNE, BLT, BGE, BLTU, BGEU | 6 |
| U-type | LUI, AUIPC | 2 |
| Jump | JAL, JALR | 2 |
| **合计** | | **31 条** |

**已译码但未实现（DataMemory 待扩展 byte/halfword 支持，基础 Case 不涉及）：**

LH, LHU, LB, LBU, SH, SB 共 6 条

---

## SOC 特性

| 项目 | 内容 |
|------|------|
| 复位键 | EGO1 按键 P15 (低有效)，同时支持 Debug 软复位 (cpu_reset) |
| IO 方案 | **① UART + Difftest** AND **② MMIO** (两者均支持) |
| 测试基准地址(0x4000)写入方式 | **Verilog 硬编码** (Ifetch.v 中 `PC_RESET = 32'h00004000`) |

### 用例数据在 Data Memory 中的地址

| 数据 | 地址 |
|------|------|
| CaseID | 0x4000 (Base + 0) |
| OperandA | 0x4004 (Base + 4) |
| OperandB | 0x4008 (Base + 8) |
| Result | 0x400C (Base + C) |

### MMIO 方案下的 I/O 组件及地址

| 设备 | 描述 | 位宽 | 地址 | 示例指令 |
|------|------|------|------|---------|
| sw_g0 | EGO1 左下角 8 个黑色拨码开关 (sw_pin[7:0]) | 8 | 0xFFFF0000 | `lw x1, 0xFFFF0000` |
| sw_g1 | EGO1 中下部 8 个白色拨码开关 (dip_pin[7:0]) | 8 | (同上高8位) | (SwitchIn[15:8]) |
| led_g0 | EGO1 16 个 LED (led_pin[15:0]) | 16 | 0xFFFF0008 | `sw x1, 0xFFFF0008` |
| btn_g0 | EGO1 5 个按键 (btn_pin[4:0]) | 5 | 0xFFFF0004 | `lw x1, 0xFFFF0004` |
| seg_cs | 数码管 8 位位选 (共阳极) | 8 | 0xFFFF000C | `sw x1, 0xFFFF000C` |
| seg_data_0 | 数码管段选组0 (左4位) | 8 | 0xFFFF0010 | `sw x1, 0xFFFF0010` |
| seg_data_1 | 数码管段选组1 (右4位) | 8 | 0xFFFF0014 | `sw x1, 0xFFFF0014` |

---

## Bonus 规划 — 目标满分 10 分

**推荐方案：VGA 文本显示 [5分] + 贪吃蛇游戏 [5分] = 10 分**

利用 EGO1 现有 VGA 接口 (vga_hs/vga_vs/vga_data[11:0]) 和按键，无需额外硬件。VGA 80×30 文本模式约需 4.5KB BRAM，贪吃蛇纯 RISC-V 汇编实现。

| 方案 | 组合 | 总分 | 可行性 |
|------|------|------|--------|
| A(推荐) | VGA[5] + 软硬件应用[5] | 10 | ✅ 高 |
| B(备选) | VGA[5] + M扩展[4] + 工具[1] | 10 | ⚠️ 中 |
| C(备选) | VGA[5] + PS/2键盘[计入VGA] + 应用[5] | 10 | ✅ 高 |

> Pipeline[6] 两周内时间窗口不足，不推荐。

---

## 测试方案

### 子模块仿真（未执行）

本项目采用 **Verilog 逐行代码审查 + RARS 模拟器汇编验证 + 直接上板测试** 的开发流程，替代传统子模块仿真。

**替代理由**：
1. 单周期 CPU 以组合逻辑为主，11 个模块的端口和逻辑已通过逐行交叉审查验证
2. RARS 模拟器对 10 个 Case（21 组高风险数据）的汇编逻辑验证全部 PASS
3. 课程要求（requirement 第 7 节）明确：能上板则无需仿真，仿真仅为无法上板时的降级方案（得分×0.3）

### CPU 集成仿真（未执行）

集成仿真通过 RARS 模拟器替代实现：`batch_test.asm` 在 RARS 中覆盖全部 10 个 Case 的指令组合，逐 Case 验证通过（详见 [3_test_results](3_test_results.md)）。

### 上板测试

| 用例编号 | Assembly file 涉及指令 | ASM 就绪 | 测试环境 | 测试结果 |
|---------|----------------------|---------|---------|---------|
| TC0 (AND) | lw + and + sw | Y | IO on EGO1 / Difftest | 待测 |
| TC1 (SLL) | lw + sll + sw | Y | Difftest | 待测 |
| TC2 (SRA) | lw + sra + sw | Y | Difftest | 待测 |
| TC3 (LUI+ADD) | lw + lui + add + sw | Y | Difftest | 待测 |
| TC4 (JAL+AUIPC) | lw + jal + auipc + sub + add + sw | Y | Difftest | 待测 |
| TC5 (JAL+JALR) | lw + jal + jr + add + sw | Y | Difftest | 待测 |
| TC6 (Fibonacci) | lw + addi + add + ble + bgtz + sw | Y | Difftest | 待测 |
| TC7 (Popcount) | lw + srli + andi + add + sw | Y | Difftest | 待测 |
| TC8 (浮点分类) | lw + slli + srli + andi + beq + bne + sw | Y | Difftest | 待测 |
| TC9 (浮点→Q3.4) | lw + srli + slli + andi + addi + sll/srl + sub + beq + sw | Y | Difftest | 待测 |

---

## 项目管理

| 项目 | 内容 |
|------|------|
| 开发进度 | **Verilog 代码 100%**（11 模块全部完成并审查），**汇编代码 100%**（batch_test.asm + batch_test.hex 已完成并反汇编验证通过） |
| 测试进度 | **RARS 模拟验证已完成 (21/21 PASS)**（刘一骏），Windows 上板测试待执行（陈俊希） |
| 文档进度 | **10%** — 提纲和素材已整理（1_report.md），正文待撰写 |
| 项目整体风险点 | ① difftest 差分测试尚未执行，是否 PASS 未知 ② Vivado 2017.4 综合/时序收敛待验证 ③ 第 15 周截止，测试时间窗口紧张 |

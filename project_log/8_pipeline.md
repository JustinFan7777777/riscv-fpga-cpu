# 五级流水线 CPU — Bonus 演示指南

> 架构优化 | 分值: 6 | 状态: 完成
> 新增文件: CPUTopPipeline.v, Ifetch_Pipe.v, PipeRegs.v, HazardUnit.v, RegFile_Pipe.v
> 复用模块: Decoder, ImmGen, ALU, DataMemory

---

## 一、功能介绍

在单周期 CPU 基础上实现 IF→ID→EX→MEM→WB 五级流水线，含完整冒险处理。通过 EGO1 SwitchIn[15] 拨码开关一键切换单周期/流水线模式。

**五级流水线结构:**
```
时钟周期:  T1     T2     T3     T4     T5     T6 ...
IF:      inst1 → inst2 → inst3 → inst4 → inst5 → ...
ID:              inst1 → inst2 → inst3 → inst4 → ...
EX:                      inst1 → inst2 → inst3 → ...
MEM:                              inst1 → inst2 → ...
WB:                                        inst1 → ...
```

**双 CPU 共存架构 (TopDebug.v):**
- 同时实例化 CPUTop (单周期) 和 CPUTopPipeline (流水线)
- SwitchIn[15] MUX 选择活跃 CPU 的输出
- Debug 读信号经 cpu_mode MUX, 写信号同时广播到两个 CPU
- IMem/DMem 始终保持同步, 切换模式无需重新烧录

---

## 二、冒险处理详解 (核心亮点)

### 2.1 数据转发 (Forwarding) — 解决 RAW 冒险

**场景:**
```asm
add x1, x2, x3   # x1 在 EX/MEM 阶段产生
sub x4, x1, x5   # x1 在 EX 阶段就需要
```

**解决方案 (HazardUnit.v):**
- 检测 EX/MEM.rd == ID/EX.rs1 → forward_a = 01 (从 EX/MEM 转发)
- 检测 MEM/WB.rd == ID/EX.rs1 → forward_a = 10 (从 MEM/WB 转发)
- EX/MEM 优先级更高 (数据更新)
- ALU 输入端 MUX: `(forward_a==01) ? exmem_result : (forward_a==10) ? memwb_result : rs1_val`

**代价: 0 周期延迟。** 大部分 RAW 冒险通过转发零延迟解决。

### 2.2 Load-Use Stall — 转发无法解决的冒险

**场景:**
```asm
lw  x1, 0(x2)    # x1 在 MEM 阶段才读出
add x3, x1, x4   # x1 在 EX 阶段就需要 (差 1 拍!)
```

**解决方案:**
- HazardUnit 检测 ID/EX.MemRead && (ID/EX.rd == IF/ID.rs1 或 IF/ID.rs2)
- stall=1: 冻结 IF/ID 寄存器 + PC
- flush_idex=1: 清零 ID/EX 寄存器 → 插入 NOP 气泡

**代价: 1 周期延迟。**

### 2.3 控制冒险 — 分支预测 + Flush

**策略:** 预测不跳转 (Predict Not Taken)

```asm
beq x1, x2, label   # EX 阶段才知道跳不跳
inst2                # 已进入 IF/ID, 可能错误
inst3                # 已进入 IF
```

**分支成立时:**
- EX 阶段检测 branch_taken=1
- flush_ifid=1: 清零 IF/ID 寄存器 → inst2/inst3 作废
- PC 更新为分支目标
- ctrl_flush 延长 1 拍 (补偿 BRAM 读延迟)

**代价: 1 周期 penalty。**

---

## 三、关键设计决策 (指代码讲)

### 3.1 BRAM 寄存器读 (Ifetch_Pipe.v)
- 与单周期 IMem 分布式 RAM 组合读不同, 流水线版使用 BRAM + 寄存器读
- 1 周期延迟由流水线自然吸收 (IR 是流水线第一级)
- 节省 ~14000 LUTs, 确保 VGA+双 CPU 适配 XC7A35T

### 3.2 RegFile negedge 写 + bypass (RegFile_Pipe.v)
- WB 阶段在 negedge clk 写入寄存器, 在下一拍 posedge (ID 读) 之前完成
- bypass 旁路: 如果 ID 读的寄存器正好是 WB 正在写的寄存器, 直接用 WD3
- 消除流水线 RAW 冒险的 NBA (Non-Blocking Assignment) 竞争

### 3.3 复位预热 + flush 延长
- `reset_stall`: 复位后 1 拍冻结 IF/ID, 等待 BRAM 加载首条指令
- `flush_ifid_delay`: ctrl_flush 延长 1 拍, 兜底清除 BRAM 读延迟中已超前的指令

---

## 四、视频演示流程

**1. 模式切换展示:**
- "SwitchIn[15] 拨下 → 单周期模式"
- "拨上 → 流水线模式, 两个 CPU 在 TopDebug.v 中同时运行"
- 切换瞬间 LED/数码管正常切换, 无需重新烧录

**2. 代码走读 (Vivado 中依次打开):**
- CPUTopPipeline.v: 五级流水线顶层结构
- PipeRegs.v: 4 组流水线寄存器
- HazardUnit.v: 转发检测 (forward_a/forward_b 优先级逻辑) + Load-Use 检测

**3. Debug 验证 (串口):**
- HALT → 读寄存器 → STEP → 再读寄存器
- 验证: 单周期和流水线模式下同一程序的寄存器值一致
- "两种模式下 Debug 都能暂停观察, 写信号同时广播保持 IMem/DMem 同步"

---

## 五、Bug 记录

| # | 问题 | 修复 |
|---|------|------|
| 1 | Vivado 不支持表达式 part-select | 拆为中间 wire |
| 2 | 复位后 IMem 第一条指令是 NOP | 加 reset_stall 冻结 IF/ID 1 拍 |
| 3 | BRAM 读延迟导致 flush 后仍有错误指令 | flush 延长 1 拍 (`flush_ifid_delay`) |
| 4 | wire 声明顺序导致 implicit wire | 所有内部信号在模块实例化前显式声明 |

---

## 六、创新点

1. **一键模式切换** — SwitchIn[15] MUX, 双 CPU 共存, 无需重新烧录
2. **转发优先编码** — EX/MEM > MEM/WB, 大部分 RAW 零延迟
3. **Debug 双 CPU 兼容** — 读 MUX + 写广播, 两种模式统一调试
4. **模块复用** — 流水线复用单周期 6 个模块, 仅新增 5 个 (~400 行)
5. **BRAM 替代分布式 RAM** — 节省 ~14000 LUTs, 适配 XC7A35T
6. **RegFile negedge 写 + bypass** — 消除流水线 NBA 竞争

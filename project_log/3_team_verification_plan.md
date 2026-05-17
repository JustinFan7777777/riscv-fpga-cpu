# 三方协同验证计划

> 当前状态：**🟡 汇编 RARS 测试阶段**

---

## 验证阶段总览

```
阶段 A: RARS 模拟验证 ← 🟡 正在进行 (刘一骏)
   → 逐 Case 在 RARS 中跑 33 组测试数据
   → 记录 PASS/FAIL 结果

阶段 B: Vivado 综合 (陈俊希)
   → source create_project.tcl → Generate Bitstream

阶段 C: 传统 I/O 上板 (陈俊希)
   → 开关+LED 验证硬件通路

阶段 D: Debug UART 通信 (陈俊希)
   → Python 串口测试 PING/PONG

阶段 E: Difftest 差分测试 (陈俊希)
   → difftest 跑全部 33 组测试数据

阶段 F: 问题修复循环
   → FAIL → 定位 → 修代码 → 重新综合 → 重新测试
```

---

## 🟡 阶段 A：RARS 模拟验证（当前阶段）

**负责人：刘一骏**

### 操作步骤

1. RARS → Settings → Memory Configuration → 勾选 "Compact, Text at 0, Data at 0x1000" → 重启 RARS
2. 打开 `assembly/batch_test.asm` → Assemble (F3)
3. 逐组测试 33 组数据（详见 [2_assembly_dev_guide.md](2_assembly_dev_guide.md)）

### 每组操作

```
Data Segment 手动写入:
  [0x4000] = CaseID
  [0x4004] = OperandA
  [0x4008] = OperandB
→ Run (F5)
→ 查看 [0x400C] 的值
→ 与期望值比对 → PASS/FAIL
→ Reset (F12)
→ 下一组
```

### 快捷启动

首次用 Case 0 第 1 组数据快速验证流程是否走通，确认后再批量跑 33 组。

### 验收条件

- 全部 33 组 PASS → 通知 Windows 队友进入阶段 B
- 出现 FAIL → 截图寄存器 + DMem，发群里给范晓乐定位

---

## ⬜ 阶段 B：Vivado 综合

**负责人：陈俊希** | **依赖：阶段 A 全部通过**

1. Clone 最新仓库
2. Vivado 2017.4 → Tcl Console → `source create_project.tcl`
3. Run Synthesis → Run Implementation → Generate Bitstream

**验收：Bitstream 生成成功，无 critical warning**

---

## ⬜ 阶段 C：传统 I/O 测试

**负责人：陈俊希** | **依赖：阶段 B**

1. 烧录 bitstream 到 EGO1
2. 拨码开关设置 OperandA (左8位)，拨码开关设置 OperandB (右8位)
3. 按复位键 (P15)
4. 观察 LED 显示 AND 结果

**验收：LED 输出与手动计算一致**

---

## ⬜ 阶段 D：Debug UART 测试

**负责人：陈俊希** | **依赖：阶段 B**

```python
import serial
ser = serial.Serial('COM3', 115200, timeout=0.5)
ser.write(b'\x00')           # CMD_PING
assert ser.read(1)[0] == 0x80  # RESP_PONG
```

**验收：收到 PONG (0x80)**

---

## ⬜ 阶段 E：Difftest 差分测试

**负责人：陈俊希** | **依赖：阶段 D**

在 difftest 工具中载入 33 组测试数据（详见 [2_assembly_dev_guide.md](2_assembly_dev_guide.md) 中的测试清单），点击 Run Batch Test。

**验收：全部 33 组 PASS**

---

## ⬜ 阶段 F：问题修复循环

若任何阶段出现 FAIL：

1. 记录具体错误（实际值 vs 期望值，截图）
2. 范晓乐根据错误定位问题（Verilog 逻辑 or 汇编逻辑）
3. 修复后 git commit + push
4. 陈俊希 git pull，重新综合/测试

---

## 成功标准

✅ 全部 33 组差分测试 PASS → 基础功能 80 分到手 → 进入文档 & 视频阶段

# 项目时间线行动清单

> 当前：🟢 RARS 验证通过 (21/21 PASS)，代码终审完成，进入上板阶段

---

## 第一阶段：上板验证 ⬅ 当前

| 步骤 | 负责人 | 操作 | 预计耗时 |
|------|--------|------|---------|
| 1.1 | 陈俊希 | `git clone` 仓库，确认 11 个 `.v` + `batch_test.hex` + `ego1.xdc` 完整 | 5 分钟 |
| 1.2 | 陈俊希 | Vivado 2017.4 → Tcl Console → `source create_project.tcl` | 2 分钟 |
| 1.3 | 陈俊希 | Run Synthesis → Run Implementation → Generate Bitstream | 30 分钟 |
| 1.4 | 陈俊希 | 开发板连接：Micro USB 烧录 `TopDebug.bit` | 5 分钟 |
| 1.5 | 陈俊希 | 传统 I/O 测试（快速硬件链路检查，见下方） | 10 分钟 |
| 1.6 | 陈俊希 | UART 连通测试：Python 发 `b'\x00'`，收 `0x80` (PONG) | 5 分钟 |
| 1.7 | 陈俊希 | Difftest 差分测试：载入 33 组数据 → Run Batch Test | 15 分钟 |

**验收**：全部 33 组 difftest PASS → 进入第二阶段。FAIL → 范晓乐定位修 bug → 回到步骤 1.3。

### 快速 I/O 测试（步骤 1.5 备用）

```asm
# 临时替代 batch_test.hex，仅验证开关→LED 硬件链路
lui  x31, 0xFFFF0
lw   x1, 0(x31)
andi x1, x1, 0xFF
sw   x1, 8(x31)
j    .
```

### 关键确认（范晓乐）

- [x] batch_test.asm 第 50 行 = `lui s0, 0x4`（硬件/difftest 模式）
- [x] batch_test.hex = 130 行，首行 `00004437`（即 `lui s0, 0x4`）
- [x] ego1.xdc 与 TopDebug.v 端口名一致
- [x] Ifetch.v PC_RESET = 0x4000，hex 偏移 = 4096

---

## 第二阶段：问题修复循环（按需）

| 步骤 | 负责人 | 操作 |
|------|--------|------|
| 2.1 | 陈俊希 | 记录 FAIL 详情：Case 编号、实际值 vs 期望值、截图 |
| 2.2 | 范晓乐 | 根据错误定位根因（Verilog 逻辑 / 汇编逻辑 / 时序） |
| 2.3 | 范晓乐 | 修复代码 → `git commit && git push` |
| 2.4 | 陈俊希 | `git pull` → 重新综合 → 重新测试 |

---

## 第三阶段：文档 & 视频

| 步骤 | 负责人 | 操作 |
|------|--------|------|
| 3.1 | 范晓乐 | 撰写项目文档 PDF（提纲见 [1_report](1_report.md)） |
| 3.2 | 刘一骏 | 提供汇编设计说明文字（已写入 1_report） |
| 3.3 | 全员 | 录制视频：全员出镜 + 至少 2 个复杂 Case 上板演示 |
| 3.4 | 陈俊希 | 录制 difftest 批量测试过程 + 传统 I/O 演示片段 |
| 3.5 | 范晓乐 | 视频剪辑合成，≤500MB MP4 |

---

## 第四阶段：提交

| 步骤 | 负责人 | 操作 |
|------|--------|------|
| 4.1 | 范晓乐 | `git log > gitlog.txt`，文件头加成员名→GitHub ID 映射 |
| 4.2 | 范晓乐 | 整理压缩包 `c_rv_FanXiaole_ChenJunxi_LiuYijun.zip` |
| 4.3 | 范晓乐 | 上传 BB：zip + PDF + MP4 三个文件分别上传 |
| 4.4 | 范晓乐 | 共享文档登记提交者姓名 |

### 提交目录结构

```
c_rv_FanXiaole_ChenJunxi_LiuYijun/
├── cpu_project/
│   ├── cpu_project.xpr
│   ├── cpu_project.srcs/*
│   └── cpu_project.runs/impl_1/
│       ├── TopDebug.bit
│       ├── TopDebug_opt.dcp
│       ├── TopDebug_placed.dcp
│       └── TopDebug_routed.dcp
├── assembly/
│   ├── batch_test.asm
│   ├── batch_test.hex
│   └── test_results.txt
├── other/
└── gitlog.txt
```

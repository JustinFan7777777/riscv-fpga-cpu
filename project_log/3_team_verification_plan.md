# 三方协同验证计划

## 验证阶段总览

```
阶段 A: 汇编验证 (汇编队友)
  → 用 RISC-V 模拟器逐 Case 验证

阶段 B: Vivado 综合 (Windows 队友)
  → source create_project.tcl
  → 不含 hex 的首次综合 (验证硬件正确)
  → 含 hex 的最终综合

阶段 C: 传统 I/O 上板 (Windows 队友)
  → 开关+LED 验证最简 Case
  → 确认整条硬件通路

阶段 D: Debug UART 通信 (Windows 队友)
  → Python 串口测试 PING/PONG
  → CLI 命令验证 reg/pc/step

阶段 E: 差分测试 (Windows 队友)
  → difftest 跑全部 33 组测试数据

阶段 F: 问题修复 (循环)
  → FAIL → 定位问题 → 修代码 → 重新综合 → 重新测试
```

## 阶段 A：汇编验证

- **负责人**：汇编队友
- **依赖**：无
- **文件**：[2_assembly_dev_guide](2_assembly_dev_guide.md)

**验收条件**：全部 33 组测试数据在 RISC-V 模拟器中 PASS

## 阶段 B：Vivado 综合

- **负责人**：Windows 队友
- **依赖**：阶段 A (需要 batch_test.hex)
- **文件**：[1_windows_vivado_guide](1_windows_vivado_guide.md) 步骤 1-4

**验收条件**：Bitstream 生成成功，无 critical warning

## 阶段 C：传统 I/O 测试

- **负责人**：Windows 队友
- **依赖**：阶段 B
- **测试内容**：
  1. 烧录 bitstream
  2. 拨动开关设置输入值
  3. 按复位键
  4. 观察 LED 输出

**验收条件**：至少一个 Case 的 LED 输出与预期一致

## 阶段 D：Debug UART 测试

- **负责人**：Windows 队友
- **依赖**：阶段 B
- **测试内容**：
  1. 连接 USB 转串口线
  2. Python 脚本发 PING (0x00)
  3. 收到 PONG (0x80)
  4. 依次测试 HALT, READ_REG, READ_PC, STEP

**验收条件**：PING/PONG 成功 + 至少能读出一个寄存器值

## 阶段 E：差分测试

- **负责人**：Windows 队友
- **依赖**：阶段 D
- **完整测试数据** (33 组)：

```
0,[0x00000f0f,0x00001234],0x0204
0,[0xffffffff,0x00001234],0x1234
1,[0x12481248,0x4],0x24812480
1,[0x1,0x2d],0x2000
2,[0x71240000,0x18],0x71
2,[0x81231234,0x24],0xf8123123
3,[0x10000000,0],0x22345000
3,[0x1,0],0x12345001
4,[0x0,0],0x12345000
4,[0x10,0],0x12345010
5,[0x5,0x6],0xB
5,[0x1,0x2],0x3
6,[0x01,0],0x1
6,[0x02,0],0x1
6,[0x03,0],0x2
6,[0x04,0],0x3
7,[0xc1,0],0x3
7,[0xF8,0],0x5
8,[0x8000,0],0x0
8,[0x0000,0],0x0
8,[0x7c00,0],0x1
8,[0xFc00,0],0x1
8,[0xFc01,0],0x2
8,[0x2026,0],0x3
8,[0xc202,0],0x3
8,[0x0003,0],0x4
8,[0x80e1,0],0x4
9,[0x3c00,0],0x10
9,[0x3e00,0],0x18
9,[0x4200,0],0x30
9,[0xc400,0],0xc0
9,[0x4240,0],0x32
9,[0xBF00,0],0xE4
```

**验收条件**：全部 33 组数据 PASS

## 阶段 F：问题修复循环

如果任何阶段出现 FAIL：

1. **Windows 队友**：记录具体错误 (实际值 vs 期望值，截图)
2. **代码队友 (Mac)**：根据错误定位问题 (Verilog 逻辑 还是 汇编逻辑)
3. **汇编队友**：如有汇编错误，修正 batch_test.asm
4. **代码队友**：如有 Verilog 错误，修正 .v 文件
5. Git commit + push
6. **Windows 队友**：git pull，重新综合/测试

## 成功标准

全部 10 个 Case (33 组差分测试数据) PASS，即可进入文档和视频阶段。

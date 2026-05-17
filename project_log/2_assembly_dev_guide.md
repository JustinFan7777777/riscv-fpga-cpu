# 汇编队友操作指南：汇编编译 + 模拟验证

## 前置准备

- [ ] 安装 RISC-V GNU Toolchain (课程提供)
- [ ] 或安装 RARS (RISC-V Assembler and Runtime Simulator, Java 版)
- [ ] Clone 小组仓库到本地

## 步骤 1：确认汇编文件

打开 `assembly/batch_test.asm`，这个文件包含：
- **主调度器**：循环从 DMem 0x4000 读取 CaseID，跳转到对应 case 处理函数
- **Case 0-5**：完整实现 (简单指令)
- **Case 6-9**：完整实现 (斐波那契、popcount、浮点分类、浮点量化)

## 步骤 2：编译 .asm → .hex

### 方法 A：GNU Toolchain (推荐)

```bash
# 汇编
riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 \
  assembly/batch_test.asm -o assembly/batch_test.o

# 链接 (代码从地址 0 开始)
riscv64-unknown-elf-ld -Ttext 0x00000000 \
  assembly/batch_test.o -o assembly/batch_test.elf

# 生成 hex (Verilog 格式)
riscv64-unknown-elf-objcopy -O verilog \
  assembly/batch_test.elf assembly/batch_test.hex
```

### 方法 B：RARS

```bash
java -jar rars.jar a dump .text HexText assembly/batch_test.hex assembly/batch_test.asm
```

## 步骤 3：验证 hex 文件

检查 `assembly/batch_test.hex`：
- 每行应该是 8 位十六进制数 (32-bit)
- 第一行对应 PC=0x00000000 的指令
- 第二行对应 PC=0x00000004 的指令
- 依此类推

```bash
# 检查行数
wc -l assembly/batch_test.hex

# 查看前 10 行
head -10 assembly/batch_test.hex
```

## 步骤 4：模拟器验证 (关键步骤！)

在把 hex 交给 Windows 队友之前，先在本机用模拟器逐 case 验证。

### 方法 A：使用 Spike (RISC-V ISA Simulator)

```bash
# 安装 spike (如未安装)
# sudo apt-get install spike  # Ubuntu
# 或从源码编译: https://github.com/riscv-software-src/riscv-isa-sim

# 运行 batch_test.elf
spike --isa=rv32i batch_test.elf
```

### 方法 B：使用 RARS 模拟器

1. 打开 RARS
2. File → Open → 选择 `batch_test.asm`
3. Tools → Memory Map (查看内存布局)
4. 在 Data Segment 窗口设置 DMem 测试数据：
   - 地址 0x4000: CaseID
   - 地址 0x4004: OperandA
   - 地址 0x4008: OperandB
5. Run → Go (或单步 Step)
6. 执行完成后检查 0x400C 处的 Result
7. 与 TestCase_Specification.xlsx 中的期望值比对

### 逐 Case 验证清单

| Case | 测试数据 (A,B) | 期望结果 | 模拟器结果 | PASS/FAIL |
|------|---------------|---------|-----------|-----------|
| 0 | (0x0f0f, 0x1234) | 0x0204 | | |
| 0 | (0xffffffff, 0x1234) | 0x1234 | | |
| 1 | (0x12481248, 0x4) | 0x24812480 | | |
| 1 | (0x1, 0x2d) | 0x2000 | | |
| 2 | (0x71240000, 0x18) | 0x71 | | |
| 2 | (0x81231234, 0x24) | 0xf8123123 | | |
| 3 | (0x10000000, 0) | 0x22345000 | | |
| 3 | (0x1, 0) | 0x12345001 | | |
| 4 | (0x0, 0) | 0x12345000 | | |
| 4 | (0x10, 0) | 0x12345010 | | |
| 5 | (0x5, 0x6) | 0xB | | |
| 5 | (0x1, 0x2) | 0x3 | | |
| 6 | (0x1, 0) | 0x1 | | |
| 6 | (0x2, 0) | 0x1 | | |
| 6 | (0x3, 0) | 0x2 | | |
| 6 | (0x4, 0) | 0x3 | | |
| 7 | (0xC1, 0) | 0x3 | | |
| 7 | (0xF8, 0) | 0x5 | | |
| 8 | (0x8000, 0) | 0x0 | | |
| 8 | (0x0000, 0) | 0x0 | | |
| 8 | (0x7C00, 0) | 0x1 | | |
| 8 | (0xFC00, 0) | 0x1 | | |
| 8 | (0xFC01, 0) | 0x2 | | |
| 8 | (0x2026, 0) | 0x3 | | |
| 8 | (0xC202, 0) | 0x3 | | |
| 8 | (0x0003, 0) | 0x4 | | |
| 8 | (0x80E1, 0) | 0x4 | | |
| 9 | (0x3C00, 0) | 0x10 | | |
| 9 | (0x3E00, 0) | 0x18 | | |
| 9 | (0x4200, 0) | 0x30 | | |
| 9 | (0xC400, 0) | 0xC0 | | |
| 9 | (0x4240, 0) | 0x32 | | |
| 9 | (0xBF00, 0) | 0xE4 | | |

## 步骤 5：提交 hex

全部 case 通过模拟器验证后：
1. 将 `batch_test.hex` 提交到 GitHub 仓库的 `assembly/` 目录
2. 通知 Windows 队友重新 Generate Bitstream

## 常见问题

| 问题 | 解决 |
|------|------|
| 汇编器报 "unknown pseudo-instruction" | 一些伪指令 (如 `li`, `ble`, `bgtz`) 可能需要换成基础指令。如果 toolchain 不支持，反馈给代码队友。 |
| hex 文件为空或格式不对 | 检查 objcopy 参数。Verilog hex 格式每行一个 32-bit 十六进制数。 |
| 模拟结果与期望不符 | 单步跟踪，检查每条指令执行后的寄存器值。 |

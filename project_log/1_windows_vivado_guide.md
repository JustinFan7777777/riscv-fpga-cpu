# Windows 队友操作指南：Vivado 工程 + 上板验证

## 前置准备

- [ ] 安装 Vivado 2017.4 (必须是这个版本)
- [ ] 安装 EGO1 开发板的 USB 串口驱动 (CH340/CP2102)
- [ ] 确认有一根 USB 转串口线 (Micro USB)
- [ ] GitHub Desktop 或 Git Bash，Clone 小组仓库到本地

## 步骤 1：Clone 仓库并确认文件完整

```bash
git clone <你们组的GitHub Classroom仓库URL>
cd <仓库目录>
```

确认以下文件存在：
```
cpu_project/cpu_project.srcs/sources_1/new/  ← 11个 .v 文件
cpu_project/cpu_project.srcs/constrs_1/ego1.xdc
assembly/batch_test.hex                      ← 需汇编队友先提供
create_project.tcl
```

## 步骤 2：Vivado 创建工程

1. 打开 Vivado 2017.4
2. 在底部 **Tcl Console** 中输入：
   ```
   cd <仓库路径>
   source create_project.tcl
   ```
3. 脚本自动完成：
   - 创建 cpu_project 工程 (FPGA: xc7a35tcsg324-1)
   - 添加全部 11 个 Verilog 源文件
   - 加载 ego1.xdc 引脚约束
   - 设置顶层为 TopDebug
4. 左侧 Flow Navigator 应该显示完整工程

> 如果 Tcl 报错 "project already exists"，先删掉 cpu_project 文件夹再执行

## 步骤 3：确认 batch_test.hex

- 检查 `assembly/batch_test.hex` 是否存在
- 如果不存在：等汇编队友编译好放进来，然后跳到步骤 2 重新 `source create_project.tcl`
- hex 文件格式：每行 8 位十六进制 (对应一条 32-bit 指令)

## 步骤 4：综合 → 实现 → 生成 Bitstream

按顺序点击 Vivado 左侧 Flow Navigator：
1. **Run Synthesis** — 综合 (约 5-10 分钟)
2. **Run Implementation** — 实现 (约 5-15 分钟)
3. **Generate Bitstream** — 生成比特流 (约 3-5 分钟)

### 常见问题

| 错误 | 可能原因 | 解决 |
|------|---------|------|
| "TopDebug not found" | 顶层模块名不对 | 确认 TopDebug.v 中 module 名是 `TopDebug` |
| Port mismatch | .v 文件和 .xdc 端口名不一致 | 反馈给代码队友修 |
| BRAM overflow | 内存太大超出 FPGA 容量 | 减小 Ifetch/DataMemory 中 mem 数组大小 |
| Unconstrained pins | XDC 缺少某些引脚约束 | 检查是否用了未约束的外设端口 |
| Timing violation | 25MHz 时钟约束违例 | 先不管，看能否正常工作；如不行则增加 MEM_WAIT_CYCLES |

## 步骤 5：烧录到 EGO1 开发板

1. 用 Micro USB 线连接 EGO1 和电脑
2. Vivado 中点击 **Open Hardware Manager** → **Open Target** → **Auto Connect**
3. 如果找不到设备：检查 USB 驱动是否安装、线是否接对
4. **Program Device** → 选择 `TopDebug.bit` → **Program**

## 步骤 6：传统 I/O 测试（先确认 CPU 基本功能）

验证 Case 0 (AND 运算)：

1. 确保 batch_test.hex 中 Case 0 代码已加载
2. 在开发板上：
   - 用 **左8个拨码开关 (sw_pin)** 输入 OperandA 的低 8 位
   - 用 **右8个拨码开关 (dip_pin)** 输入 OperandB 的低 8 位
   - 按 **复位键 (P15)** 让 CPU 从 PC=0 开始
   - 观察 **LED (led_pin[15:0])** 的 [7:0]：应该显示 A & B 的结果
3. 如果 LED 显示预期结果 → CPU 硬件通路正常 ✅

> 注：传统 I/O 测试需要 CPU 主动读取开关值并写入 LED。确认 case0 程序在执行 AND 运算前先从 MMIO 地址 0xFFFF0000 和 0xFFFF0004 读取开关值。

## 步骤 7：Debug UART 测试

1. 用 USB 转串口线连接 EGO1 的 UART 口 (N5=RX, T4=TX) 到电脑
2. 确认串口号：
   - Windows：设备管理器 → 端口 (COM 和 LPT) → 找到 USB Serial Port (COMx)
3. 打开 Python，运行连通性测试：
   ```python
   import serial
   ser = serial.Serial('COM3', 115200, timeout=0.5)
   ser.write(b'\x00')              # CMD_PING
   resp = ser.read(1)
   print(f"Response: 0x{resp[0]:02X}")  # 应该输出 0x80 (PONG)
   ```
4. 如果收到 PONG → UART 通信正常 ✅
5. 进一步测试 debug 命令（见 DebugController.v 头部批注的 Python 示例）

## 步骤 8：差分测试 (Difftest)

1. 打开课程提供的 difftest 工具
2. 选择正确的串口号，波特率 115200
3. 在 "Test Cases" 区域输入测试数据（从 TestCase_Specification.xlsx 中文页面 D3-D12 列复制）
4. 点击 "Run Batch Test"
5. 检查每个 Case 的测试结果是否 PASS

### 差分测试数据格式

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

## 步骤 9：记录测试结果

在 [4_report_notes](4_report_notes.md) 中记录：
- 哪些 Case PASS / FAIL
- 如果 FAIL：具体的错误现象（实际值 vs 期望值）
- 截图保存到 `project_log/screenshots/` 目录

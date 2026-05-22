# VGA 文本模式显示控制器 — 实现与上板指南

## 这是什么？

一个纯 Verilog 实现的 VGA 文本模式显示控制器，运行在 EGO1 开发板上，CPU 通过 MMIO 直接写入显存即可在显示器上输出 80 列 × 30 行的彩色字符画面。

**显示规格：** 640×480@60Hz，80 列 × 30 行，每字符 8×16 像素，支持 16 种前景色 × 16 种背景色。

## 文件位置

```
cpu_project/cpu_project.srcs/sources_1/new/VGA.v   # VGA 控制器 Verilog 源码
other/vga/font_rom.hex                              # 128 字符 × 8×16 字模位图
other/vga/gen_font.py                               # 字模 ROM 生成脚本 (可复现)
```

## 架构总览

```
                         TopDebug.v
   ┌──────────────────────────────────────────────────────────┐
   │                                                          │
   │  100MHz ── clk_div[2] ── BUFG ── 12.5MHz ──▶ CPUTop     │
   │          ── clk_div[1] ── BUFG ── 25MHz   ──▶ VGA.v     │
   │                                                          │
   │  CPUTop (CPU单周期核)                                     │
   │    │                                                     │
   │    └── DataMemory.v                                      │
   │          │                                               │
   │          ├── Port A (CPU侧, 12.5MHz)                     │
   │          │   └── VGA帧缓冲 BRAM 2400×16-bit              │
   │          │       CPU通过 sw 0xFFFF_01xx 写入             │
   │          │                                               │
   │          └── Port B (VGA侧, 25MHz)                       │
   │              └── VGA.v 逐像素扫描读出                    │
   │                    │                                     │
   │                    ├── 字模ROM (2048×8-bit, 分布式RAM)   │
   │                    │   查表: {ascii[6:0], row[3:0]}      │
   │                    │                                     │
   │                    ├── 像素着色: bit=1→前景色, bit=0→背景色│
   │                    │                                     │
   │                    └── vga_hs, vga_vs, vga_r[3:0],       │
   │                        vga_g[3:0], vga_b[3:0]            │
   └──────────────────────────────────────────────────────────┘
```

## MMIO 地址规划

| 地址范围 | 内容 | 大小 |
|---------|------|------|
| `0xFFFF_0100` – `0xFFFF_13BF` | VGA 帧缓冲 (2400 字 × 2 字节) | 4800 字节 |

**每字 (16-bit) 格式：**

```
bit[15:12]  背景色 (I+R+G+B)
bit[11:8]   前景色 (I+R+G+B)
bit[7:0]    ASCII 字符码 (低 7 位有效, 支持 0x00–0x7F)
```

**地址计算：** `VGA地址 = 0xFFFF_0100 + 2 × (行号 × 80 + 列号)`

汇编示例 — 在屏幕左上角画一个亮绿色的 `A`:
```asm
lui  t0, 0xFFFF0         # t0 = 0xFFFF0000
addi t0, t0, 0x100       # t0 = 0xFFFF0100 (VGA基址)
addi t1, x0, 0x0A41      # 亮绿色 'A' = 0x0A00 | 0x41
sw   t1, 0(t0)           # 写入帧缓冲 (低16-bit生效)
```

**颜色编码 (I+R+G+B, 每通道 1-bit)：**

| 值 | I | R | G | B | 颜色 |
|----|---|---|---|---|------|
| 0x0 | 0 | 0 | 0 | 0 | 黑 |
| 0x2 | 0 | 0 | 1 | 0 | 暗绿 |
| 0x4 | 0 | 1 | 0 | 0 | 暗红 |
| 0x8 | 1 | 0 | 0 | 0 | 暗灰 |
| 0xA | 1 | 0 | 1 | 0 | 亮绿 |
| 0xC | 1 | 1 | 0 | 0 | 亮红 |
| 0xE | 1 | 1 | 1 | 0 | 黄 |
| 0xF | 1 | 1 | 1 | 1 | 白 |

VGA 输出 4-bit 每通道，颜色值扩展为 `{通道色, 通道色, 通道色, 亮度}`。

## VGA 时序参数

| 参数 | 水平 (像素) | 垂直 (行) |
|------|-----------|----------|
| 有效区域 | 640 | 480 |
| 前沿 (Front Porch) | 16 | 10 |
| 同步脉冲 (Sync) | 96 | 2 |
| 后沿 (Back Porch) | 48 | 33 |
| 总计 | 800 | 525 |

像素时钟 25MHz (100MHz 主时钟的 clk_div[1] + BUFG)，标准 VGA 640×480@60Hz 需要 25.175MHz，误差 0.7%，通用显示器均可兼容。

## 像素流水线 (2 级)

```
h_cnt → fb_addr (预取, 提前 2 像素) → BRAM读(1拍)
  → char_data锁存 → 字模ROM(组合读) → font_row
  → pixel = font_row[7 - h_d1[2:0]]
  → 着色 → VGA_RGB输出
```

- 每字符开始前 2 像素预取下一个字符的帧缓冲地址
- 每行开始前在水平消隐期预取该行首字符
- 字模 ROM 使用分布式 RAM (LUT)，支持组合逻辑读出，零额外延迟

## EGO1 引脚连接

| 信号 | EGO1 引脚 | 说明 |
|------|----------|------|
| vga_hs | D7 | 水平同步 |
| vga_vs | C4 | 垂直同步 |
| vga_r[0] | F5 | 红 bit0 |
| vga_r[1] | C6 | 红 bit1 |
| vga_r[2] | C5 | 红 bit2 |
| vga_r[3] | B7 | 红 bit3 |
| vga_g[0] | B6 | 绿 bit0 |
| vga_g[1] | A6 | 绿 bit1 |
| vga_g[2] | A5 | 绿 bit2 |
| vga_g[3] | D8 | 绿 bit3 |
| vga_b[0] | C7 | 蓝 bit0 |
| vga_b[1] | E6 | 蓝 bit1 |
| vga_b[2] | E5 | 蓝 bit2 |
| vga_b[3] | E7 | 蓝 bit3 |

## 上板测试流程

### 1. Vivado 工程准备

```bash
# 确保以下文件在工程中
cpu_project/cpu_project.srcs/sources_1/new/VGA.v   # 添加为设计源文件
cpu_project/cpu_project.srcs/constrs_1/ego1.xdc    # XDC约束 (含VGA引脚)
other/vga/font_rom.hex                              # 字模数据 (与VGA.v同目录)
```

### 2. 编译与烧录

```
Vivado → Generate Bitstream → Hardware Manager → Program Device
→ 烧录 TopDebug.bit
```

### 3. 快速测试：通过 Debug Controller 写入测试画面

连接 UART 串口 (115200/8N1)，使用 Python 脚本写入帧缓冲：

```python
import serial, struct
ser = serial.Serial('/dev/ttyUSB0', 115200, timeout=0.5)

# 暂停 CPU
ser.write(b'\x03')          # CMD_HALT
assert ser.read(1)[0] == 0x81

# 在第 5 行第 20 列写一个亮绿色 'H'
# 地址 = 0xFFFF_0100 + 2*(5*80+20) = 0xFFFF_0100 + 840 = 0xFFFF_0348
addr = 0xFFFF0348
data = 0x00000A48           # 0x0A00(亮绿) + 0x48('H') → 只取低16位 = 0x0A48
ser.write(b'\x41' + struct.pack('>I', addr) + struct.pack('>I', data))
assert ser.read(1)[0] == 0x81

# 恢复运行
ser.write(b'\x02')          # CMD_RUN
```

### 4. 预期结果

- VGA 显示器显示 80×30 字符网格
- 未经初始化的帧缓冲可能显示随机字符 (BRAM 上电值不确定)
- 写入测试数据后应在指定位置显示对应颜色的字符
- 无雪花、无撕裂、无抖动

### 5. 常见问题

| 问题 | 可能原因 | 解决 |
|------|---------|------|
| 显示器黑屏 / "No Signal" | VGA 时序不对，或引脚约束缺失 | 检查 ego1.xdc 中 14 个 VGA 引脚是否正确约束 |
| 显示花屏 / 乱码 | 帧缓冲未初始化 (BRAM 上电随机值) | 先用空格 (0x0020) 填满帧缓冲 |
| 字符位置偏移 | 像素流水线预取逻辑错误 | 检查 VGA.v 中 h_cnt==798 和 h_cnt[2:0]==6 的 fb_addr 更新 |
| 颜色不对 | 颜色通道位序错误 | 检查 vga_r/g/b 引脚映射是否与 vga_data_pin 对齐 |
| Vivado 报 font_rom.hex 找不到 | $readmemh 相对路径错误 | 确认 FONT_FILE 参数指向 `../../../../other/vga/font_rom.hex` |

---

## 软硬件协同工作原理（视频讲解用）

### 一条指令到一个像素：完整数据旅程

```
sw t0, 0xFFFF0100(x0)    # t0=0x0A48(亮绿'H'), 写入VGA帧缓冲
```

**第1步 — CPU执行sw（软件→硬件边界）**

```
PC→Ifetch(取指)→Decoder(译码: MemWrite=1)
→RegFile(读t0)→ALU(计算地址0xFFFF0100)
→DataMemory(Addr=0xFFFF0100, WriteData=0x0A48)
```

**第2步 — MMIO地址译码（硬件路由）**

DataMemory.v 中检测到 Addr[31:16]=0xFFFF，判定这不是普通内存访问，而是外设操作。然后根据 Addr[15:0] 区分：

```
0xFFFF0000 → 开关    0xFFFF0008 → LED
0xFFFF0004 → 按键    0xFFFF0100-0xFFFF13BF → VGA帧缓冲
```

CPU 以为自己只是在写内存，但硬件译码器把这次写操作路由到了帧缓冲 BRAM。这就是 MMIO（内存映射I/O）的核心思想。

**第3步 — 双端口BRAM（零开销软硬件通信）**

```
      Port A (CPU, 12.5MHz)          Port B (VGA, 25MHz)
      ─────────────────────          ────────────────────
      negedge clk: 写入 0x0A48      posedge clk_pix: 读出 0x0A48
      写 buffer[0]                   读 buffer[0]
                     ↘              ↙
                  同一块物理BRAM
                (2400 × 16-bit)
```

CPU 和 VGA 是**完全异步**的两个系统——时钟不同、工作内容不同、互不知晓对方存在。FPGA 的硬核 BRAM 原生支持这种真双端口并行访问，无需任何软件锁或同步机制。

**第4步 — VGA扫描着色（纯硬件流水线）**

```
h_cnt=0 (屏幕左上角第一个像素):
  fb_addr=0 → BRAM返回0x0A48 → char_data锁存
  → 字模ROM[{0x48(H), v_cnt[3:0]}] → 字符'H'第0行位图
  → 取bit7 → pixel_on=1 → fg=0xA(亮绿) → vga_r/g/b输出
  → 屏幕左上角像素亮绿色
```

这个流程每秒重复 2500 万次（25MHz），扫描 800×525 个位置，其中 640×480 个有效像素通过字模 ROM 查表着色。

### 三条核心原理

**1. MMIO — CPU和外设的统一语言**

CPU 用 `lw`/`sw` 两条指令就能操作所有外设——开关、按键、LED、数码管、VGA 帧缓冲。硬件地址译码器根据地址高 16 位自动路由。CPU 不需要知道外设的存在。

**2. 双端口 BRAM — 软硬件共享内存**

CPU 写入 = 软件表达意图。VGA 读出 = 硬件执行渲染。同一块 BRAM，两个端口，独立时钟，互不干扰。软件写完立刻生效——这是 FPGA 特有的零延迟通信方式。

**3. 增量渲染 — 软硬件分工的最优解**

帧缓冲是持久化的 BRAM：写入的值一直保留，直到被新值覆盖。贪吃蛇每帧只需更新 3 个位置（新蛇头、旧头变身体、擦除蛇尾），不用重绘全部 2400 个字符。软件负责"算"（what changed），硬件负责"存"（persistent memory）。

### 一句话总结

> **软件定义"画什么"，硬件负责"怎么画"。MMIO 是接口，BRAM 是共享内存，VGA 控制器是独立运行的硬件加速器。三者配合，12.5MHz 的简单 CPU 就能驱动 640×480@60Hz 的实时彩色游戏。**

---

## 创新点

1. **纯 Verilog 文本模式 VGA 控制器** — 无需任何 IP 核或外部芯片，全部用 Verilog 手写。字模 ROM 用 `$readmemh` 从 hex 文件加载，可替换任意 8×16 点阵字体。

2. **双端口 BRAM 软硬件通信** — CPU (12.5MHz) 和 VGA (25MHz) 完全异步，通过 FPGA 硬核双端口 BRAM 实现零开销共享内存。CPU 写一个 `sw` 指令，显示器下一帧就能看到。

3. **MMIO 地址空间统一** — VGA 帧缓冲与传统外设 (开关/LED/数码管) 共用同一套 MMIO 译码器，CPU 用 `lw`/`sw` 操作所有外设，无需特殊指令。

4. **像素级流水线** — 2 级流水 (BRAM读→字模查表→着色)，fb_addr 预取提前 2 像素，确保每个字符的第 0 像素就有正确数据。

## 上板操作指南

### 前置条件
- Vivado 2017.4 工程已打开，16 个 .v 文件已添加
- EGO1 通过 Micro-USB 连接学生机
- VGA 线连接 EGO1 → 显示器
- 显示器已开机

### 步骤 1: 综合和烧录
1. Vivado 点击 "Generate Bitstream" → 等待完成 (~10分钟)
2. Open Hardware Manager → Open Target → Auto Connect
3. Program Device → 选择 `TopDebug.bit` → Program
4. EGO1 DONE 灯亮起，显示器从 "No Signal" 变黑屏

### 步骤 2: 基础 VGA 测试
1. 打开串口工具 (115200/8N1)，确认 COM 口
2. 运行 Python 脚本:
```python
import serial, struct
ser = serial.Serial('COM3', 115200, timeout=0.5)

# 暂停CPU → 写VGA帧缓冲 → 恢复运行
ser.write(b'\x03')  # HALT
ser.read(1)

# 地址 0xFFFF0100 (VGA帧缓冲首字): 亮绿 'A'
addr, data = 0xFFFF0100, 0x0A41
ser.write(b'\x41' + struct.pack('>I', addr) + struct.pack('>I', data))
ser.read(1)

ser.write(b'\x02')  # RUN
ser.close()
```
3. **预期结果:** 显示器左上角出现亮绿色字母 'A'

### 步骤 3: 清屏 + 写入测试画面
```python
ser.write(b'\x03'); ser.read(1)
# 清屏: 2400个空格
for i in range(2400):
    addr = 0xFFFF0100 + 2*i
    ser.write(b'\x41' + struct.pack('>I', addr) + struct.pack('>I', 0x0020))
    ser.read(1)
# 写入测试字符串
msg = "Hello RISC-V CPU!"
for i, ch in enumerate(msg):
    addr = 0xFFFF0100 + 2*(5*80 + 30 + i)  # 第5行, 第30列起
    ser.write(b'\x41' + struct.pack('>I', addr) + struct.pack('>I', 0x0F00 | ord(ch)))
    ser.read(1)
ser.write(b'\x02'); ser.close()
```
3. **预期结果:** 第 5 行显示白色 "Hello RISC-V CPU!"

### 步骤 4: 验证结果
- ✅ 显示器正常显示 80×30 字符网格
- ✅ 无雪花/撕裂/抖动
- ✅ 颜色正确 (亮绿 A, 亮红 B, 白色文字)
- ✅ 不同位置显示不同字符

### 故障排查
| 现象 | 检查 |
|------|------|
| 显示器 "No Signal" | VGA 线是否插紧；ego1.xdc 中 VGA 引脚是否全部约束 |
| 黑屏无字符 | 确认已写清屏脚本；检查串口通信正常 |
| 花屏/乱码 | 帧缓冲未初始化 (BRAM 上电随机值)，先清屏 |

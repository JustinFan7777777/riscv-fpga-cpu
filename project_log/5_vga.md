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

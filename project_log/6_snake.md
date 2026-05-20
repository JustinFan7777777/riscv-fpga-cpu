# 贪吃蛇游戏 — 实现与上板指南

## 这是什么？

一款纯 RISC-V RV32I 汇编实现的贪吃蛇游戏，运行在自研单周期 CPU 上。通过 EGO1 开发板的按键控制方向，VGA 显示器输出 80×30 彩色字符画面。

**核心数据：** 417 条 RV32I 指令，80×30 字符网格，500 节最大蛇身，~0.15 秒/帧。

## 文件位置

```
other/snake/snake.asm    # RISC-V 汇编源码 (RARS 兼容, 无 .equ 依赖)
other/snake/snake.hex    # 编译后机器码 (417 条指令)
```

## 如何游玩

### 按键映射

| EGO1 按键 | 引脚 | 功能 |
|----------|------|------|
| btn[0] | R11 | 上 (↑) |
| btn[1] | R17 | 下 (↓) |
| btn[2] | R15 | 左 (←) |
| btn[3] | V1 | 右 (→) |
| btn[4] | U4 | 重新开始 (Reset) |

- 蛇初始向右移动，长度 3，位于屏幕中央
- 吃到红色 `*` (食物) 蛇身增长 1 节，分数 +1
- 撞墙或撞到自己 → 游戏结束，屏幕显示 "GAME OVER"
- 游戏结束画面按 btn[4] 重新开始

### 画面元素

| 字符 | 颜色 | 含义 |
|------|------|------|
| `#` | 暗灰 | 墙壁边框 |
| `@` | 亮绿 | 蛇头 |
| `o` | 亮绿 | 蛇身 |
| `*` | 亮红 | 食物 |
| ` ` | 黑 | 空白区域 |

## 游戏架构

```
┌─────────────────────────────────────────────────────────┐
│                     Game Loop (~0.15s)                   │
│                                                         │
│  BTN[4:0] ──▶ read_input ──▶ DIR (防反向)               │
│                  │                                      │
│                  ▼                                      │
│  DIR ──▶ move_snake                                     │
│            ├── 计算新蛇头坐标 (DIR + head_xy)            │
│            ├── 墙壁碰撞检测 (x in [1,78], y in [1,28])   │
│            ├── 自身碰撞检测 (环形缓冲区遍历, 跳过蛇尾)     │
│            ├── 食物碰撞 → LEN++, place_food              │
│            ├── 无食物 → 擦除蛇尾 (写空格), TAIL++        │
│            └── HEAD++, 绘制新蛇头, 旧头变身体             │
│                  │                                      │
│                  ▼                                      │
│  game_delay (嵌套循环 ~0.15s) → 回到 Game Loop           │
└─────────────────────────────────────────────────────────┘
```

## 内存布局 (DMem)

游戏状态全部存储在 DMem 低地址区 (0x0000_0000 – 0x0000_2024)：

| 地址 | 大小 | 变量 | 说明 |
|------|------|------|------|
| 0x0000 – 0x07FF | 2048B | SNAKE_X[512] | 蛇身 X 坐标环形缓冲区 |
| 0x0800 – 0x0FFF | 2048B | SNAKE_Y[512] | 蛇身 Y 坐标环形缓冲区 |
| 0x2000 | 4B | HEAD | 蛇头索引 (环形缓冲区) |
| 0x2004 | 4B | TAIL | 蛇尾索引 |
| 0x2008 | 4B | LEN | 当前蛇身长度 |
| 0x200C | 4B | DIR | 方向 (0=上 1=下 2=左 3=右) |
| 0x2010 | 4B | FOOD_X | 食物 X 坐标 |
| 0x2014 | 4B | FOOD_Y | 食物 Y 坐标 |
| 0x2018 | 4B | STATE | 状态 (0=运行 1=结束) |
| 0x201C | 4B | LFSR | 伪随机数发生器状态 |

**环形缓冲区：** 蛇身存储在大小为 512 的环形缓冲区中。HEAD 指向最新蛇头，TAIL 指向最早蛇尾。移动时 HEAD 前进、覆盖新坐标；无食物时 TAIL 前进、擦除旧坐标。使用 `& 0x1FF` 取模。

**寄存器约定：**

| 寄存器 | 保存内容 |
|--------|---------|
| s0 | VGA 帧缓冲基址 (0xFFFF_0100) |
| s1 | 按键 MMIO 地址 (0xFFFF_0004) |
| s2 | SNAKE_X 基址 (0x0000_0000) |
| s3 | SNAKE_Y 基址 (0x0000_0800) |
| s4 | 游戏状态基址 (0x0000_2000) |
| sp | 栈指针 (0x0000_F000) |

## 核心算法

### 伪随机数 (LFSR)

16-bit 线性反馈移位寄存器，反馈多项式 x^16 + x^15 + x^14 + x^13 + x^4 + 1：

```
new_bit = lfsr[15] ^ lfsr[14] ^ lfsr[13] ^ lfsr[4]
lfsr = (lfsr >> 1) | (new_bit << 15)
```

食物坐标: `x = (lfsr & 0x7F) % 78 + 1`, `y = (lfsr & 0x1F) % 28 + 1`。含防零保护 (死锁恢复为种子值 0x3A5C)。

### 自身碰撞检测

遍历环形缓冲区中从 `(HEAD - LEN + 1)` 到 `(HEAD - 1)` 的每一节，跳过 TAIL (即将被擦除)，与 new_xy 比对。若匹配则游戏结束。

### VGA 地址计算

```
地址 = 0xFFFF_0100 + 2 × (行 × 80 + 列)
行×80 = 行×64 + 行×16 = (行 << 6) + (行 << 4)    # 移位加法，无乘法指令
```

### 渲染策略

- 只重绘变化的像素 (蛇头、旧头变身体、擦除蛇尾)，不清全屏
- 食物碰撞后重新随机放置，确保不在蛇身上
- 初始化和重启时清全屏 + 重绘边框

## 编译方法

### 方法 1: RARS (推荐，已验证)

```bash
java -jar "Rars Assembler.jar" a dump .text HexText snake.hex snake.asm
```

417 条指令，无错误无警告。

### 方法 2: GNU RISC-V Toolchain

```bash
riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 snake.asm -o snake.o
riscv64-unknown-elf-ld -Ttext 0x00000000 snake.o -o snake.elf
riscv64-unknown-elf-objcopy -O verilog snake.elf snake.hex
```

## 上板流程

### 1. 加载游戏程序

方法 A — 通过 Debug Controller 写入 IMem:

```python
import serial, struct
ser = serial.Serial('/dev/ttyUSB0', 115200, timeout=0.5)

# 暂停 CPU
ser.write(b'\x03')
ser.read(1)

# 逐条写入 snake.hex 到 IMem 地址 0x00000000
with open('snake.hex') as f:
    for i, line in enumerate(f):
        instr = int(line.strip(), 16)
        addr = i * 4
        ser.write(b'\x40' + struct.pack('>I', addr) + struct.pack('>I', instr))
        assert ser.read(1)[0] == 0x81

# 复位 CPU (PC=0x4000, 但我们需要从 0x0000 开始)
# 注意: 当前 PC_RESET = 0x4000, 需要通过 Debug 写入 PC 或修改 Ifetch 参数
```

方法 B — 修改 Ifetch.v 参数:

```verilog
// Ifetch.v 中修改
parameter PC_RESET = 32'h00000000;  // 从 0x4000 改为 0x0000
parameter INIT_FILE = "../../../../other/snake/snake.hex";  // 直接加载 snake.hex
```

重新综合烧录后，上电即自动运行贪吃蛇。

### 2. 连接外设

- VGA 线连接 EGO1 和显示器
- 无需 UART (游戏不需要 PC 通信)
- 仅需 EGO1 供电即可独立运行

### 3. 操作

1. 上电 → 自动初始化 VGA + 贪吃蛇
2. 按 btn[0]–btn[3] 控制方向
3. 游戏结束按 btn[4] 重新开始

## 延迟调优

如果游戏太快或太慢，修改 snake.asm 中的延迟参数后重新编译：

```
# snake.asm 中
# 当前值: DL_OUTER=800, DL_INNER=1200 → ~0.15秒/帧 @12.5MHz
# 更快: 减小 DL_OUTER/DL_INNER
# 更慢: 增大 DL_OUTER/DL_INNER

li t0, 0x320      # DL_OUTER (当前 800)
li t1, 0x4B0      # DL_INNER (当前 1200)
```

延迟时间 ≈ DL_OUTER × DL_INNER × 2 / 12.5MHz。当前 800 × 1200 × 2 / 12.5M ≈ 0.15 秒。

## 已知限制

| 限制 | 说明 |
|------|------|
| 无音效 | 纯视觉游戏 |
| 无分数显示 | 可在 game_over_screen 附近添加分数渲染 |
| 500 节最大蛇身 | 超过后视为胜利 (游戏结束)，80×30=2400 格远未用完 |
| 速度固定 | 不支持变速 (可通过修改延迟参数调整) |
| 仅 EGO1 | 依赖 EGO1 按键和 VGA 引脚 |

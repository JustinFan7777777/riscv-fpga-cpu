# Bonus 总体方案 — 满分 10 分 (五线并行)

> 当前进度: 基础功能 80 分已锁定 (33/33 Difftest PASS)

---

## 总览

| # | Bonus 项目 | 类别 | 最高分 | 状态 |
|---|-----------|------|--------|------|
| 1 | VGA 文本显示 | 复杂外设接口 | 5 | 待实现 |
| 2 | 贪吃蛇游戏 | 软硬件协同应用 | 5 | 待实现 |
| 3 | ISA 指令扩展 | ISA 扩展 | 4 | 待确定 |
| 4 | RISC-V CPU 通关游戏 | 教学效率工具 | 2 | 待实现 |
| 5 | 五级流水线 | 架构优化 | 6 | 待实现 |

> 五项合计未设上限，但 Bonus 类总分封顶 10 分。建议优先实现 ①②④ (确保 10 分)，③⑤ 作为超额展示。

---

## 一、VGA 文本显示 [5分] — 复杂外设接口

### 1.1 技术方案

EGO1 板载 VGA 接口 (vga_hs, vga_vs, vga_r[3:0], vga_g[3:0], vga_b[3:0])，无需额外硬件。

**显示规格：** 80 列 × 30 行，字符 8×16 像素，640×480@60Hz

**模块架构：**
```
VGAController (新增 Verilog 模块)
├── VGA 时序生成器 — HSync/VSync 计数器 → 行列像素坐标
├── 字符 ROM — 8×16 点阵，128 个 ASCII 字符 (BRAM, ~2KB)
├── 帧缓冲   — 80×30 字符 × 2字节 = 4800B (BRAM)
│   └── 每字符: [7:0]=ASCII码, [15:8]=前景色/背景色
└── 像素输出 — 行列坐标 → 字符查表 → 字模取点 → RGB 输出
```

**像素时钟：** 25MHz (100MHz/4，与 CPU 不同的时钟域)

### 1.2 改动文件

| 文件 | 改动 |
|------|------|
| `VGA.v` | **新增** — VGA 控制器 (含时序、字模ROM、帧缓冲) |
| `TopDebug.v` | 添加 VGA 端口 (12-bit: hs/vs/r/g/b) + 实例化 VGA |
| `DataMemory.v` | 新增 MMIO 区域: `0xFFFF_0100–0xFFFF_12BF` → VGA 帧缓冲 |
| `ego1.xdc` | 添加 VGA 12 个引脚约束 |

### 1.3 MMIO 地址规划

```
0xFFFF_0100 – 0xFFFF_12BF : VGA 帧缓冲
  每字 16-bit: bit[7:0]=ASCII, bit[15:8]=颜色属性
  (80×30=2400 字 × 2B = 4800B)
```

CPU 通过 `sw` 写显存：`sw x1, 0xFFFF0100(x0)` → 屏幕左上角显示字符。

---

## 二、贪吃蛇游戏 [5分] — 软硬件协同应用

### 2.1 技术方案

纯 RISC-V 汇编实现，运行在自研 CPU 上，通过 MMIO 读取按键方向，写入 VGA 帧缓冲渲染画面。

**游戏逻辑：**
```
主循环 (~0.3s 延迟):
  1. 读取按键 MMIO (0xFFFF0004) → 方向
  2. 更新蛇身坐标 (数组, 最多 2400 个)
  3. 检查碰撞 (边界/自身) → 游戏结束
  4. 检查食物 → 增长蛇身 + 生成新食物
  5. 渲染: 清空帧缓冲 → 画边框 → 画蛇身(@) → 画食物(*) → 写 VGA 帧缓冲
```

**按键映射：**
- 上: btn[0] (V1), 下: btn[1] (U4)
- 左: btn[2] (R15), 右: btn[3] (R17)
- 复位/重开: btn[4] (R11)

### 2.2 文件

| 文件 | 内容 |
|------|------|
| `other/snake.asm` | 贪吃蛇完整汇编 (~300 行) |
| `other/snake.hex` | 编译后机器码 |

### 2.3 核心数据结构

```
游戏状态 (DMem 中):
  0x4000: 蛇身X坐标数组 (16-bit × 长度)
  0x4100: 蛇身Y坐标数组
  0x4200: 蛇长度 (当前)
  0x4204: 当前方向 (0=上 1=下 2=左 3=右)
  0x4208: 食物X坐标
  0x420C: 食物Y坐标
  0x4210: 游戏状态 (0=运行 1=结束)
```

---

## 三、ISA 指令扩展 [4分]

### 3.1 可选方案

| 方案 | 内容 | 预估分 | 难度 |
|------|------|--------|------|
| A | ecall 环境调用指令 | 2 | 低 |
| B | M 扩展 — MUL/DIV/REM | 3 | 中 |
| C | 硬件加速 — POPCOUNT/CLZ/CTZ | 4 | 中 |

**推荐方案 C (硬件加速指令)：**

新增 3 条 R-type 指令，使用 RV32M 未占用的 funct7 编码空间：

| 指令 | 功能 | opcode | funct3 | funct7 |
|------|------|--------|--------|--------|
| POPCNT | `rd = popcount(rs1)` | 0110011 | 001 | 0000001 |
| CLZ | `rd = count_leading_zeros(rs1)` | 0110011 | 010 | 0000001 |
| CTZ | `rd = count_trailing_zeros(rs1)` | 0110011 | 011 | 0000001 |

**ALU 实现要点：**
```verilog
// POPCNT: 分治法 32-bit popcount (组合逻辑, O(logN))
// CLZ/CTZ: 优先编码器

4'b1010: ALUResult = popcount(A);  // 需实现 popcount function
4'b1011: ALUResult = clz(A);
4'b1100: ALUResult = ctz(A);
```

**改动文件：** ALU.v, Decoder.v (主译码器 + ALU 译码器)

**自备测试用例：** `other/isa_test.asm` — 覆盖边界值 (全0, 全1, 随机值)

### 3.2 方案 D: ecall (备选, 2分)

```verilog
// ecall: opcode=1110011 (SYSTEM), funct3=000, imm=0
// 触发伪异常: 将当前 PC+4 写入特定寄存器, 跳转到 trap handler
```

---

## 四、RISC-V CPU 通关游戏 [2分] — 教学效率工具

### 4.1 产品定位

一款**浏览器内运行的 RISC-V 学习通关游戏**，面向 CO 课程学生，帮助理解：
- RISC-V 指令类型和编码格式
- 不同指令类型的控制信号选择
- CPU 数据通路 (单周期 + 流水线)
- 流水线冒险与解决方案
- 汇编编程基础

**核心创新：** 可视化的动态 CPU 数据通路图，点击任何指令类型即时展示 IF→ID→EX→MEM→WB 数据流动。

### 4.2 技术实现

**技术栈：** 纯 HTML + CSS + JavaScript + SVG (零依赖，双击 HTML 即可运行，兼容学生机断网环境)

**文件结构：**
```
other/riscv_game/
├── index.html       # 主页面 (全部逻辑内嵌)
├── cpu_draw.js      # SVG 可视化引擎
└── questions.js     # 题库
```

**存放位置：** `other/riscv_game/` — 打包进压缩包提交。

### 4.3 关卡设计 (6 关)

#### 第 0 关 — 新手村：认识 RISC-V 指令类型

**场景：** 6 张指令卡片随机排列，拖拽到对应的类型框中 (R/I/S/B/U/J)。

**示例题目：**
- `add x1, x2, x3` → 拖到 R-type
- `addi x1, x2, 100` → 拖到 I-type
- `sw x1, 0(x2)` → 拖到 S-type
- `beq x1, x2, label` → 拖到 B-type
- `lui x1, 0x12345` → 拖到 U-type
- `jal x1, label` → 拖到 J-type

**过关条件：** 12 题全对

#### 第 1 关 — 指令解码器：识别机器码

**场景：** 给定 32-bit 机器码 (十六进制)，分解出 opcode / funct3 / funct7 / rs1 / rs2 / rd / imm。

**示例：**
- `0x002081B3` → opcode=? funct3=? rs1=? rs2=? rd=?
  - 答案: opcode=0110011, funct3=000, rs1=x1(00001), rs2=x2(00010), rd=x3(00011) → ADD

**过关条件：** 8 题正确率 ≥ 80%

#### 第 2 关 — 控制信号大师：选择 Control Bits

**场景：** 屏幕上方显示**动态 CPU 数据通路图 (SVG)**，下方显示一条指令。玩家点击数据通路图上的控制信号 MUX 选择正确的值。

对于每条指令，玩家需要选择：
- RegWrite: 1 或 0
- ALUSrc: 0(rs2) 或 1(imm)
- MemtoReg: 0(ALU) 或 1(Mem)
- MemWrite: 1 或 0
- Branch: 1 或 0
- Jump: 1 或 0
- ALUOp: 00/01/10/11

**可视化效果：** 玩家每选对一个信号，数据通路图中对应的路径就会**高亮发光**，形成完整的数据流动动画。

**示例题目：**
| 指令 | RegWrite | ALUSrc | MemtoReg | MemWrite | Branch | Jump | ALUOp | 
|------|----------|--------|----------|----------|--------|------|-------|
| ADD | 1 | 0 | 0 | 0 | 0 | 0 | 10 |
| LW | 1 | 1 | 1 | 0 | 0 | 0 | 00 |
| SW | 0 | 1 | x | 1 | 0 | 0 | 00 |
| BEQ | 0 | 0 | x | 0 | 1 | 0 | 01 |
| JAL | 1 | 1 | x | 0 | 0 | 1 | 00 |

**过关条件：** 覆盖全部 7 种 opcode 类型，正确率 ≥ 90%

#### 第 3 关 — 数据通路追踪：一条指令的旅程

**场景：** 大型 SVG 数据通路图。玩家点击数据通路中的组件 (按正确顺序) 来追踪一条指令从取指到写回的完整路径。

**示例：** 指令 `lw x1, 4(x2)` 的数据通路追踪：
```
1. PC → IMem              (IF: 取指)
2. IMem → inst            (IF: 输出指令)
3. inst → Decoder         (ID: 译码, 产生控制信号)
4. inst[19:15] → RegFile  (ID: 读 rs1=x2)
5. inst[31:20] → ImmGen   (ID: 生成立即数 4)
6. rs1_val → ALU_A        (EX: rs1=x2的值)
7. Imm → ALU_B            (EX: 立即数4)
8. ALU → ALUResult        (EX: x2+4, 即地址)
9. ALUResult → DMem addr  (MEM: 读内存地址)
10. DMem → ReadData        (MEM: 读出内存数据)
11. ReadData → WD3         (WB: 选通MemtoReg)
12. WD3 → RegFile          (WB: 写回x1)
```

**可视化效果：** 玩家每次正确点击，对应连线**从灰色变为绿色并产生流动粒子动画**。点到错误位置时，组件**闪烁红色提示**。

**过关条件：** 正确追踪 R-type / I-type / Load / Store / Branch / JAL 共 6 种指令类型的数据通路

#### 第 4 关 — 流水线冒险：识别与解决

**场景：** 屏幕显示五级流水线图 (IF/ID/EX/MEM/WB)，连续多条指令流经各阶段。玩家识别冒险类型并选择解决方案。

**冒险类型：**
- **数据冒险 (RAW)：** `add x1,x2,x3` → `sub x4,x1,x5` (x1 未写回即被读)
  - 解决：Forwarding — 从 EX/MEM 转发到 EX 的 ALU 输入
- **控制冒险：** `beq x1,x2,label` 后的指令
  - 解决：Flush + 预测不跳转，或 Stall 等待分支结果
- **结构冒险：** IMem 和 DMem 同时访问
  - 解决：哈佛结构分离 IMem/DMem

**可视化效果：**
- 展示 5 级流水线图 (IF/ID/EX/MEM/WB 横向排列)
- 多条指令从右向左流动 (每周期前进一级)
- 发生冒险时：相关连线**红色闪烁**
- 玩家选择 forwarding 后：增加一条**绿色虚线**从 EX/MEM 旁路到 EX ALU 输入
- 玩家选择 stall 后：IF/ID 阶段**暂停一周期** (插入 bubble)

**过关条件：** 3 种冒险各出 2 题 (共 6 题)，全部正确

#### 第 5 关 — ASM 编程挑战

**场景：** 简单的在线汇编器。给出功能需求，玩家编写 RISC-V 汇编。

**题目示例：**
1. "用最少指令实现 `x3 = x1 * 8`" → `slli x3, x1, 3`
2. "实现 `if (x1 == x2) x3 = 1 else x3 = 0`" → `beq` + `addi`
3. "实现交换 x1 和 x2 的值 (不借助其他寄存器)" → `xor` 三次异或

**反馈：** 输入汇编 → 模拟执行 → 显示寄存器最终值 → 比对预期

**过关条件：** 5 题中答对 3 题

### 4.4 数据通路可视化 — 核心 SVG 设计

**单周期数据通路图 (完整版)：**

```
                              +----------+
                              |  PC+4    |
                              +----+-----+
                                   |
  +-------+     +---------+    +---v-----+    +---------+    +---------+
  | PC    |---->| IMem    |--->| Decoder |--->| RegFile |--->| ALU_A   |
  |(0x4000|    |(64KB)   |    |+ImmGen  |    |  32x32  |    |  MUX    |
  +-------+    +---------+    +---------+    +---------+    +----+----+
      ^                                                          |
      |                     +---------+    +---------+    +------v------+
      |                     | Next-PC |<---| Branch  |<---| ALU         |
      |                     |  MUX    |    | Compare |    | (10 ops)    |
      |                     +---------+    +---------+    +------+------+
      |                                                          |
      |               +---------+    +---------+    +-----------v-----+
      +---------------| WD3 MUX |<---| MemtoReg|<---| DataMemory      |
                      +---------+    |  MUX    |    | (DMem + MMIO)   |
                           |         +---------+    +-----------------+
                      +----v----+
                      | RegFile |
                      | (write) |
                      +---------+
```

**流水线五级图：**

```
         IF            ID            EX            MEM           WB
    +----------+  +----------+  +----------+  +----------+  +----------+
    | IMem     |  | Decoder  |  | ALU      |  | DMem     |  | RegFile  |
    | PC Update|->| RegFile  |->| MUXes    |->| (R/W)    |->| (Write)  |
    |          |  | ImmGen   |  | Branch   |  |          |  | MemtoReg |
    +----------+  +----------+  +----------+  +----------+  +----------+
         |              |             |             |             |
    IF/ID reg     ID/EX reg     EX/MEM reg    MEM/WB reg
    (Pipeline)    (Pipeline)    (Pipeline)    (Pipeline)
```

### 4.5 技术要点

**SVG 动画引擎 (cpu_draw.js)：**

核心类：
```javascript
class CPUDatapath {
  drawSingleCycle()    // 绘制单周期数据通路
  drawPipeline()        // 绘制五级流水线
  highlightPath(stages) // 高亮指定阶段的数据路径
  animateInstruction(type, from, to)  // 动画展示指令执行
}
```

**数据流动画实现：**
- 使用 SVG `<path>` + CSS `stroke-dasharray` + `stroke-dashoffset` 动画模拟流动粒子
- 使用 `requestAnimationFrame` 控制动画帧率
- 组件状态：`idle`(灰), `active`(绿), `error`(红), `forwarding`(蓝虚线)

**题库设计 (questions.js)：**
- 结构化 JSON 数据
- 支持随机抽题、难度分级
- 记录通关时间 (用于排名/成就)

---

## 五、五级流水线 [6分] — 架构优化

### 5.1 关键约束

> requirement: "如实现 pipeline，也需要实现单周期 CPU，将两种 CPU 整合到一个 top 模块中，并支持切换模式"

这意味着：
- 保留现有单周期 CPU **不动**
- 新建流水线 CPU 模块 (CPUTopPipeline)
- 顶层 TopDebug 增加一个模式选择信号 → 切换两个 CPU
- 可减小 IMem/DMem 到 32KB 或 16KB

### 5.2 流水线 CPU 模块设计

**五级流水：** IF → ID → EX → MEM → WB

**流水线寄存器：**
```
IF/ID:  PC+4, inst
ID/EX:  PC+4, rs1_val, rs2_val, Imm, funct3, funct7,
        RegWrite, MemtoReg, MemWrite, Branch, Jump, ALUControl,
        ALUSrc, rs1_addr, rs2_addr, rd_addr
EX/MEM: PC+4, ALUResult, WriteData(rs2), rd_addr,
        RegWrite, MemtoReg, MemWrite, Branch, Jump, BranchTarget
MEM/WB: ReadData, ALUResult, rd_addr, RegWrite, MemtoReg
```

**冒险处理：**
- **数据冒险 (RAW)：** Forwarding unit — 从 EX/MEM, MEM/WB 转发到 EX 的 ALU 输入；Load-use hazard → Stall 1 周期
- **控制冒险：** 假设不跳转 + 跳转时 Flush IF/ID (1 周期 penalty)

### 5.3 改动文件

| 文件 | 改动 |
|------|------|
| `CPUTopPipeline.v` | **新增** — 流水线 CPU 顶层 |
| `Ifetch_Pipe.v` | **新增** — 流水线版 IMem (需双口读避免结构冲突) |
| `HazardUnit.v` | **新增** — 冒险检测 + Forwarding |
| `PipeRegs.v` | **新增** — 4 组流水线寄存器 (IF/ID, ID/EX, EX/MEM, MEM/WB) |
| `TopDebug.v` | 修改 — 增加 `mode` 端口 + 二选一 MUX |

### 5.4 模式切换

```verilog
// TopDebug.v
wire cpu_mode;  // 0=单周期, 1=流水线 (通过拨码开关或 Debug 命令切换)

// MMIO 地址: 0xFFFF_0020 → mode (读/写)
```

### 5.5 验证要求

- 同一测试用例 (如 Fibonacci 循环) 在两种模式下运行，对比执行时间
- 包含 control hazard 和 data hazard 的汇编片段能正确通过
- Debug 模式可暂停并观察寄存器值和流水线寄存器

---

## 实现优先级 & 时间线

```
第 15 周:
  周一：  VGA.v 编写 + 字模 ROM           [范晓乐]
  周二：  TopDebug 修改 + XDC + 综合测试    [范晓乐 + 陈俊希]
  周三：  snake.asm 编写 + RARS 模拟       [刘一骏]
  周四：  上板联调 VGA + 贪吃蛇             [全员]
  周五：  RISC-V 通关游戏 HTML/JS/SVG      [范晓乐]
  周末：  录制视频 + 填写问卷文档            [全员]

第 16 周:
  周一-周五: ISA 扩展 / 流水线 (超额展示)    [按时间窗口选做]
  周末:     最终提交 (截止 15 周周一已过，迟交系数生效)
```

---

## 风险与对策

| 风险 | 对策 |
|------|------|
| VGA 时序不收敛 (25MHz pixel clock) | 降 pixel clock 或减分辨率 |
| Snake 游戏帧率过低 (12.5MHz CPU) | 缩小地图 (40×15) 减少渲染量 |
| 流水线两周不够 | 降级方案：仅实现 3 级流水 (IF/EX/WB) |
| 网页应用开发量超预期 | 先做 3 关核心关卡，其余标注 "开发中" |

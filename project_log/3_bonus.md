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

## 四、RISC-V CPU 单周期数据通路可视化工具 [2分] — 教学效率工具

### 4.1 产品定位

一款**浏览器内运行的 CPU 单周期数据通路可视化工具**，面向 CO 课程学生，帮助直观理解：

- 单周期 CPU 各组件 (PC/IMem/Decoder/ImmGen/RegFile/ALU/DataMemory) 的物理连接
- 不同指令类型 (R/I/Load/Store/B/U/J) 的数据通路差异
- 控制信号 (RegWrite/ALUSrc/MemtoReg/MemWrite/Branch/Jump/JALRSrc/ALUOp) 如何引导数据流动
- 为什么 LUI 的 ALU_A=0？为什么 JAL 的 WD3=PC+4？

**核心创新：** 用户从下拉菜单选择一条指令 → SVG 数据通路图中对应路径**逐级点亮**(绿色高亮 + 流动动画)，从左到右展示 IF → ID → EX → MEM → WB 五阶段的数据流动。右侧面板同步显示控制信号表 (0/1/x) 和文字描述。

**与游戏的差异：** 去掉关卡/计分/通关机制，聚焦纯可视化——选指令，看通路，理解 CPU。更简洁，更专业。

### 4.2 技术实现

**技术栈：** 纯 HTML + CSS + JavaScript + SVG (零依赖，双击 HTML 即可运行，兼容学生机断网环境)

**文件结构：**
```
other/cpu_viz/
└── index.html          # 全部 HTML/CSS/JS 内嵌，单文件
```

### 4.3 可视化设计

#### 整体布局

```
┌──────────────────────────────────────────────────────────┐
│                    ┌─ 五阶段标签: IF | ID | EX | MEM | WB │
│   ┌──────────┐     │                                      │
│   │ 指令选择  │     │   SVG 数据通路图 (渐进式点亮)          │
│   │ [下拉框]  │     │                                      │
│   │          │     │   PC→IMem→Decoder┐                   │
│   │ 控制信号  │     │       ↓    ImmGen┤→RegFile           │
│   │ RegWrite │     │   ALU_A_MUX─┐    │                   │
│   │ ALUSrc   │     │   ALU_B_MUX─┤→ALU→DMem→MemtoReg→RegW │
│   │ ...      │     │   Branch→NextPC→PC                   │
│   │          │     │                                      │
│   │ 文字描述  │     │   (未激活路径灰色, 激活路径绿色发光)    │
│   └──────────┘     │                                      │
│                    └──────────────────────────────────────┘
└──────────────────────────────────────────────────────────┘
```

#### 配色方案

| 阶段 | 颜色 | CSS |
|------|------|-----|
| IF (取指) | 蓝色 | `#3B82F6` |
| ID (译码) | 紫色 | `#8B5CF6` |
| EX (执行) | 橙色 | `#F59E0B` |
| MEM (访存) | 黄色 | `#EAB308` |
| WB (写回) | 绿色 | `#10B981` |
| 未激活 | 灰色 | `#374151` |
| 控制信号=1 | 亮绿 | `#34D399` |
| 控制信号=0 | 暗红 | `#EF4444` |

#### 指令数据定义 (10 条代表性指令)

每条指令定义: 激活的组件列表 → 激活的连线列表 → 控制信号值 → 文字描述

| # | 指令 | 类型 | 关键通路差异 |
|---|------|------|------------|
| 1 | ADD | R-type | rs1+rs2→rd, RegWrite=1, ALUSrc=0 |
| 2 | SUB | R-type | 同ADD, ALUControl=funct7决定减法 |
| 3 | ADDI | I-type ALU | rs1+imm→rd, ALUSrc=1 |
| 4 | LW | Load | mem[rs1+imm]→rd, MemtoReg=1 |
| 5 | SW | Store | rs2→mem[rs1+imm], RegWrite=0, MemWrite=1 |
| 6 | BEQ | B-type | 比较rs1==rs2, RegWrite=0, Branch=1 |
| 7 | LUI | U-type | 0+imm→rd, ALU_A=0, ALU_B=imm |
| 8 | AUIPC | U-type | PC+imm→rd, ALU_A=PC, ALU_B=imm |
| 9 | JAL | J-type | PC+4→rd, PC→PC+imm, Jump=1 |
| 10 | JALR | I-jump | PC+4→rd, PC→(rs1+imm)&~1, JALRSrc=1 |

#### SVG 组件清单

| ID | 组件 | 坐标 (viewBox) |
|----|------|---------------|
| `pc` | PC 寄存器 | 左上方 |
| `imem` | 指令内存 IMem | PC 右侧 |
| `decoder` | 译码器 Decoder | IMem 下方 |
| `immgen` | 立即数生成器 ImmGen | Decoder 左侧 |
| `regfile` | 寄存器堆 RegFile | Decoder 下方 |
| `alu_a_mux` | ALU-A 选择器 | RegFile 左下方 |
| `alu_b_mux` | ALU-B 选择器 | RegFile 右下方 |
| `alu` | 算术逻辑单元 ALU | 两 MUX 下方 |
| `dmem` | 数据内存 DMem + MMIO | ALU 右方 |
| `memtoreg_mux` | MemtoReg 选择器 | DMem 下方 |
| `branch_comp` | 分支比较器 | RegFile 右侧 |
| `nextpc_mux` | Next-PC 选择器 | PC 左侧 |

#### 连线 (paths) 清单

每条连线定义: id, from, to, 激活条件

| ID | 路径 | 说明 |
|----|------|------|
| `pc_to_imem` | PC → IMem | 所有指令 |
| `imem_to_decoder` | IMem → Decoder | 所有指令 |
| `imem_to_immgen` | IMem → ImmGen | 所有指令 (ImmGen 总是运作) |
| `decoder_regwrite` | Decoder → RegFile (WE) | RegWrite=1 |
| `decoder_alusrc` | Decoder → ALU-B MUX | 控制 ALUSrc |
| `decoder_memtoreg` | Decoder → MemtoReg MUX | 控制 MemtoReg |
| `decoder_memwrite` | Decoder → DMem (WE) | MemWrite=1 |
| `decoder_branch` | Decoder → Branch Comp | Branch=1 |
| `decoder_jump` | Decoder → Next-PC MUX | Jump=1 |
| `decoder_jalrsrc` | Decoder → Next-PC MUX | JALRSrc=1 |
| `rs1_to_alu_a` | RegFile.rs1 → ALU-A MUX | 默认路径 |
| `pc_to_alu_a` | PC → ALU-A MUX | AUIPC 时选通 |
| `zero_to_alu_a` | 0 → ALU-A MUX | LUI 时选通 |
| `rs2_to_alu_b` | RegFile.rs2 → ALU-B MUX | ALUSrc=0 |
| `imm_to_alu_b` | ImmGen → ALU-B MUX | ALUSrc=1 |
| `alu_to_dmem` | ALU → DMem (addr) | 所有指令 |
| `rs2_to_dmem` | RegFile.rs2 → DMem (wd) | SW 时有效 |
| `dmem_to_memtoreg` | DMem → MemtoReg MUX | Load 时选通 |
| `alu_to_memtoreg` | ALU → MemtoReg MUX | 默认路径 |
| `pcplus4_to_memtoreg` | PC+4 → MemtoReg MUX | JAL/JALR 时选通 (已整合到WD3 MUX) |
| `wd3_to_regfile` | WD3 → RegFile (wd) | RegWrite=1 |
| `rs1_to_branch` | RegFile.rs1 → Branch Comp | Branch=1 |
| `rs2_to_branch` | RegFile.rs2 → Branch Comp | Branch=1 |
| `branch_to_nextpc` | Branch Comp → Next-PC MUX | 分支满足时 |
| `nextpc_to_pc` | Next-PC MUX → PC | 所有指令 |

### 4.4 交互设计

1. 页面加载 → 默认选中 ADD 指令 → 数据通路按 ADD 高亮
2. 用户从下拉框切换指令 → 通路即时切换 (CSS transition, ~0.5s)
3. 鼠标悬停组件 → tooltip 显示组件功能说明
4. 控制信号表实时更新 (绿色=1, 红色=0, 灰色=x/don't care)
5. 底部文字描述该指令的完整数据流动

### 4.5 技术要点

- SVG 使用 `<path marker-end="url(#arrow)">` 绘制箭头
- 高亮通过 CSS class `.active` 切换实现 `transition: stroke 0.3s`
- 控制信号表用 JS 对象字面量映射，按 opcode 索引
- 单文件 HTML ~500 行，提交到 `other/cpu_viz/index.html`

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

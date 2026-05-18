# CPU Project 完整进展总结 (截至第 15 周 — 基础部分完成)

---

## 1. 项目基本盘

| 项 | 值 |
|----|-----|
| 指令集 | RISC-V RV32I |
| CPU 架构 | 单周期 (Single-cycle), 哈佛结构 |
| CPU 时钟 | 12.5MHz (100MHz 系统时钟 / 8 + BUFG) |
| IMem | 64KB BRAM, PC_RESET=0x4000, hex 从 mem[4096] 加载, 组合读 |
| DMem | 64KB BRAM + MMIO (0xFFFF0000 起) |
| 开发板 | EGO1 (XC7A35T) |
| Vivado | 2017.4 |
| 顶层模块 | TopDebug |
| 已实现指令 | **31 条** (R/I/S/B/U/J 全部基础类型, 缺 LH/LB/SH/SB 共 6 条 byte/halfword) |
| 基础 Case | 10 个全覆盖 (Case 0-9) |
| Debug | DebugController + UartRx/UartTx, 11 条命令 |
| Difftest | **33/33 PASS** ✅ |

---

## 2. 文件清单

### 2.1 Verilog 源文件 (11 个)

```
cpu_project/cpu_project.srcs/sources_1/new/
├── TopDebug.v          # 工程顶层: 时钟分频+BUFG, 复位合并, 实例化所有组件
├── CPUTop.v            # CPU顶层: 单周期数据通路, 6子模块连线, WD3/Branch/Next-PC
├── Ifetch.v            # 取指: PC+IMem BRAM(64KB), Next-PC MUX, Debug口, $readmemh
├── Decoder.v           # 译码: Main Decoder(8控制信号) + ALU Decoder(4-bit ALUControl)
├── ImmGen.v            # 立即数: I/S/B/U/J 六种格式提取+符号扩展
├── RegFile.v           # 寄存器堆: 32x32, x0=0, 双读口+Debug读口
├── ALU.v               # ALU: ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU + Zero
├── DataMemory.v        # 数据内存: DMem BRAM(64KB) + MMIO译码(6外设), Debug口
├── DebugController.v   # Debug控制器: FSM(6状态), 11命令, 跨时钟域, UART协议
├── UartRx.v            # UART接收: 115200/8N1, 双触发器同步, 半bit起始验证
└── UartTx.v            # UART发送: 115200/8N1, tx_busy握手, LSB first
```

### 2.2 其他工程文件

```
├── create_project.tcl           # Vivado 一键建工程脚本
├── .gitignore                   # Vivado 忽略规则
├── assembly/
│   ├── batch_test.asm           # 10 Case 汇编 (390行)
│   └── batch_test.hex           # 编译后 hex (130条指令)
└── cpu_project/cpu_project.srcs/constrs_1/
    └── ego1.xdc                 # EGO1 引脚约束 (时钟/复位/UART/开关/LED/按键/数码管)
```

### 2.3 协作文件 (project_log/)

```
project_log/
├── README.md           # 导览: 文件索引 + 项目概况 + 成员信息
├── 0_todo.md            # 时间线行动清单: 4阶段17步骤, 每步标负责人
├── 1_report.md          # 报告素材: 提纲 + 汇编设计说明(10 Case) + 心路历程(7条) + Bug记录(8条)
├── 2_progress.md        # 课程进度检查表 (5/19提交)
└── 3_test_results.md    # RARS 验证结果 (21/21 PASS)
```

---

## 3. 架构核心细节

### 3.1 数据通路

```
PC(0x4000)→IMem→inst→Decoder(控制信号)
                    →RegFile(rs1,rs2)
                    →ImmGen(立即数)
                    →ALU_A MUX(LUI=0, AUIPC=PC, else=rs1)
                    →ALU_B MUX(ALUSrc=0→rs2, =1→imm)
                    →ALU→ALUResult
                        →DataMemory(addr)→ReadData
                        →MemtoReg MUX→WD3→RegFile(writeback)
                    →Branch比较→PCSrc→Next-PC MUX→PC
```

### 3.2 关键设计决策

**ALU_A MUX (CPUTop.v:210-215)**
- LUI: ALU_A=0, ALU_B=imm → ALUResult = 0+imm = imm (加载立即数)
- AUIPC: ALU_A=PC, ALU_B=imm → ALUResult = PC+imm
- 其他: ALU_A=rs1

**WD3 MUX (CPUTop.v:257-259)**
- JAL/JALR: WD3 = PC+4 (链接地址)
- Load: WD3 = ReadData (内存值)
- 其他: WD3 = ALUResult

**Branch 判断 (CPUTop.v:265-273)**
- 直接在 CPUTop 用 funct3 比较 rs1/rs2, 不使用 ALU Zero (更短路径)

**Next-PC 优先级 (Ifetch.v:147-152)**
- halt > reset > JALR > JAL > branch taken > PC+4

**difftest 地址对齐 (Ifetch.v)**
- PC_RESET = 32'h00004000
- HEX_LOAD_OFFSET = PC_RESET >> 2 (localparam 自动推导)
- $readmemh(INIT_FILE, mem, HEX_LOAD_OFFSET) → hex 加载在 mem[4096] (字节地址 0x4000)
- 原因: difftest 框架默认从 IMem 0x4000 放指令

**IMem 读取方式**
- 组合读 (combinational read): `assign inst = mem[imem_addr]`
- 原因: 单周期 CPU 要求当周期取指，BRAM 寄存器读会引入 1 周期延迟
- 写仍为同步时序 (`always @(posedge clk)`)

**跨时钟域**
- DebugController+UART @100MHz, CPU @12.5MHz
- IMem sync: posedge clk
- DMem sync: negedge clk (错半拍改善时序)
- MEM_WAIT_CYCLES = 20 (保证 Debug 信号被 12.5MHz 域稳定采样)
- STEP_COUNTDOWN_INIT = 8 (100MHz/12.5MHz = 8 cycles per CPU step)

**MMIO 地址映射**
- 0xFFFF0000: 开关 (16-bit, 只读)
- 0xFFFF0004: 按键 (5-bit, 只读)
- 0xFFFF0008: LED (16-bit, 读/写)
- 0xFFFF000C: 数码管位选 (8-bit, 读/写)
- 0xFFFF0010: 数码管段选0 (8-bit, 读/写)
- 0xFFFF0014: 数码管段选1 (8-bit, 读/写)

---

## 4. 已修复的 Bug (共 10 个)

| # | 问题 | 修复 | 文件 |
|---|------|------|------|
| 1 | JAL/JALR 把 ALUResult 写回 rd, 应写 PC+4 | 新增 JALWDSrc, WD3 三选一 | CPUTop.v |
| 2 | `{(rs1+Imm)[31:1],1'b0}` 语法错误 | 拆为中间 wire jalr_sum | CPUTop.v |
| 3 | 内存 16KB 太小, 0x4000 可能越界 | 扩容至 64KB, [15:2] | Ifetch.v, DataMemory.v |
| 4 | EGO1 端口宽度不匹配 (32→16/5/8) | SwitchIn/ButtonIn/LEDOut/7-seg 修正 | TopDebug/CPUTop/DataMemory |
| 5 | Ifetch Next-PC 使用未声明信号 Branch | 改为直接使用 PCSrc | Ifetch.v |
| 6 | RegFile integer i 在 always 内声明 | 移到模块级 | RegFile.v |
| 7 | JALRTarget part-select 不支持 | 中间 wire jalr_sum | CPUTop.v |
| 8 | Difftest PC=0x4000 vs CPU PC=0x0000 | PC_RESET=0x4000, hex 偏移 4096 | Ifetch.v |
| 9 | BRAM 寄存器读导致单周期失效 | IMem 改为组合读, 去除 mem_dout | Ifetch.v |
| 10 | 25MHz 组合读路径时序不收敛, 后18组超时 | CPU 降频至 12.5MHz (100MHz/8) | TopDebug.v |

---

## 5. 测试结果

**Difftest 上板验证: 33/33 PASS ✅** (2026-05-18)

| Case | 测试组数 | RARS | Difftest | 验证人 |
|------|---------|------|---------|--------|
| 0 (AND) | 2 | PASS | PASS | 刘一骏(RARS) / 陈俊希(Difftest) |
| 1 (SLL) | 2 | — | PASS | 陈俊希 |
| 2 (SRA) | 2 | — | PASS | 陈俊希 |
| 3 (LUI+ADD) | 2 | — | PASS | 陈俊希 |
| 4 (JAL+AUIPC) | 2 | PASS | PASS | 刘一骏 / 陈俊希 |
| 5 (JAL+JALR) | 2 | — | PASS | 陈俊希 |
| 6 (Fibonacci) | 4 | PASS | PASS | 刘一骏 / 陈俊希 |
| 7 (Popcount) | 2 | — | PASS | 陈俊希 |
| 8 (IEEE754) | 9 | PASS | PASS | 刘一骏 / 陈俊希 |
| 9 (Q3.4量化) | 6 | PASS | PASS | 刘一骏 / 陈俊希 |

所有 33 组测试数据全部通过, 详见 3_test_results.md。

---

## 6. 当前状态 & 下一步

### 已完成 ✅
- 11 个 Verilog 文件全部编写 + 审查 + 注释补充
- batch_test.asm (390行, 10 Case) + batch_test.hex (130条)
- ego1.xdc EGO1 完整引脚约束
- create_project.tcl Vivado 一键建工程脚本
- RARS 模拟验证 21/21 PASS
- **Difftest 上板验证 33/33 PASS**
- **全部 10 个 Bug 修复 (含 2 个上板后发现)**
- 代码注释全覆盖
- project_log 协作文件整理

### 待执行 ❌

| 步骤 | 负责人 | 操作 |
|------|--------|------|
| 1 | 范晓乐 | 项目文档 PDF (提纲见 1_report.md) |
| 2 | 全员 | 视频 MP4 (全员出镜 + 2 复杂 Case 演示) |
| 3 | 范晓乐 | gitlog.txt + 打包 + 上传 BB |

### 提交文件命名
- 文件夹: `c_rv_FanXiaole_ChenJunxi_LiuYijun`
- 文档 PDF: `d_rv_FanXiaole_ChenJunxi_LiuYijun.pdf`
- 视频 MP4: `v_rv_FanXiaole_ChenJunxi_LiuYijun.mp4`

---

## 7. 检查清单

- [x] batch_test.asm 第 50 行 = `lui s0, 0x4` (硬件/difftest 模式, **不是** 0x1)
- [x] batch_test.hex 首行 = `00004437` (验证为 `lui s0, 0x4`)
- [x] ego1.xdc 端口名与 TopDebug.v 一致
- [x] Ifetch.v PC_RESET = 32'h00004000
- [x] Ifetch.v HEX_LOAD_OFFSET = PC_RESET >> 2
- [x] Vivado 2017.4 版本确认
- [x] No Vivado IP cores
- [x] $readmemh 初始化 IMem
- [x] Difftest 33/33 PASS
- [x] IMem 组合读 (单周期正确)
- [x] CPU 12.5MHz (100MHz/8, 时序收敛)

---

## 8. Bonus 规划 (基础 PASS, 可启动)

**推荐: VGA 文本显示 [5分] + 贪吃蛇游戏 [5分] = 10 分满分**

- EGO1 已有 VGA 接口 (vga_hs/vga_vs/vga_data[11:0])
- 80×30 文本模式 ~4.5KB BRAM
- 贪吃蛇纯 RISC-V 汇编, 按键操控
- 两周内可完成 (~200行 Verilog + ~300行 汇编)

# 现场设计备考指南 — 5 分

> **⚠️ 第 15 周实验课 · 断网 · Vivado 2017.4 · 严禁手机/个人电脑 · 目标 10 分钟完成 Verilog 修改**
> **基于单周期 CPU (SwitchIn[15]=0 默认模式) · 考试只需改 Decoder/ALU/CPUTop/Ifetch 四个文件**
> **验证方式: difftest 工具 (优先) 或开发板外设 · 汇编采用 "占位符法"**

---

## 🚨 考前准备 (断网前必须完成!!!)

### 第 1 步: 从 GitHub 拉取项目代码到 D 盘

**所有资料和工具务必保存在 D 盘！** C 盘可能被系统异常重启清空。

打开终端 (cmd 或 PowerShell)，逐条执行:

```bash
# 1. 切换到 D 盘
D:

# 2. 创建考试专用文件夹
mkdir exam_cpu

# 3. 进入文件夹
cd exam_cpu

# 4. 从 GitHub 克隆项目 (换成你们组的仓库地址!)
git clone https://github.com/CS202ComputerOrganization/cpu-project-12412307-12411025-12411922.git

# 5. 进入项目目录
cd cpu-project-12412307-12411025-12411922

# 6. 确认分支和最新提交
git branch
git log --oneline -3
```

> **💡 如果电脑上已经 clone 过:** 直接 `cd` 到项目目录，执行 `git pull origin main` 拉取最新版本即可。

### 第 2 步: 下载其他必要资料到 D 盘

| 必须下载 | 获取方式 | 说明 |
|----------|---------|------|
| ✅ 项目代码 | `git clone` (上一步) | 你们的 CPU 项目仓库 |
| ✅ Rars / Lars | BB / 邮箱 / 官网 | RISC-V 汇编器，生成机器码 |
| ✅ difftest 工具 | BB / 邮箱 | 串口比对测试工具 |
| ✅ Inclass_Guide.md | 项目里自带 | 就是本指南，断网后离线看 |
| ✅ 电子资料 | 提前存到 D 盘 | 课件、笔记、开发板说明书 |

### 第 3 步: 工具链验证 (务必在断网前完成!)

```text
1. 双击 Vivado 2017.4 → 打开 D:\exam_cpu\... 下的 cpu_project.xpr
2. Run Synthesis → Run Implementation → Generate Bitstream
   → 确认能通过，无 Error!
3. Hardware Manager → Open Target → Auto Connect
4. Program Device → 选 TopDebug.bit → DONE 灯亮
5. 打开 difftest 工具 → 跑一次完整测试
   → 确认串口连接正常、比对结果 PASS
6. 打开 Rars/Lars → 打开任意 .asm 文件 → Assemble
   → 确认能正常生成机器码
```

> **⚠️ 工具链不通 = 考试白给。趁有网赶紧排查！Vivado 打不开通常是路径含中文。**

### 第 4 步: 确认文件结构 (对着这张表检查)

```text
D:\exam_cpu\cpu-project-...\
├── cpu_project.xpr              ← Vivado 工程文件
├── cpu_project.srcs/
│   └── sources_1/
│       └── new/
│           ├── Decoder.v         ← 要改! INCLASS_MAIN
│           ├── ALU.v             ← 要改! INCLASS_ALU
│           ├── CPUTop.v          ← 按需改 INCLASS_MUX_A/WD3
│           ├── Ifetch.v          ← 按需改 INCLASS_HEX
│           ├── batch_test.txt    ← 写测试机器码
│           └── ... (其他文件不要动)
├── assembly/
│   ├── batch_test.asm            ← 汇编源文件参考
│   └── batch_test.txt            ← 汇编生成的 txt 参考
└── Inclass_Guide.md              ← 本指南 (离线看)
```

## 考场纪律速览

| 要求 | 详情 |
|------|------|
| 到场 | 全员提前到场，迟到超 5 分钟 = 缺考 = 0 分 |
| 桌面 | 只放学生卡 + EGO1 开发板 |
| 电子设备 | 手机/U盘等放书包，书包放讲台 |
| 讨论 | 组内可小声讨论，勿影响其他组 |
| 课间 | 不休息，去厕所 = 放弃后续考试 |
| 验收流程 | 登记小组编号 → 回座位等验收(勿在讲台逗留) → disconnect_hw_server → 清空D盘+回收站 → 签名 → 带板离开 |

---

## 🔴 速查卡 —— 打印携带，考试直接看这一页

## ⭐ 汇编占位符速查 (新方法!)

**为什么用占位符？** Rars 不认识你的新指令，会报错。用同格式的已知指令代替，生成 txt 后再手工替换机器码。

| 新指令格式 | 占位指令 (Rars 能汇编) | 替换目标 |
|-----------|----------------------|----------|
| R-type (rd, rs1, rs2) | `add s0, a0, a1` | 教师给的机器码 |
| I-type (rd, rs1, imm) | `addi s0, a0, 0` | 教师给的机器码 |
| U-type (rd, imm) | `lui s0, 0x12345` | 教师给的机器码 |
| Branch (rs1, rs2, label) | `beq a0, a1, label` | 教师给的机器码 |
| Jump (rd, label) | `jal s0, label` | 教师给的机器码 |

**测试汇编模板 (直接抄，改占位符那行):**

```asm
    lw t0, 0x4000(x0)   # 用例编号 (教师指定)
    lw t1, 0x4004(x0)   # 源操作数 1
    lw t2, 0x4008(x0)   # 源操作数 2
    add s0, t1, t2      # ← 占位符! 把这行替换成教师的机器码
    sw s0, 0x400C(x0)   # 存结果，供 difftest 比对
```

> **关键:** 0x4000=用例编号, 0x4004/0x4008=源操作数, 0x400C=结果。格式固定！

## 指令类型 → 我需要改哪些文件？

| 教师出的类型 | ALU.v | Decoder.v (主) | Decoder.v (ALU表) | CPUTop.v | 参考 |
|-------------|-------|---------------|-------------------|----------|------|
| R-type 新运算 (最常见!) | ✅ 新运算 | ✅ 新 opcode | ✅ funct3 表 | ❌ | AND/SLL |
| I-type 新运算 | ✅ 新运算 | ✅ 新 opcode | ✅ funct3 表 | ❌ | ADDI/ANDI |
| U-type 新指令 (如 LUI 变体) | ❌ | ✅ 新 opcode | ❌ | ❌ | LUI |
| B-type 新分支 | ❌ | ✅ 新 opcode | ❌ | ❌ | BEQ |
| J-type 新跳转 | ❌ | ✅ 新 opcode | ❌ | ❌ | JAL |
| Load/Store 变体 | ❌ | ✅ 新 opcode | ❌ | ❌ | LW/SW |
| 需要新数据通路 | ? | ✅ 新 opcode | ? | ✅ 加 MUX | — |

**> 铁律：Decoder.v 主译码器一定要改，其余看指令类型。**

## 控制信号一秒查

| 信号 | =1 什么意思 | =0 什么意思 |
|------|-----------|-----------|
| RegWrite | **写**寄存器 | 不写 |
| ALUSrc | ALU_B = **立即数** | ALU_B = **rs2** |
| MemtoReg | WD3 = **内存值** (Load) | WD3 = ALU结果 |
| MemWrite | **写**内存 (Store) | 不写 |
| Branch | 条件分支 (B-type) | 不是分支 |
| Jump | **JAL** 跳转 | 不是 JAL |
| JALRSrc | **JALR** 跳转 | 不是 JALR |
| ALUOp=00 | 强制 ADD | — |
| ALUOp=01 | 强制 SUB (分支比较用) | — |
| ALUOp=10 | **R-type** (查 funct3+funct7) | — |
| ALUOp=11 | **I-type ALU** (查 funct3) | — |

## 四个文件的改哪里 (Ctrl+F 搜关键字)

| 文件 | 搜什么 | 行号 | 改什么 |
|------|--------|------|--------|
| **Decoder.v** | `INCLASS_MAIN` | ~232 | 加 7'b 新 opcode 分支 |
| **Decoder.v** | `INCLASS_ALU_R` | ~276 | R-type 加 funct3 行 |
| **Decoder.v** | `INCLASS_ALU_I` | ~293 | I-type 加 funct3 行 |
| **ALU.v** | `INCLASS_ALU` | ~110 | 加 4'b 新运算 case |
| CPUTop.v | `INCLASS_MUX_A` | ~218 | 加 ALU_A 来源 (按需!) |
| CPUTop.v | `INCLASS_MUX_WD3` | ~278 | 加 WD3 来源 (按需!) |
| Ifetch.v | `INCLASS_HEX` | ~51 | 临时换 txt (按需!) |

## 🚫 绝对不要动的文件 (改了可能导致综合失败或扣分)

**VGA.v, CPUTopPipeline.v, PipeRegs.v, HazardUnit.v, Ifetch_Pipe.v, RegFile_Pipe.v, DataMemory.v, DebugController.v, UartRx.v, UartTx.v**
— 这些都是 Bonus 模块或调试模块，与基础分数无关。

---

## 标准操作流程 (照着一步步做)

## 步骤 1: 接收题目 → 填表 (30 秒)

教师给什么就填什么：

| 参数 | 值 |
|------|-----|
| 指令名 | ___________ |
| 功能 (一句话) | ___________ |
| 指令格式: R / I / S / B / U / J ? | ___________ |
| opcode[6:0] | ___________ |
| funct3[2:0] (如有) | ___________ |
| funct7[6:0] (如有) | ___________ |
| 测试机器码 (32-bit hex) | ___________ |
| 测试用例 | 0, [src1, src2], expect=___________ |

## 步骤 2: 编写测试汇编 (占位符法) ⭐

**用 Rars/Lars 写 `.asm` 文件:**

```asm
    # 固定格式: lw 从 0x4000/4004/4008 读, sw 到 0x400C 写结果
    lw  t0, 0x4000(x0)   # 用例编号
    lw  t1, 0x4004(x0)   # 源操作数1
    lw  t2, 0x4008(x0)   # 源操作数2
    add s0, t1, t2       # ← 占位符! 选同格式指令 (R=R/I=I)
    sw  s0, 0x400C(x0)   # 存结果
```

**占位指令速查:**

| 新指令格式 | 用这个占位 |
|-----------|----------|
| R-type: rd = rs1 op rs2 | `add s0, a0, a1` |
| I-type: rd = rs1 op imm | `addi s0, a0, 0` |
| U-type: rd = imm << 12 | `lui s0, 0x12345` |
| Branch | `beq a0, a1, label` |
| Jump | `jal s0, label` |

**操作:** Rars → Assemble → 得到 `.txt` 机器码 → **找到占位符那行的 hex，替换成教师给的机器码。**

## 步骤 3: 改 Decoder.v — 主译码器 ⭐ (必改!)

**打开文件:** `cpu_project/cpu_project.srcs/sources_1/new/Decoder.v`

**定位:** Ctrl+F 搜 `INCLASS_MAIN` (约第 232 行)

**你在代码中会看到:**
```verilog
            // ===== INCLASS_MAIN: 现场设计 — 新opcode分支插在此注释上方 =====
            // 模板 (复制上方类似指令格式修改):
            // 7'bXXXXXXX: begin ... end
            // ALUOp速查: 00=强制ADD  01=强制SUB  10=R-type  11=I-type-ALU
            default: begin
                regwrite_r = 1'b0; ...
```

**把下面模板插入到 INCLASS_MAIN 注释行的上方 (即 default 之前):**
```verilog
            7'bXXXXXXX: begin  // ← 改成教师给的 opcode
                regwrite_r = 1'bX;  // ← 写出到 rd? 1=是 0=否
                alusrc_r   = 1'bX;  // ← ALU_B 用立即数? 0=rs2 1=imm
                memtoreg_r = 1'b0;  // ← 从内存读? (只有 Load 才=1)
                memwrite_r = 1'b0;  // ← 写内存? (只有 Store 才=1)
                branch_r   = 1'b0;  // ← 条件分支? (只有 B-type 才=1)
                jump_r     = 1'b0;  // ← JAL 跳转? (只有 JAL 才=1)
                jalrsrc_r  = 1'b0;  // ← JALR 跳转? (只有 JALR 才=1)
                aluop_r    = 2'bXX; // ← 00=ADD 01=SUB 10=R-type 11=I-type
            end
```

**抄哪个现成模板 (在代码里找到对应 opcode 行，直接复制它的控制信号值):**

| 如果你的指令像... | 抄代码里这个 opcode 行 | 关键信号值 |
|-----------------|---------------------|-----------|
| ADD/SUB/AND 等 R-type | `7'b0110011` | RegWrite=1, ALUSrc=0, ALUOp=**10** |
| ADDI/ANDI 等 I-type | `7'b0010011` | RegWrite=1, ALUSrc=1, ALUOp=**11** |
| LW (Load) | `7'b0000011` | RegWrite=1, ALUSrc=1, MemtoReg=1, ALUOp=**00** |
| SW (Store) | `7'b0100011` | RegWrite=0, ALUSrc=1, MemWrite=1, ALUOp=**00** |
| BEQ 等 Branch | `7'b1100011` | RegWrite=0, ALUSrc=0, Branch=1, ALUOp=**01** |
| JAL | `7'b1101111` | RegWrite=1, Jump=1, ALUOp=**00** |
| JALR | `7'b1100111` | RegWrite=1, JALRSrc=1, ALUOp=**00** |
| LUI | `7'b0110111` | RegWrite=1, ALUSrc=1, ALUOp=**00** |

## 步骤 4: 改 Decoder.v — ALU 译码表 (如需新运算)

**仅当你的指令需要 ALU 做新运算时才改。** Load/Store/Branch/Jump 类不需要。

**R-type 新运算:** Ctrl+F 搜 `INCLASS_ALU_R` (约第 276 行)

把模板插入:
```verilog
                // 把下面这行加在 INCLASS_ALU_R 注释下方
                3'bXXX: alucontrol_r = funct7_5 ? 4'b新编码 : 4'b旧编码;
                // 如果不需要 funct7_5 区分, 直接写:
                3'bXXX: alucontrol_r = 4'bYYYY;
```

**I-type 新运算:** Ctrl+F 搜 `INCLASS_ALU_I` (约第 293 行)

```verilog
                3'bXXX: alucontrol_r = 4'bYYYY;  // 新运算编码
```

**可选 ALUControl 编码 (选一个没用过的):** 已占用 `0000`~`1100`, 可用: **`1101`, `1110`, `1111`**

**💡 提示:** 如果你只加了一条新指令且它需要新运算，建议用 `1101` (最容易记)。

## 步骤 5: 改 ALU.v — 新运算实现 (如需)

**打开文件:** `cpu_project/cpu_project.srcs/sources_1/new/ALU.v`

**定位:** Ctrl+F 搜 `INCLASS_ALU` (约第 110 行)

**你在代码中会看到:**
```verilog
            // ===== INCLASS_ALU: 现场设计 — 新ALU运算插在此注释下方 =====
            // ===== ISA 扩展: 硬件加速指令 (funct7=0000001) =====
            4'b1010: ALUResult = popcount(A);   // ← 这就是现有自定义运算的写法
            4'b1011: ALUResult = clz(A);
            4'b1100: ALUResult = ctz(A);
            default: ALUResult = 32'd0;
```

**在 INCLASS_ALU 注释下方插入 (推荐插在 4'b1100 之后, default 之前):**
```verilog
            4'b1101: ALUResult = /* 你的运算表达式 */;
```

**常用 Verilog 运算表达式 (直接抄):**
```verilog
A + B                          // 加法
A - B                          // 减法
A & B                          // 按位与
A | B                          // 按位或
A ^ B                          // 按位异或
A << B[4:0]                    // 逻辑左移 (只移低5位)
A >> B[4:0]                    // 逻辑右移
$signed(A) >>> B[4:0]          // 算术右移 (保留符号)
($signed(A) < $signed(B)) ? 32'd1 : 32'd0   // 有符号比较
(A < B) ? 32'd1 : 32'd0       // 无符号比较
~A                             // 按位取反 (NOT)
32'd0 - A                      // 取负数 (补码)
(A + B) >> 1                   // 平均数 (防溢出)
(A < B) ? A : B                // 取最小值
(A < B) ? B : A                // 取最大值
{16'd0, A[15:0]}               // 零扩展低 16 位
{{16{A[15]}}, A[15:0]}         // 符号扩展低 16 位
A[7:0] * B[7:0]                // 8-bit 乘法 (注意: 别用 * 做全 32-bit, 扣分!)
```

## 步骤 6: 改 CPUTop.v (仅特殊情况!)

**⚠️ 大多数指令不需要改 CPUTop！** 只有下面两种情况才需要:

- **情况 A:** 新指令的 ALU_A 来源不是 rs1_val (像 LUI 需要 A=0, AUIPC 需要 A=PC)
- **情况 B:** 新指令的写回数据 WD3 来源不是 ALUResult (像 JAL/JALR 需要写 PC+4, Load 需要写内存值)

**如果需要改 ALU_A MUX:** Ctrl+F 搜 `INCLASS_MUX_A` (约第 218 行)

```verilog
    wire isNEW = (inst[6:0] == 7'bXXXXXXX);  // ← 你的 opcode
    assign ALU_A = isLUI   ? 32'd0   :
                   isAUIPC ? PC      :
                   isNEW   ? 新的来源 :  // ← 改成你的 ALU_A 来源
                             rs1_val;
```

**如果需要改 WD3 MUX:** Ctrl+F 搜 `INCLASS_MUX_WD3` (约第 278 行)

```verilog
    wire isNEW_WD3 = (inst[6:0] == 7'bXXXXXXX);
    assign WD3 = JALWDSrc  ? PCPlus4 :
                 isNEW_WD3 ? 新的来源 :  // ← 改成你的 WD3 来源
                 MemtoReg  ? ReadData : ALUResult;
```

## 步骤 7: 注入测试机器码到 batch_test.txt ⭐

**文件:** `cpu_project/cpu_project.srcs/sources_1/new/batch_test.txt`

**重要:** 第 1 行 → PC=0x4000, 第 2 行 → PC=0x4004, 以此类推。

### 标准测试格式 (配合 difftest / 开发板外设)

从步骤 2 生成的 txt 文件中取机器码（已替换占位符），**写在 batch_test.txt 最开头**:

```
XXXXXXXX    ← lw t0, 0x4000(x0) 的机器码
XXXXXXXX    ← lw t1, 0x4004(x0) 的机器码
XXXXXXXX    ← lw t2, 0x4008(x0) 的机器码
XXXXXXXX    ← ★ 教师给的新指令机器码 (替换了占位符那行)
XXXXXXXX    ← sw s0, 0x400C(x0) 的机器码
```

> **⚠️ 注意:** 不需要删除 txt 中原有的 batch_test 内容——CPU 执行完你的测试段后会执行 sw 写 0x400C，后面的代码无所谓。但**确保你的测试代码在文件最开头**。

### 如果不想改 batch_test.txt (备选方案)

- Ctrl+F 搜 `INCLASS_HEX` (Ifetch.v 约第 51 行)
- 把 `INIT_FILE = "batch_test.txt"` 临时改成你的文件名

## 步骤 8: Vivado 综合 + 实现 (~18 分钟, 开始后不能停)

```
1. 双击 Vivado 2017.4 桌面图标
2. File → Open Project → 找到 cpu_project.xpr → OK
3. 左侧 Flow Navigator → Run Synthesis → OK
   ⏳ 等待 ~5 分钟 (看 Tcl Console 滚动)
4. 弹出对话框 → Run Implementation → OK
   ⏳ 等待 ~10 分钟
5. 弹出对话框 → Generate Bitstream → OK
   ⏳ 等待 ~3 分钟
6. 确认 Tcl Console 最后一行无红色 "Error"
7. Hardware Manager → Open Target → Auto Connect
8. 右键 xc7a35t_0 → Program Device → 选 TopDebug.bit → OK
9. 等待 DONE 灯亮
```

> **⚠️ 如果综合报错:** 不要慌。看 Tcl Console 红色行，通常是拼写错误或少写了分号。最常见: `undeclared identifier` = 变量名写错, `syntax error` = 少了分号或 begin/end 不匹配。修复后从步骤 3 重新开始。

## 步骤 9: 上板验证 (1-2 分钟)

### 方法 A: difftest 工具 (推荐!)

1. EGO1 上电 (Micro-USB 连接学生机)
2. **确认 SwitchIn[15] 拨下** (单周期模式!)
3. 打开 difftest 工具 → 确认串口已连接
4. 运行测试 → difftest 自动加载 0x4000/0x4004/0x4008 的源操作数，执行你的指令，比对 0x400C 的结果
5. **difftest 显示 PASS → 立刻举手请老师/助教来验证!**

### 方法 B: 开发板外设 (不支持 difftest 时)

1. EGO1 上电，SwitchIn[15] 拨下
2. 通过拨码开关/按钮输入源操作数
3. 观察 LED[7:0] → 应等于预期结果低 8 位
4. **LED 显示符合预期 → 立刻举手请老师/助教来验证!**

### 如果结果不对

- 检查测试机器码是否写对 (32-bit hex, 每行 8 位)
- 检查 Decoder 主译码器的 opcode 是否和教师给的一致
- 检查控制信号是否抄对了现成模板
- 如果 ALUOp=10 或 11, 确认 ALU 译码表中 funct3 那行写对了
- difftest 失败: 检查 0x4000/0x4004/0x4008 的 lw 和 0x400C 的 sw 是否正确

## 步骤 10: 验收与离场 (别忘了!)

1. **登记:** 一名组员到讲台登记小组编号
2. **等验收:** 立刻回到座位，不要在讲台或他人电脑前逗留
3. **断开:** 监考人员验收后，在 Vivado Tcl Console 中输入 `disconnect_hw_server`
4. **清空:** 清空 D 盘和回收站
5. **签名:** 确认成绩登记，全体成员签名
6. **带走:** EGO1 开发板原样带走保存，后续会统一回收

---

## 📋 最终检查清单 (综合前逐条打勾)

### 代码修改

- [ ] 参数表已填好 (opcode/funct3/funct7/机器码/预期结果)
- [ ] Decoder.v: INCLASS_MAIN 上方加了新 opcode 分支
- [ ] Decoder.v: 控制信号值抄对了现成模板 (RegWrite/ALUSrc/ALUOp 等)
- [ ] Decoder.v: INCLASS_ALU_R 或 _I 中加了 funct3 行 (如需)
- [ ] ALU.v: INCLASS_ALU 下方加了新 case (如需)
- [ ] CPUTop.v: MUX 已更新 (如需, 大多数不需要)

### 测试机器码

- [ ] Rars/Lars 汇编 `.asm` → 生成 `.txt`
- [ ] 占位符那行已替换成教师给的机器码
- [ ] batch_test.txt: 测试代码写在文件开头
- [ ] batch_test.txt: 包含 lw(0x4000), lw(0x4004), lw(0x4008), 新指令, sw(0x400C)

### Vivado 流程

- [ ] Run Synthesis → 无 Error
- [ ] Run Implementation → 无 Error
- [ ] Generate Bitstream → 成功

### 上板验证

- [ ] Program Device 成功, DONE 灯亮
- [ ] SwitchIn[15]=0 (单周期模式)
- [ ] difftest: 测试用例 PASS (或 LED 显示符合预期)
- [ ] 🙋 举手请老师/助教现场验证!

### 验收离场

- [ ] 一名组员到讲台登记小组编号 (其他人回座位等)
- [ ] 验收通过后 Tcl Console 执行 `disconnect_hw_server`
- [ ] 清空 D 盘和回收站
- [ ] 全体签名确认成绩
- [ ] EGO1 开发板带走保存

---

## 🆘 紧急情况速查

| 问题 | 最可能的原因 | 立即检查 |
|------|------------|---------|
| Synthesis 报 `syntax error` | 少了分号或括号不匹配 | 检查刚插入的代码行末是否有 `;` |
| Synthesis 报 `undeclared` | 变量名写错 | 检查 regwrite_r 等是否拼写正确 |
| Synthesis 报 `multiple drivers` | 同一信号在两个 always 里赋值 | 检查是否把代码插到了错误的位置 |
| Bitstream 生成成功但结果为 0 | ALUOp 设错了, ALU 没执行你的运算 | 检查 ALUOp 值是否匹配指令格式 |
| 结果的值差了一点 | ALU 运算表达式写错了 | 检查 ALU.v 中 case 分支的表达式 |
| difftest 连接失败 | 串口未连接或端口被占用 | 检查串口线, 重启 difftest 工具 |
| difftest 显示 MISMATCH | 机器码替换错误或控制信号不对 | 对比 Rars 生成的 txt 和教师给的机器码 |
| Vivado 打不开 .xpr | 工程路径含中文 | 把整个文件夹移到纯英文路径 |
| 综合到一半崩溃 | 路径含中文或空格 | 同上 |
| 系统重启后文件丢失 | 文件保存在了 C 盘 | **务必放 D 盘!** 立刻检查文件位置 |

---

## 📝 完整案例参考 (考试对照着做!)

> **题型: R-type 新运算，和已有指令共用 opcode+funct3，靠 funct7 区分**
> 这是最常见也最简单的题型，只改 **2 行代码**。

### 案例题目

**新指令 `NAND rd, rs1, rs2`** — 按位与非

- 功能: `rd = ~(rs1 & rs2)`
- 格式: R-type
- opcode: `7'b0110011` (R-type 通用 opcode，不改)
- funct3: `3'b111` (和 AND 共用)
- funct7: `7'b0100000` (用 funct7[5]=1 区分 AND 的 funct7=0000000)
- 测试用例: `0, [0xFF, 0x0F], expect=0xFFFFFFF0`

### ① 填表

| 参数 | 值 |
|------|-----|
| 指令名 | NAND |
| 功能 | rd = ~(rs1 & rs2) |
| 指令格式 | R-type |
| opcode[6:0] | `7'b0110011` |
| funct3[2:0] | `3'b111` |
| funct7[6:0] | `7'b0100000` |
| 测试机器码 (NAND x3,x1,x2) | `0x4020F1B3` |
| 测试用例 | 0, [0xFF, 0x0F], expect=0xFFFFFFF0 |

### ② 汇编占位符

```asm
    lw  t0, 0x4000(x0)   # 用例编号
    lw  t1, 0x4004(x0)   # 源操作数1
    lw  t2, 0x4008(x0)   # 源操作数2
    add s0, t1, t2       # ← 占位符! R-type用add代替
    sw  s0, 0x400C(x0)   # 存结果
```

Rars 汇编 → 生成 txt → 把 `add s0, t1, t2` 那行的 hex 替换成 `4020F1B3`。

### ③ Decoder.v — 主译码器 (INCLASS_MAIN)

**不需要改！** 因为 opcode 还是 `7'b0110011`（R-type），现有分支已经覆盖。控制信号自动正确: RegWrite=1, ALUSrc=0, ALUOp=`10`。

> **什么时候主译码器要改？** 当教师给了一个全新的 opcode（不是 0110011/0010011/0000011 等现有 9 个），才需要在 INCLASS_MAIN 加分支。

### ④ Decoder.v — ALU 译码表 (搜 INCLASS_ALU_R, ~287 行)

原代码:

```verilog
                    3'b111: alucontrol_r = 4'b0010; // AND
```

改成:

```verilog
                    3'b111: alucontrol_r = funct7_5 ? 4'b1101 : 4'b0010; // NAND : AND
```

> **原理:** funct7[5]=0 → 走 AND(`0010`). funct7[5]=1 → 走 NAND(`1101`). 和 ADD/SUB 共用 funct3=000 的模式一模一样。

### ⑤ ALU.v (搜 INCLASS_ALU, ~117 行)

在 `4'b1100` 和 `default` 之间插入:

```verilog
            4'b1101: ALUResult = ~(A & B);  // NAND
```

### ⑥ batch_test.txt (前 5 行)

```text
XXXXXXXX    ← lw t0, 0x4000(x0)   Rars生成
XXXXXXXX    ← lw t1, 0x4004(x0)   Rars生成
XXXXXXXX    ← lw t2, 0x4008(x0)   Rars生成
4020F1B3    ← ★ NAND x3,x1,x2    (替换占位符)
XXXXXXXX    ← sw s0, 0x400C(x0)   Rars生成
```

### ⑦ 手算机器码 (R-type)

```text
funct7 | rs2 | rs1 | funct3 | rd | opcode
0100000 00010 00001   111   00011 0110011

0100 0000 0010 0000 1111 0001 1011 0011
 4    0    2    0    F    1    B    3
→ 0x4020F1B3
```

> 验证: 0xFF & 0x0F = 0x0F → ~0x0F = 0xFFFFFFF0 ✅

### ⑧ 改动总结

| 文件 | 改什么 | 几行 |
|------|--------|------|
| Decoder.v 主译码器 | ❌ 不改 | 0 |
| Decoder.v ALU 表 | funct3=111 加 funct7_5 判断 | 1 |
| ALU.v | 加 4'b1101 case | 1 |
| CPUTop.v | ❌ 不改 | 0 |
| batch_test.txt | 写测试代码 | 5 |

---

## 🏋️ 更多练习 (考前自测)

- **练习 A:** `AVG rd, rs1, rs2` — 求平均 (A+B)/2, R-type, opcode=0110011, funct3=000, funct7=0000001
- **练习 B:** `NEGI rd, rs1, imm` — 立即数取负, I-type, opcode=0010011, funct3=001
- **练习 C:** LUI 功能但 opcode 改成 `7'b1110111` — 需要改 CPUTop.v 的 ALU_A mux!

# 现场设计备考指南 — 5 分

> **⚠️ 15 周实验课 · 断网 · Vivado 2017.4 · 严禁手机/个人电脑 · 目标 10 分钟完成**
> **基于单周期 CPU (SwitchIn[15]=0 默认模式) · 考试只需改 Decoder/ALU/CPUTop/Ifetch 四个文件**

---

# 🔴 速查卡 —— 打印携带，考试直接看这一页

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

# 标准操作流程 (照着一步步做)

## 步骤 1: 接收指令 → 填表 (30 秒)

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
| 预期结果 (LED 低 8 位) | ___________ |

## 步骤 2: 改 Decoder.v — 主译码器 ⭐ (必改!)

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

## 步骤 3: 改 Decoder.v — ALU 译码表 (如需新运算)

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

## 步骤 4: 改 ALU.v — 新运算实现 (如需)

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

## 步骤 5: 改 CPUTop.v (仅特殊情况!)

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

## 步骤 6: 注入测试机器码 ⭐

### 方法 A: 直接改 batch_test.txt (强烈推荐! 最快最稳)

**文件:** `cpu_project/cpu_project.srcs/sources_1/new/batch_test.txt`

**重要:** 这个 txt 文件是 Ifetch.v 用 `$readmemh` 加载的指令内存初始内容。**第 1 行 → PC=0x4000, 第 2 行 → PC=0x4004, 以此类推。**

把你从教师那里拿到的 32-bit 机器码写在文件**最开头**，然后接一条 `sw` 指令把结果写到 LED:

```
XXXXXXXX                               ← 教师给的测试机器码 (PC=0x4000)
0FF00FA3                               ← sw x_result, 0xFFFF0008(x0) 的机器码
```

> **💡 如果你不会手算 sw 指令的机器码:**
> 把结果寄存器的值先 `addi t1, 结果寄存器, 0` 复制到 t1，然后用:
> ```
> 00602023    ← 这是 sw t1, 0xFFFF0008(x0) 的机器码
> ```
> 这条指令把 t1 的值写到 LED 地址 0xFFFF0008，你就能在 LED[7:0] 看到结果低 8 位。

### 方法 B: 如果教师给了多条测试机器码

按顺序写在文件开头即可:
```
XXXXXXXX    ← 测试指令 1 (PC=0x4000)
XXXXXXXX    ← 测试指令 2 (PC=0x4004)
XXXXXXXX    ← 测试指令 3 (PC=0x4008)
XXXXXXXX    ← sw 结果到 LED   (PC=0x400C)
```

> **⚠️ 注意:** 只要把测试指令写在 txt 开头，CPU 上电复位 (PC=0x4000) 后就会从第一条测试指令开始执行。**不需要删除 txt 文件中原有的 batch_test 内容**——CPU 执行完你的指令后会执行 sw 写 LED，然后后面的代码无所谓。

### 方法 C: 备选 — 临时换个 txt 文件

如果不想改 batch_test.txt，可以临时让 Ifetch.v 加载另一个文件:
- Ctrl+F 搜 `INCLASS_HEX` (约第 51 行)
- 把 `INIT_FILE = "batch_test.txt"` 临时改成你的文件名

## 步骤 7: Vivado 操作 (~18 分钟, 开始后不能停)

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

## 步骤 8: 上板验证 (1 分钟)

1. EGO1 上电 (Micro-USB 连接学生机)
2. **确认 SwitchIn[15] 拨下** (单周期模式!)
3. 观察 LED[7:0] → 应等于你的预期结果
4. **LED 显示符合预期 → 立刻举手请老师/助教来验证!**

如果 LED 显示不对:
- 检查测试机器码是否写对 (32-bit hex, 每行 8 位)
- 检查 Decoder 主译码器的 opcode 是否和教师给的一致
- 检查控制信号是否抄对了现成模板
- 如果 ALUOp=10 或 11, 确认 ALU 译码表中 funct3 那行写对了

---

# 📋 最终检查清单 (综合前逐条打勾)

- [ ] 参数表已填好 (opcode/funct3/funct7/机器码/预期结果)
- [ ] Decoder.v: INCLASS_MAIN 上方加了新 opcode 分支
- [ ] Decoder.v: 控制信号值抄对了现成模板 (RegWrite/ALUSrc/ALUOp 等)
- [ ] Decoder.v: INCLASS_ALU_R 或 _I 中加了 funct3 行 (如需)
- [ ] ALU.v: INCLASS_ALU 下方加了新 case (如需)
- [ ] CPUTop.v: MUX 已更新 (如需, 大多数不需要)
- [ ] batch_test.txt: 测试机器码写在文件开头
- [ ] batch_test.txt: 最后一条是 `sw` 到 `0xFFFF0008` (写 LED)
- [ ] Run Synthesis → 无 Error
- [ ] Run Implementation → 无 Error
- [ ] Generate Bitstream → 成功
- [ ] 上板: SwitchIn[15]=0, LED 显示符合预期
- [ ] 🙋 举手请老师/助教现场验证!

---

# 🆘 紧急情况速查

| 问题 | 最可能的原因 | 立即检查 |
|------|------------|---------|
| Synthesis 报 `syntax error` | 少了分号或括号不匹配 | 检查刚插入的代码行末是否有 `;` |
| Synthesis 报 `undeclared` | 变量名写错 | 检查 regwrite_r 等是否拼写正确 |
| Synthesis 报 `multiple drivers` | 同一信号在两个 always 里赋值 | 检查是否把代码插到了错误的位置 |
| Bitstream 生成成功但 LED 全 0 | ALUOp 设错了, ALU 没执行你的运算 | 检查 ALUOp 值是否匹配指令格式 |
| LED 显示的值差了一点 | ALU 运算表达式写错了 | 检查 ALU.v 中 case 分支的表达式 |
| Vivado 打不开 .xpr | 工程路径含中文 | 把整个文件夹移到纯英文路径 |
| 综合到一半崩溃 | 路径含中文或空格 | 同上 |

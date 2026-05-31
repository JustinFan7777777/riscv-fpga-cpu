# 现场设计备考指南 — 5 分

> 15 周实验课 · 断网 · 学生机 Vivado 2017.4 · 严禁手机/个人电脑
> **基于单周期 CPU (SwitchIn[15]=0, 默认模式)**

---

## 速查卡 (打印携带)

### 指令类型 → 改动范围速查

| 教师可能出的类型 | 需改 ALU | 需改 Decoder(主) | 需改 Decoder(ALU) | 需改 CPUTop | 参考指令 |
|------------------|----------|-----------------|-------------------|-------------|----------|
| R-type 新运算 | 新 ALUControl | 新 opcode 分支 | funct表新增 | 否 | AND/SLL/SRA |
| I-type 新运算 | 新 ALUControl | 新 opcode 分支 | funct表新增 | 否 | ADDI/ANDI |
| U-type 新指令 | 否 | 新 opcode 分支 | 否 | 否 | LUI |
| B-type 新分支 | 否 | 新 opcode 分支 | 否 | 否 | BEQ |
| J-type 新跳转 | 否 | 新 opcode 分支 | 否 | 否 | JAL |
| 访存类 | 否 | 新 opcode 分支 | 否 | 否 | LW |
| 需要新数据通路 | 可能需要 | 新 opcode 分支 | 可能需要 | 加 MUX/连线 | — |

**规律：Decoder 主译码器一定要改，其余看指令类型。**

### 控制信号速查

| 信号 | 值 | 含义 |
|------|-----|------|
| RegWrite | 1 | 写寄存器 (rd 有值) |
| ALUSrc | 0 | ALU_B = rs2_val |
| ALUSrc | 1 | ALU_B = 立即数 |
| MemtoReg | 1 | WD3 = 内存值 (Load) |
| MemWrite | 1 | 写内存 (Store) |
| Branch | 1 | 条件分支 (B-type) |
| Jump | 1 | JAL 跳转 |
| JALRSrc | 1 | JALR 跳转 |
| ALUOp | 00 | 强制 ADD (lw/sw/lui/auipc/jal/jalr) |
| ALUOp | 01 | 强制 SUB (分支比较) |
| ALUOp | 10 | R-type (查 funct3+funct7) |
| ALUOp | 11 | I-type ALU (查 funct3) |

---

## 标准操作流程 (目标: 10 分钟完成)

### 1. 接收指令 — 填写参数表

教师在黑板/PPT 给出：

| 参数 | 本组填写 |
|------|---------|
| 指令名 | ___________ |
| 功能描述 | ___________ |
| 指令格式 (R/I/S/B/U/J) | ___________ |
| opcode[6:0] | ___________ |
| funct3[2:0] | ___________ |
| funct7[6:0] (如有) | ___________ |
| 测试机器码 (1-2 条) | ___________ |
| 预期结果 | ___________ |

### 2. 改 Decoder.v — 主译码器 (文件位置: cpu_project/cpu_project.srcs/sources_1/new/Decoder.v)

**定位：** 搜 `INCLASS_MAIN` (在 `case (opcode)` 的 default 分支上方, 约第 232 行)

**插入模板：**
```verilog
            // ===== INCLASS_MAIN: 现场设计 — 新opcode分支插在此注释上方 =====
            // 模板 (复制上方类似指令格式修改):
            7'bXXXXXXX: begin  // ← 替换为教师给的 opcode (7位)
                regwrite_r = 1'bX;  // 写寄存器? 1=是 0=否
                alusrc_r   = 1'bX;  // B口来源? 0=rs2 1=imm
                memtoreg_r = 1'b0;  // 写回来自内存? (非Load=0)
                memwrite_r = 1'b0;  // 写内存? (非Store=0)
                branch_r   = 1'b0;  // 条件分支? (非B-type=0)
                jump_r     = 1'b0;  // JAL? (非JAL=0)
                jalrsrc_r  = 1'b0;  // JALR? (非JALR=0)
                aluop_r    = 2'bXX; // 00=强制ADD 01=强制SUB 10=R-type 11=I-type-ALU
            end
```

**速查 — 抄哪个现成模板：**
- R-type → 抄 `7'b0110011` 那行 (RegWrite=1, ALUSrc=0, ALUOp=10)
- I-type ALU → 抄 `7'b0010011` 那行 (RegWrite=1, ALUSrc=1, ALUOp=11)
- Load → 抄 `7'b0000011` 那行 (RegWrite=1, ALUSrc=1, MemtoReg=1, ALUOp=00)
- Store → 抄 `7'b0100011` 那行 (RegWrite=0, ALUSrc=1, MemWrite=1, ALUOp=00)
- Branch → 抄 `7'b1100011` 那行 (RegWrite=0, ALUSrc=0, Branch=1, ALUOp=01)
- JAL → 抄 `7'b1101111` 那行 (RegWrite=1, Jump=1, ALUOp=00)
- JALR → 抄 `7'b1100111` 那行 (RegWrite=1, JALRSrc=1, ALUOp=00)

### 3. 改 Decoder.v — ALU 译码器 (如需新运算)

**R-type (ALUOp=10 时):** 搜 `INCLASS_ALU_R` (约第 276 行)

**插入模板：**
```verilog
                // ===== INCLASS_ALU_R: 现场设计 — R-type新运算改此funct3表中对应行 =====
                // 模式: 3'bXXX: alucontrol_r = funct7_5 ? 4'b新编码 : 4'b旧编码;
                3'bXXX: alucontrol_r = funct7_5 ? 4'bYYYY : 4'bZZZZ;
```

**I-type ALU (ALUOp=11 时):** 搜 `INCLASS_ALU_I` (约第 293 行)

**插入模板：**
```verilog
                // ===== INCLASS_ALU_I: 现场设计 — I-type新运算改此funct3表中对应行 =====
                3'bXXX: alucontrol_r = 4'bYYYY;  // 新运算
```

**可选 ALUControl 编码：** 已占用 0000–1100，可用: `1101`, `1110`, `1111`

### 4. 改 ALU.v (如需新运算) — 文件位置: cpu_project/cpu_project.srcs/sources_1/new/ALU.v

**定位：** 搜 `INCLASS_ALU` (在 `case (ALUControl)` 内, 约第 110 行)

**插入模板：**
```verilog
            // ===== INCLASS_ALU: 现场设计 — 新ALU运算插在此注释下方 =====
            4'bXXXX: ALUResult = /* 新运算表达式 */;
```

**常用表达式模板：**
```verilog
A + B                          // 加法
A - B                          // 减法
A & B                          // 按位与
A | B                          // 按位或
A ^ B                          // 按位异或
A << B[4:0]                    // 逻辑左移 (移位量仅低5位)
A >> B[4:0]                    // 逻辑右移
$signed(A) >>> B[4:0]          // 算术右移
($signed(A) < $signed(B)) ? 32'd1 : 32'd0   // 有符号比较 (SLT)
(A < B) ? 32'd1 : 32'd0       // 无符号比较 (SLTU)
~A                             // 按位取反
32'd0 - A                      // 取负 (补码)
(A + B) >> 1                   // 均值 (无溢出)
(A < B) ? A : B                // MIN
(A < B) ? B : A                // MAX
```

### 5. 改 CPUTop.v (如需新数据通路) — 文件位置: cpu_project/cpu_project.srcs/sources_1/new/CPUTop.v

**仅当新指令需要特殊的 ALU_A 来源或特殊的 WD3 来源时才需要改。**

**ALU_A MUX：** 搜 `INCLASS_MUX_A` (约第 219 行)

```verilog
    // ===== INCLASS_MUX_A: 现场设计 — 如需新ALU_A来源，在此MUX添加分支 =====
    // 模板: wire isNEW = (inst[6:0] == 7'bXXXXXXX);
    //       assign ALU_A = isNEW ? new_source : ...原有逻辑...;
    wire isNEW = (inst[6:0] == 7'bXXXXXXX);  // ← 填入新 opcode
    assign ALU_A = isLUI   ? 32'd0   :
                   isAUIPC ? PC      :
                   isNEW   ? rs1_val :  // ← 改为实际数据来源
                             rs1_val;
```

**WD3 MUX：** 搜 `INCLASS_MUX_WD3` (约第 279 行)

```verilog
    // ===== INCLASS_MUX_WD3: 现场设计 — 如需新WD3来源，在此MUX添加分支 =====
    wire JALWDSrc = Jump | JALRSrc;
    wire isNEW_WD3 = (inst[6:0] == 7'bXXXXXXX);  // ← 填入新 opcode
    assign WD3 = JALWDSrc ? PCPlus4 :
                 isNEW_WD3 ? new_wd3_source :  // ← 新数据来源
                 MemtoReg  ? ReadData : ALUResult;
```

**大多数新指令不需要改 CPUTop。** 只有改变了数据流方向（比如新增了 ALU 输入源或写回来源）时才需要。

### 6. 注入测试指令

**推荐方法 — 直接改 batch_test.txt (Ifetch.v 同目录)：**

文件位置: `cpu_project/cpu_project.srcs/sources_1/new/batch_test.txt`

PC 从 0x4000 开始 (对应 mem[0])。将测试机器码写在文件**开头**：
```
XXXXXXXX    ← PC=0x4000 的第一条指令
XXXXXXXX    ← PC=0x4004 的第二条指令
XXXXXXXX    ← ... 后续指令
```

测试指令末尾建议加 `sw x_result, 0xFFFF0008(x0)` 将结果写到 LED 方便观察。

**备选 — 临时 hex：** 搜 Ifetch.v 的 `INCLASS_HEX` (约第 51 行)，临时改 `INIT_FILE` 参数。

### 7. Vivado 操作 (断网环境下)

```
1. 桌面双击 Vivado 2017.4
2. File → Open Project → 找到 cpu_project.xpr → OK
3. Flow Navigator → Run Synthesis → OK (等约 5 分钟)
4. 完成后 Run Implementation → OK (等约 10 分钟)
5. 完成后 Generate Bitstream → OK (等约 3 分钟)
6. 确认 Tcl Console 无红色 Error
7. Hardware Manager → Open Target → Auto Connect
8. 右键 xc7a35t_0 → Program Device → 选 TopDebug.bit → OK
```

### 8. 上板验证

**传统方式 (不依赖 UART，最稳妥)：**
1. 测试指令末尾 `sw x_result, 0xFFFF0008(x0)` 写 LED
2. `sw x_result, 0xFFFF0010(x0)` + `sw x_seg, 0xFFFF0014(x0)` 写数码管
3. 观察 LED/数码管是否符合预期
4. 举手请老师/助教现场验证

---

## 现场设计文件改动点汇总

| 文件 | INCLASS 标记 | 大致行号 | 改动内容 |
|------|-------------|---------|---------|
| Decoder.v | `INCLASS_MAIN` | ~232 | 新 opcode 主译码分支 |
| Decoder.v | `INCLASS_ALU_R` | ~276 | R-type ALU 译码 funct3 表 |
| Decoder.v | `INCLASS_ALU_I` | ~293 | I-type ALU 译码 funct3 表 |
| ALU.v | `INCLASS_ALU` | ~110 | 新 ALU 运算 case 分支 |
| CPUTop.v | `INCLASS_MUX_A` | ~219 | ALU_A 来源 MUX (按需) |
| CPUTop.v | `INCLASS_MUX_WD3` | ~279 | 写回数据 MUX (按需) |
| Ifetch.v | `INCLASS_HEX` | ~51 | hex 文件路径 / 测试指令注入 |

### 不要动的文件 (Bonus 模块, 不影响基础分数)

| 文件 | 原因 |
|------|------|
| VGA.v, CPUTopPipeline.v | Bonus 模块 |
| PipeRegs.v, HazardUnit.v, Ifetch_Pipe.v, RegFile_Pipe.v | 流水线子模块 |
| DataMemory.v (VGA 帧缓冲部分) | Bonus MMIO 扩展 |
| DebugController.v, UartRx.v, UartTx.v | 调试模块 (现场设计不需要 UART) |

### 参考: ISA 扩展现有模式

工程中已实现 3 条自定义指令 (POPCNT/CLZ/CTZ)，可作为现场设计参考：

- **区分机制：** `custom_op = inst[25]` (funct7[0])。RV32I 标准指令 funct7[0]=0，自定义设 funct7[0]=1
- **ALU 编码：** 已占用 4'b0000–4'b1100，剩余 4'b1101–4'b1111 可用
- **参考代码：** [ALU.v:46–95](cpu_project/cpu_project.srcs/sources_1/new/ALU.v#L46) (组合逻辑 function 写法), [Decoder.v:83–84,280–283](cpu_project/cpu_project.srcs/sources_1/new/Decoder.v#L83) (custom_op 译码)

---

## 最终检查清单

- [ ] 收到教师指令, 填好参数表
- [ ] Decoder.v 主译码器: 新 opcode 分支已添加 (复制模板, 改 X)
- [ ] Decoder.v ALU 译码器: funct3 表已更新 (如需)
- [ ] ALU.v: 新运算 case 分支已添加 (如需)
- [ ] CPUTop.v: ALU_A / WD3 MUX 已更新 (如需)
- [ ] batch_test.txt: 测试机器码已写入文件开头
- [ ] Synthesis 无 Error
- [ ] Implementation 无 Error
- [ ] Bitstream 生成成功
- [ ] 上板 LED/数码管显示与预期一致
- [ ] 举手请老师/助教现场验证

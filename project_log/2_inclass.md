# 现场设计备考指南 — 5 分

> 15 周实验课 · 断网 · 学生机 Vivado 2017.4 · 严禁手机/个人电脑

---

## 速查卡 (打印携带)

### 指令类型 → 改动范围速查

| 教师可能出的类型 | 需改 ALU | 需改 Decoder(主) | 需改 Decoder(ALU) | 需改 CPUTop | 参考指令 |
|------------------|----------|-----------------|-------------------|-------------|----------|
| R-type 新运算 | ✅ 新 ALUControl | ✅ 新 opcode 分支 | ✅ funct表新增 | ❌ | AND/SLL/SRA |
| I-type 新运算 | ✅ 新 ALUControl | ✅ 新 opcode 分支 | ✅ funct表新增 | ❌ | ADDI/ANDI |
| U-type 新指令 | ❌ | ✅ 新 opcode 分支 | ❌ | ❌ | LUI |
| B-type 新分支 | ❌ | ✅ 新 opcode 分支 | ❌ | ❌ | BEQ |
| J-type 新跳转 | ❌ | ✅ 新 opcode 分支 | ❌ | ❌ | JAL |
| 访存类 | ❌ | ✅ 新 opcode 分支 | ❌ | ❌ | LW |
| 需要新数据通路 | ❔ | ✅ | ❔ | ✅ 加 MUX/连线 | — |

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

### 文件改动点定位 (Ctrl+F 搜 `INCLASS`)

| 文件 | 搜 `INCLASS` 找到的位置 |
|------|------------------------|
| `ALU.v` | 新 ALU 运算插在哪里 (case 内) |
| `Decoder.v` | 新 opcode 分支插在哪里 (主译码器 case) |
| `Decoder.v` | ALU 译码表改哪里 (R-type/I-type funct3 表) |
| `CPUTop.v` | ALU_A MUX / WD3 MUX 改哪里 (如需新数据通路) |
| `Ifetch.v` | hex 文件路径 / 测试指令注入方式 |

---

## 标准操作流程 (10 分钟做完)

### 1. 接收指令 — 提取关键参数

教师在黑板/PPT 给出：

| 参数 | 本组填写 (示例) |
|------|----------------|
| 指令名 | \_\_\_\_\_\_\_\_\_\_ |
| 功能描述 | \_\_\_\_\_\_\_\_\_\_ |
| 指令格式 (R/I/S/B/U/J) | \_\_\_\_\_\_\_\_\_\_ |
| opcode[6:0] | \_\_\_\_\_\_\_\_\_\_ |
| funct3[2:0] | \_\_\_\_\_\_\_\_\_\_ |
| funct7[6:0] (如有) | \_\_\_\_\_\_\_\_\_\_ |
| 测试机器码 (1-2 条) | \_\_\_\_\_\_\_\_\_\_ |
| 预期结果 | \_\_\_\_\_\_\_\_\_\_ |

### 2. 改 Decoder.v — 主译码器

1. Ctrl+F 搜 `INCLASS_MAIN` → 定位到 `case (opcode)` 末尾
2. 在 `INCLASS_MAIN` 标记处插入新 opcode 分支：

```verilog
// INCLASS_MAIN: 现场设计 — 新 opcode 分支插在此注释上方
7'bXXXXXXX: begin   // ← 替换为教师给的 opcode
    regwrite_r = 1'bX;   // 写回？1=是 0=否
    alusrc_r   = 1'bX;   // B口来源？0=rs2 1=imm
    memtoreg_r = 1'b0;   // 写回来自内存？(非Load=0)
    memwrite_r = 1'b0;   // 写内存？(非Store=0)
    branch_r   = 1'b0;   // 条件分支？(非B-type=0)
    jump_r     = 1'b0;   // JAL？(非JAL=0)
    jalrsrc_r  = 1'b0;   // JALR？(非JALR=0)
    aluop_r    = 2'bXX;  // 00=ADD 01=SUB 10=R-type 11=I-type-ALU
end
```

参考现有关键模式：R-type 抄 `7'b0110011` 那行，I-type 抄 `7'b0010011`，Load 抄 `7'b0000011`。

### 3. 改 Decoder.v — ALU 译码器 (如需新运算)

1. Ctrl+F 搜 `INCLASS_ALU_R` (R-type 用) 或 `INCLASS_ALU_I` (I-type ALU 用)
2. 在对应 funct3 行修改。常用模式：

**R-type 新增 (funct7_5 区分)：**
```verilog
3'bXXX: alucontrol_r = funct7_5 ? 4'b新编码 : 4'b旧编码;
```

**选未用的 ALUControl：** `1010`, `1011`, `1100`, `1101`, `1110`, `1111` 均未使用。

### 4. 改 ALU.v (如需新运算)

1. Ctrl+F 搜 `INCLASS_ALU` → 定位到 `case (ALUControl)` 内
2. 插入新分支：

```verilog
4'bXXXX: ALUResult = /* 新运算表达式 */;
```

**常用表达式模板：**
```
加法:       A + B
减法:       A - B
按位与:     A & B
按位或:     A | B
按位异或:   A ^ B
左移:       A << B[4:0]
逻辑右移:   A >> B[4:0]
算术右移:   $signed(A) >>> B[4:0]
有符号比较: ($signed(A) < $signed(B)) ? 32'd1 : 32'd0
无符号比较: (A < B) ? 32'd1 : 32'd0
取负:       32'd0 - A
均值:       (A + B) >> 1
```

### 5. 改 CPUTop.v (如需新数据通路)

- Ctrl+F 搜 `INCLASS_MUX` — 定位到 ALU_A / WD3 MUX 附近
- 只有指令需要**特殊的 ALU_A 选择**或**特殊的 WD3 选择**时才需改
- 大部分指令不需要改 CPUTop

### 6. 注入测试指令

**方法① — 改 hex (推荐，最可靠)：**
打开 `assembly/batch_test.hex`，在原内容**前**插入测试机器码。注意：
- PC 从 0x4000 开始 (mem[4096])
- hex 每行一条 8 位十六进制指令
- 第 1 行 → PC=0x4000，第 2 行 → PC=0x4004

**方法② — Debug 写入 (需要 UART 正常)：**
用 Python 通过 UART 发送 CMD_WRITE_INST 写入指令到 IMem。

**方法③ — 临时 hex (Ifetch.v 的 INIT_FILE)：**
Ctrl+F 搜 `INCLASS_HEX` 附近，临时改 `INIT_FILE` 参数指向测试 hex。

### 7. Vivado 操作 (断网环境下)

```
1. 桌面双击 Vivado 2017.4 图标
2. File → Open Project → 找到 cpu_project.xpr → OK
3. 左侧 Flow Navigator → Run Synthesis → OK（等 ~5min）
4. 完成后 Run Implementation → OK（等 ~10min）
5. 完成后 Generate Bitstream → OK（等 ~3min）
6. 底部 Tcl Console 无红色 Error = 成功
7. Hardware Manager → Open Target → Auto Connect
8. 右键 xc7a35t_0 → Program Device → 选 TopDebug.bit → OK
```

### 8. 上板验证

**传统方式 (不依赖 UART，最保险)：**
1. 测试指令末尾 `sw x_result, 0xFFFF0008(x0)` 将结果写到 LED
2. 观察 LED 是否符合预期
3. 或用拨码开关输入 → CPU 计算 → LED/数码管输出

**Debug 方式 (需要 UART 正常)：**
1. Python 脚本: `WRITE_DMEM` 写测试数据 → `RUN` / `STEP` → `READ_REG` 读结果
2. 或直接 `READ_PC` 确认 CPU 跑到了正确位置

---

## 教师可能出的指令类型 & 应对模板

### 类型 1: R-type 新运算 (最常见)

例: AVG(均值), NEG(取负), ABS(绝对值), MAX/MIN, REV(位反转)

**改动:** ALU(新运算) + Decoder(主+ALU)  
**参考:** `7'b0110011` (ADD/SUB/AND/OR)

**重点：** funct7 选一个未用的编码。现有: `0000000`(ADD/SLL等), `0100000`(SUB/SRA), `0000001`(M扩展乘除)。可选: `0010000`, `0100001`, `1000000` 等。

### 类型 2: I-type ALU 新运算

例: ADDI+1(加1), XORN(异或取反), BITC(位计数)

**改动:** ALU(新运算) + Decoder(主+ALU I-type)  
**参考:** `7'b0010011` (ADDI/ANDI/ORI)

### 类型 3: 无运算新指令 (不需要改 ALU)

例: 特殊 Load/Store 变体、新跳转指令

**改动:** 仅 Decoder 主译码器  
**参考:** `7'b0000011` (LW)

---

## Vivado 常见报错速查

| 错误信息关键词 | 原因 | 解决 |
|---------------|------|------|
| `part-select is not allowed` | 表达式上用了 bit-select | 拆为中间 wire 再取位 |
| `undeclared identifier` | 变量未声明 | 添加 `wire` 或 `reg` 声明 |
| `multiple drivers` | 同一信号多处赋值 | 检查是否重复 assign/always |
| `syntax error near 'always'` | `integer i` 在 always 内声明 | 移到模块级 |
| `cannot be assigned within always` | wire 在 always 里赋值 | 改为 reg |

---

## 最终检查清单

在提交前逐项确认：

- [ ] Decoder.v: 新 opcode 分支已添加
- [ ] Decoder.v: ALU 译码表已更新 (如需)
- [ ] ALU.v: 新运算已添加 (如需)
- [ ] CPUTop.v: 新 MUX 通路正确 (如需)
- [ ] 测试指令已写入 hex / 通过 Debug 注入
- [ ] Synthesis 无 Error
- [ ] Implementation 无 Error
- [ ] Bitstream 生成成功
- [ ] 上板结果与预期一致
- [ ] 举手请老师/助教现场验证 ✅

# Report 素材与开发日志

## Report 提纲 (对应 requirement 5.1)

### 1. 开发者说明
- 成员姓名、学号、贡献百分比
- 每人负责的工作

| 姓名 | 学号 | 负责工作 | 贡献比 |
|------|------|---------|--------|
| | | | |
| | | | |
| | | | |

### 2. 开发环境
- Vivado 版本：2017.4
- 操作系统：Windows (Vivado) + macOS (代码开发)
- 开发板型号：EGO1 (XC7A35T)
- GitHub Classroom 团队名：_____
- 仓库地址：_____

### 3. 开发计划与实施情况
- 第 12 周：_____
- 第 13 周：_____
- 第 14 周：_____
- 第 15 周：_____

### 4. CPU 架构设计说明

#### ISA 特性
- 指令集：RISC-V RV32I (基础整数指令集)
- 指令数量：约 37 条
- 指令列表：ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU, ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU, LW, LH, LHU, LB, LBU, SW, SH, SB, BEQ, BNE, BLT, BGE, BLTU, BGEU, LUI, AUIPC, JAL, JALR
- 寄存器：32 个 32-bit 通用寄存器 (x0-x31)，x0 硬连线为 0
- 异常处理：不支持 (基础版本)

#### CPU 架构
- 时钟频率：CPU 25MHz (100MHz 系统时钟 / 4)
- CPI：1 (单周期 CPU)
- 流水线：无 (基础版本)
- 哈佛架构：指令内存 64KB + 数据内存 64KB (物理分离)

#### 地址空间
- IMem: 0x0000_0000 - 0x0000_FFFF (64KB)
- DMem: 0x0000_0000 - 0x0000_FFFF (64KB)
- MMIO: 0xFFFF_0000 - 0xFFFF_0017 (开关/LED/按键/数码管)

#### 外设 IO
- 使用 MMIO 方式访问外设
- 轮询方式 (无中断)
- 外设地址映射：
  - 0xFFFF_0000: 开关输入 (16-bit, 只读)
  - 0xFFFF_0004: 按键输入 (5-bit, 只读)
  - 0xFFFF_0008: LED 输出 (16-bit, 读/写)
  - 0xFFFF_000C: 数码管位选 (8-bit, 读/写)
  - 0xFFFF_0010: 数码管段选组0 (8-bit, 读/写)
  - 0xFFFF_0014: 数码管段选组1 (8-bit, 读/写)

#### CPU 接口
- 时钟：100MHz 输入，内部通过 Clock Divider + BUFG 生成 25MHz CPU 时钟
- 复位：低有效，合并物理按钮复位和 Debug 软复位
- UART：115200 波特率，8N1
- Debug 接口：支持 halt/step/reset/寄存器读写/内存读写/PC 读取

#### 上板使用说明
- 复位：按下 EGO1 右下角按键 (P15)
- 开关输入：左 8 个 (sw_pin) + 右 8 个 (dip_pin)
- LED 输出：16 个 LED
- 数码管：8 位共阳极，位选 + 两组段选
- Debug：通过 Micro USB 串口连接 PC

### 5. 自测试说明

| 测试方法 | 测试类型 | 测试用例 | 结果 |
|---------|---------|---------|------|
| 模拟 | 单元 | Case 0-9 逐个模拟 | |
| 上板 | 集成 | 传统 I/O 测试 | |
| 差分测试 | 集成 | 33 组批量测试 | |

### 6. Bonus (如有)
- 功能点描述：
- 设计思路与模块关系：
- 核心代码说明：
- 测试说明：

### 7. 问题与总结
- 开发过程中遇到的问题：
- 解决方案：
- 对课程项目的意见和建议：

---

## 开发日志

### 第 12 周 (5月)
- 完成 Requirement 文档阅读理解
- 完成 DebugController/UartRx/UartTx 代码审查和中文注释
- 完成项目文件结构整理
- 完成 CPU 架构设计 (单周期、哈佛、RISC-V RV32I)
- 完成全部 11 个 Verilog 模块编写和审查
- 完成 EGO1 XDC 引脚约束
- 完成 batch_test.asm (全部 10 个 Case)

### 第 13 周 (5月)
- 修复 JAL/JALR 写回 bug
- 修复 JALRTarget 语法错误
- 内存扩容 16KB→64KB
- EGO1 端口对齐修正 (SwitchIn/ButtonIn/LEDOut/7-seg)
- 汇编代码完成并审查
- 创建 Vivado TCL 脚本
- 创建团队协作指南

### 第 14 周
- (待记录)

### 第 15 周
- (待记录)

---

## Bug 记录

### Bug 1: JAL/JALR 写回错误
- 发现日期：第 13 周
- 现象：JAL/JALR 把 ALUResult (跳转目标) 写回 rd，应写 PC+4
- 修复：添加 JALWDSrc 信号，WD3 MUX 改为三选一
- 文件：CPUTop.v:253-260

### Bug 2: JALRTarget 语法错误
- 发现日期：第 13 周
- 现象：`{rs1_val + Imm}[31:1], 1'b0` 不是合法 Verilog
- 修复：改为 `{(rs1_val + Imm)[31:1], 1'b0}`
- 文件：CPUTop.v:283

### Bug 3: 内存容量不足
- 发现日期：第 13 周
- 现象：16KB 只有 4096 条目，测试数据可能越界
- 修复：扩容至 64KB (16384 条目)，地址宽度改为 [15:2]
- 文件：Ifetch.v, DataMemory.v

### Bug 4: EGO1 端口宽度不匹配
- 发现日期：第 13 周
- 现象：TopDebug 端口使用了 32-bit 总线，EGO1 实际硬件宽度不同
- 修复：SwitchIn 32→16, ButtonIn 32→5, LEDOut 32→16, SegOut→seg_cs+seg_data_0+seg_data_1
- 文件：TopDebug.v, CPUTop.v, DataMemory.v

# 五级流水线 CPU — 实现与上板指南

## 概述

在单周期 CPU 基础上实现完整的 IF→ID→EX→MEM→WB 五级流水线，含数据转发、Load-Use 暂停和分支预测。通过 EGO1 拨码开关一键切换单周期/流水线模式。

## 架构

```
        T1       T2       T3       T4       T5
IF:   inst1 → inst2 → inst3 → inst4 → inst5 → ...
ID:            inst1 → inst2 → inst3 → inst4 → ...
EX:                     inst1 → inst2 → inst3 → ...
MEM:                             inst1 → inst2 → ...
WB:                                      inst1 → ...
```

## 创新点

1. **一键模式切换** — SwitchIn[15] 拨码开关: 0=单周期(80分基础), 1=流水线(6分Bonus)。两个 CPU 在 TopDebug.v 中同时实例化，输出经 cpu_mode MUX 选择，切换不需要重新烧录。

2. **转发优先编码** — HazardUnit 检测 EX/MEM 和 MEM/WB 两个转发源，EX/MEM 优先 (数据更新)。大部分 RAW 冒险零延迟解决。

3. **Debug 双 CPU 兼容** — Debug 读信号经 cpu_mode MUX，写信号同时广播到两个 CPU (IMem/DMem 保持同步)。两种模式下均可用 UART 暂停、单步、读寄存器。

4. **模块复用** — 流水线 CPU 复用单周期的 Decoder/RegFile/ImmGen/ALU/DataMemory，仅新增 4 个模块 (~400 行 Verilog)。

5. **分布式 RAM IMem 优化** — 将 IMem 从 16K 缩减至 2K words (地址重映射 PC 0x4000→物理0)，释放 ~14000 LUTs，确保 VGA+Pipeline 同时适配 XC7A35T。

## 冒险处理

| 冒险类型 | 场景 | 处理方式 | 代价 |
|---------|------|---------|------|
| RAW (ALU→ALU) | add x1,x2,x3; sub x4,x1,x5 | EX/MEM 转发到 ALU 输入 | 0 拍 |
| RAW (较早) | add x1,x2,x3; nop; sub x4,x1,x5 | MEM/WB 转发到 ALU 输入 | 0 拍 |
| Load-Use | lw x1,0(x2); add x3,x1,x4 | stall 1 拍 + NOP | 1 拍 |
| 控制冒险 | beq taken | flush IF/ID (插入 NOP) | 1 拍 |

## 上板操作指南

### 步骤 1: 确认单周期正常
SwitchIn[15]=0 (拨下)，difftest 33/33 PASS。

### 步骤 2: 切换到流水线模式
SwitchIn[15]=1 (拨上)，CPU 自动切换到流水线模式。

### 步骤 3: 流水线基本验证
```python
import serial, struct
ser = serial.Serial('COM3', 115200, timeout=0.5)

# 加载简单测试程序到 IMem
# (包含 RAW 冒险: add x1,x2,x3 + sub x4,x1,x5)
program = [0x003100B3, 0x40520233]  # add x1,x2,x3; sub x4,x1,x5
for i, instr in enumerate(program):
    ser.write(b'\x40' + struct.pack('>I', i*4) + struct.pack('>I', instr))
    ser.read(1)

# 复位 + 单步 + 读寄存器验证转发
ser.write(b'\x01'); ser.read(1)  # RESET
ser.write(b'\x04'); ser.read(1)  # STEP (add)
ser.write(b'\x04'); ser.read(1)  # STEP (sub)
# 读 x1 → 验证 add 结果, 读 x4 → 验证 sub 结果(转发后)
```

### 步骤 4: 验证清单
- [ ] SwitchIn[15]=0 → difftest 33/33 (单周期正常)
- [ ] SwitchIn[15]=1 → 基本指令执行正确
- [ ] Debug 暂停读寄存器 (两种模式均可)
- [ ] 模式切换瞬间 LED/数码管正确切换
- [ ] 运行中拨开关不崩溃

### 代码位置
```
cpu_project/cpu_project.srcs/sources_1/new/
├── CPUTopPipeline.v    # 流水线 CPU 顶层
├── PipeRegs.v          # 4组流水线寄存器
├── HazardUnit.v        # 冒险检测+转发
└── Ifetch_Pipe.v       # 流水线版取指 (BRAM寄存器读)
```

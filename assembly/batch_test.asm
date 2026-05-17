# ==============================================================================
# batch_test.asm — RISC-V RV32I 基础功能测试 (Case 0-9)
# ==============================================================================
#
# ==== 写给汇编队友：文件用途 ====
# 这个文件包含全部 10 个基础测试用例的 RISC-V 汇编代码。
# 编译成 batch_test.hex 后，通过 $readmemh 加载到 CPU 的指令内存 (IMem)，
# 伴随 TopDebug.bit 一起烧入 FPGA。上电后 CPU 自动从 PC=0 开始执行。
#
# ==== 内存布局 (与 Host 差分测试框架约定) ====
# DMem 地址          内容                  谁写
# 0x4000 (Base+0)    CaseID (32-bit)       Host (通过 UART)
# 0x4004 (Base+4)    OperandA (32-bit)     Host (通过 UART)
# 0x4008 (Base+8)    OperandB (32-bit)     Host (通过 UART)
# 0x400C (Base+C)    Result  (32-bit)      CPU  (本程序写入)
#
# ==== 程序执行流程 ====
# 1. CPU 从 PC=0 开始执行 (复位后)
# 2. 主调度器 (dispatcher) 循环读取 Base+0 处的 CaseID
# 3. 根据 CaseID (0~9) 跳转到对应的 case 处理函数
# 4. case 函数从 Base+4/Base+8 读取操作数, 计算, 结果写入 Base+C
# 5. 完成后跳回 dispatcher 继续读下一个 CaseID
#    (Host 会在两次 case 之间通过 debug 模式写入新的 CaseID 和操作数)
#    如果 CaseID >= 10 (非法), 进入无限循环等待
#
# ==== 寄存器约定 (ABI) ====
# x0  = zero  (恒为0)
# x1  = ra    (返回地址, JAL 自动写入)
# x2  = sp    (栈指针, 本程序不用栈, 可作临时)
# x5  = t0    (临时, 用于加载 CaseID 等)
# x6  = t1    (临时, 操作数 A)
# x7  = t2    (临时, 操作数 B)
# x28 = t3    (结果寄存器)
# x10-x17 = a0-a7 (函数参数/返回值, 按需使用)
# x8  = s0    (保存寄存器, 用于存 Base 地址 = 0x4000)
#
# ==== 编译指令 (由汇编队友执行) ====
# 你们的 RISC-V toolchain 应该有类似以下命令:
#   riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 batch_test.asm -o batch_test.o
#   riscv64-unknown-elf-ld -Ttext 0x00000000 batch_test.o -o batch_test.elf
#   riscv64-unknown-elf-objcopy -O verilog batch_test.elf batch_test.hex
# 或使用 RARS: java -jar rars.jar a dump .text HexText batch_test.hex batch_test.asm
#
# 生成的 batch_test.hex 放到 assembly/ 目录下即可。
# ==============================================================================

.text
.globl _start

_start:
    # ===========================
    # 主调度器 (dispatcher)
    # ===========================
    # 初始化: s0 = Base 地址 = 0x4000
    lui  s0, 0x4        # s0 = 0x4000 (0x4 << 12)
    # 注: 0x4000 = 0x4 << 12, 所以 lui s0, 4 即可

dispatcher_loop:
    # ---- 步骤1: 读取 CaseID (Base+0) ----
    lw   t0, 0(s0)       # t0 = CaseID (从 0x4000 读取)

    # ---- 步骤2: 根据 CaseID 跳转 ----
    # Case 0: AND
    li   t1, 0
    beq  t0, t1, case0_and

    # Case 1: SLL
    li   t1, 1
    beq  t0, t1, case1_sll

    # Case 2: SRA
    li   t1, 2
    beq  t0, t1, case2_sra

    # Case 3: LUI + ADD
    li   t1, 3
    beq  t0, t1, case3_lui_add

    # Case 4: JAL + AUIPC
    li   t1, 4
    beq  t0, t1, case4_jal_auipc

    # Case 5: JAL + JALR
    li   t1, 5
    beq  t0, t1, case5_jal_jalr

    # Case 6: Fibonacci
    li   t1, 6
    beq  t0, t1, case6_fibonacci

    # Case 7: Popcount
    li   t1, 7
    beq  t0, t1, case7_popcount

    # Case 8: IEEE754 浮点分类
    li   t1, 8
    beq  t0, t1, case8_float_type

    # Case 9: 浮点→Q3.4 量化
    li   t1, 9
    beq  t0, t1, case9_float_q34

    # 非法 CaseID: 死循环等待
    j    dispatcher_dead

dispatcher_dead:
    j    dispatcher_dead   # 无限循环, Host 会通过 HALT 命令暂停

# ==============================================================================
# Case 0: AND — 逻辑与运算
# 输入: OperandA (Base+4), OperandB (Base+8) — 各32-bit
# 输出: Result = A & B → Base+C
# 测试数据: A=0x00000f0f, B=0x00001234 → 期望 0x00000204
#          A=0xffffffff, B=0x00001234 → 期望 0x00001234
# ==============================================================================
case0_and:
    lw   t1, 4(s0)      # t1 = OperandA
    lw   t2, 8(s0)      # t2 = OperandB
    and  t3, t1, t2      # t3 = A & B
    sw   t3, 12(s0)      # 结果写入 Base+C (0x400C)
    j    dispatcher_loop

# ==============================================================================
# Case 1: SLL — 逻辑左移
# 输入: OperandA (被移位数), OperandB (移位量, 只用低5bit)
# 测试: A=0x12481248, B=0x4 → 期望 0x24812480
#       A=0x1, B=0x2d → 期望 0x2000
# ==============================================================================
case1_sll:
    lw   t1, 4(s0)
    lw   t2, 8(s0)
    sll  t3, t1, t2      # t3 = A << B[4:0]
    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 2: SRA — 算术右移
# 输入: OperandA (被移位数), OperandB (移位量, 只用低5bit)
# 测试: A=0x71240000, B=0x18 → 期望 0x00000071
#       A=0x81231234, B=0x24 → 期望 0xf8123123
# ==============================================================================
case2_sra:
    lw   t1, 4(s0)
    lw   t2, 8(s0)
    sra  t3, t1, t2      # t3 = A >>> B[4:0] (算术右移)
    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 3: LUI + ADD — 先加载高位立即数, 再加
# 代码: lui a0, 0x12345; add s3, t1, a0
# 输入: OperandA (t1), OperandB 忽略
# 测试: A=0x10000000 → 期望 0x22345000
#       A=0x1        → 期望 0x12345001
# ==============================================================================
case3_lui_add:
    lw   t1, 4(s0)       # t1 = OperandA
    lui  a0, 0x12345      # a0 = 0x12345000
    add  t3, t1, a0       # t3 = t1 + a0
    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 4: JAL + AUIPC
# 代码片段:
#    jal  a0, target
# target:
#    auipc a1, 0x12345
#    sub s3, a1, a0       # s3 = (PC+0x12345000) - (PC+4) = 0x12344FFC
#    add s3, s3, t1       # s3 = 0x12344FFC + OperandA
# 输入: OperandA (t1)
# 测试: A=0x0  → 期望 0x12345000 (因为 jal 之后 auipc 的 PC = target addr + 4)
#                              (auipc a1=PC+0x12345000, sub 减去 a0(=target PC+4),
#                               add 加上 OperandA,
#                               实际: 0x12344FFC + 4 + t1? 等等需要精确算)
# 实际: jal a0, target → a0 = PC+4 (当前PC+4)
#       auipc a1, 0x12345 → a1 = PC + 0x12345000 (此处PC=target的地址)
#       sub s3, a1, a0 → s3 = a1 - a0 = (target_PC + 0x12345000) - (jal_PC + 4)
#                        = (jal_PC + 4 + 0x12345000) - (jal_PC + 4)
#                        = 0x12345000
#                        (因为target是jal的下一条, target_PC = jal_PC+4)
# 待验证! 队友请根据实际 PC 计算确认
# 测试数据: A=0x0 → 期望 0x12345000
#          A=0x10 → 期望 0x12345010
# ==============================================================================
case4_jal_auipc:
    lw   t1, 4(s0)       # t1 = OperandA
    jal  a0, case4_target
case4_target:
    auipc a1, 0x12345     # a1 = PC + 0x12345000
    sub  t3, a1, a0       # t3 = a1 - a0 (= 0x12345000 因为 target 紧接 jal)
    add  t3, t3, t1       # t3 = 0x12345000 + OperandA
    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 5: JAL + JALR — 函数调用与返回, 然后加法
# 代码: jal func; add s3, t1, t2; func: jr ra
# jal func 跳转到 func, a0=PC+4 (返回地址)
# func 什么也不做, jr ra 立即返回
# 回到 jal 的下一条: add s3, t1, t2
# 测试: A=0x5, B=0x6 → 期望 0xB
#       A=0x1, B=0x2 → 期望 0x3
# ==============================================================================
case5_jal_jalr:
    lw   t1, 4(s0)       # t1 = OperandA
    lw   t2, 8(s0)       # t2 = OperandB
    jal  ra, case5_func   # 调用 func, ra = 返回地址
    # func 返回后执行此处:
    add  t3, t1, t2       # t3 = t1 + t2
    sw   t3, 12(s0)
    j    dispatcher_loop

case5_func:
    jr   ra               # 返回 (JALR x0, ra, 0)

# ==============================================================================
# Case 6: Fibonacci — 斐波那契数列
# 输入: OperandA = n (斐波那契下标, 8-bit, n>=1)
# 输出: fib(n) — 第 n 个斐波那契数 (32-bit)
# fib(1)=1, fib(2)=1, fib(3)=2, fib(4)=3, fib(5)=5, ...
# 测试: n=1 → 1, n=2 → 1, n=3 → 2, n=4 → 3
# ==============================================================================
case6_fibonacci:
    lw   t1, 4(s0)       # t1 = n (OperandA, 只有低8bit有效)
    # TODO: 队友实现斐波那契算法
    #
    # 算法思路 (循环, 不递归):
    #   if n <= 2: result = 1
    #   else:
    #     a=1, b=1
    #     loop n-2 times:
    #       c = a+b; a = b; b = c
    #     result = b
    #
    # 寄存器建议:
    #   t1 = n (已加载)
    #   t2 = loop counter
    #   a0 = a (prev)
    #   a1 = b (curr)
    #   a2 = c (next)
    #   t3 = result
    #
    # 在此编写你的代码...

    # --- 占位代码 (请替换) ---
    li   t3, 1            # 临时返回1, 实际需要实现算法
    # --- 占位结束 ---

    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 7: Popcount — 统计 8-bit 数据中 '1' 的个数
# 输入: OperandA (低8bit有效)
# 输出: OperandA 的二进制表示中 1 的个数 (8-bit)
# 测试: A=0xC1 (0b11000001) → 3
#       A=0xF8 (0b11111000) → 5
# ==============================================================================
case7_popcount:
    lw   t1, 4(s0)       # t1 = 8-bit data (OperandA)
    # TODO: 队友实现 popcount 算法
    #
    # 算法思路1 (简单循环):
    #   count = 0
    #   loop 8 times:
    #     if (data & 1): count++
    #     data = data >> 1
    #   result = count
    #
    # 算法思路2 (分治):
    #   data = (data & 0x55) + ((data>>1) & 0x55)
    #   data = (data & 0x33) + ((data>>2) & 0x33)
    #   data = (data & 0x0F) + ((data>>4) & 0x0F)
    #   result = data
    #
    # 寄存器建议:
    #   t1 = data
    #   t2 = count / temp
    #   t3 = result
    #
    # 在此编写你的代码...

    # --- 占位代码 (请替换) ---
    li   t3, 0            # 临时返回0, 实际需要实现算法
    # --- 占位结束 ---

    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 8: IEEE 754 半精度浮点数分类
# 输入: OperandA (低16bit有效: sign[15] exp[14:10] mantissa[9:0])
# 输出: 类型编码 (8-bit)
#   0 = 正负零:      exp=0,  mantissa=0
#   1 = 正负无穷大:   exp=31, mantissa=0
#   2 = NaN:          exp=31, mantissa!=0
#   3 = 规约化数:     1 <= exp <= 30
#   4 = 非规约化数:   exp=0,  mantissa!=0
# 测试: 0x8000(负零)→0, 0x0000(正零)→0, 0x7C00(+∞)→1,
#       0xFC00(-∞)→1, 0xFC01(NaN)→2, 0x2026(规约)→3,
#       0xC202(规约)→3, 0x0003(非规约)→4, 0x80E1(非规约)→4
# ==============================================================================
case8_float_type:
    lw   t1, 4(s0)       # t1 = 16-bit float (OperandA)
    # TODO: 队友实现 IEEE 754 半精度分类
    #
    # 提取字段:
    #   sign  = (t1 >> 15) & 0x1     (不用也可, 类型判断与符号无关)
    #   exp   = (t1 >> 10) & 0x1F    (5-bit 指数)
    #   mant  = t1 & 0x3FF           (10-bit 尾数)
    #
    # 判断逻辑 (伪代码):
    #   if (exp == 0):
    #       if (mant == 0): result = 0  (零)
    #       else:           result = 4  (非规约化数)
    #   elif (exp == 31):
    #       if (mant == 0): result = 1  (无穷大)
    #       else:           result = 2  (NaN)
    #   else:
    #       result = 3                  (规约化数)
    #
    # 寄存器建议:
    #   t1 = 原始数据
    #   t2 = 指数 (exp)
    #   a0 = 尾数 (mantissa)
    #
    # 在此编写你的代码...

    # --- 占位代码 (请替换) ---
    li   t3, 0            # 临时返回0, 实际需要实现算法
    # --- 占位结束 ---

    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 9: IEEE 754 半精度浮点数 → Q3.4 定点数 量化
# 输入: OperandA (低16bit有效, IEEE 754 半精度, 只含规约化数)
# 输出: Q3.4 定点数 (8-bit: sign[7] int[6:4] frac[3:0])
#       负数输出补码形式
#
# Q3.4 格式: 最高位符号位, 3位整数, 4位小数
# 可表示范围: 正数 0.0625 ~ 7.9375, 负数 -8.0 ~ -0.0625
# 量化: 四舍五入到最近的 1/16 = 0.0625
#
# IEEE 754 半精度 → 实际值:
#   value = (-1)^sign * 2^(exp-15) * (1 + mantissa/1024)
#   (规约化数: 隐含 leading 1)
#
# 转换步骤:
#   1. 提取 sign, exp (5-bit), mantissa (10-bit)
#   2. 计算实际值: val = (1 + mant/1024) * 2^(exp-15)
#   3. 乘以 16 (Q3.4 的小数部分4bit → 乘16把4bit拉成整数)
#      scaled = val * 16
#   4. 四舍五入: result_int = round(scaled)
#   5. 如果是负数, 取补码: result_int = (~result_int + 1) & 0xFF (截断到8bit)
#   6. 输出 result_int[7:0]
#
# 测试: 0x3C00 (1.0) → 0x10 (16 = 1.0*16)
#       0x3E00 (1.5) → 0x18 (24 = 1.5*16)
#       0x4200 (3.0) → 0x30 (48 = 3.0*16)
#       0xC400 (-3.0) → 0xD0 (-48的补码=256-48=208=0xD0)
#       0x4240 (3.125) → 0x32 (50 = 3.125*16)
#       0xBF00 (-1.875) → 0xE4 (-30的补码=256-30=226=0xE2)
#       注: 0xBF00 = 1_01111_1100000000 = -1 * 2^(15-15) * (1+0.875) = -1.875
#           -1.875*16 = -30 → 补码: 256-30=226=0xE2
#       但 xlsx 说要输出 0xE4... 队友请根据实际测试调整!
#       可能四舍五入: -1.875*16 = -30.0 → -30 → 0xE2
#       也可能量化边界值不一样...
#
# 注: 测试数据保证不涉及 NaN/无穷大/非规约化数, 且在 Q3.4 表示范围内
# ==============================================================================
case9_float_q34:
    lw   t1, 4(s0)       # t1 = 16-bit float (OperandA)
    # TODO: 队友实现浮点→Q3.4 定点数量化
    #
    # 运算中会涉及:
    #   - 移位 (sll/srl/sra) 来提取字段
    #   - 乘法和除法 (因为没有 mul/div 指令, 需用移位+加法实现)
    #   - 条件分支处理符号
    #
    # 简化方案 (纯软件实现, 不需要硬件乘法器):
    #   由于 mantissa 只有 10-bit, 且 1/16 精度, 我们可以预计算一部分...
    #   不, 采用通用的移位加法实现.
    #
    # 寄存器建议:
    #   t1 = 原始16-bit float
    #   t2 = sign bit
    #   t3 = exponent (5-bit, bias 15)
    #   t4 = mantissa (10-bit, 隐含 leading 1)
    #   a0,a1,a2 = 中间计算
    #   t3 = 最终结果
    #
    # 在此编写你的代码...

    # --- 占位代码 (请替换) ---
    li   t3, 0            # 临时返回0, 实际需要实现算法
    # --- 占位结束 ---

    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# END — 文件结束
# ==============================================================================

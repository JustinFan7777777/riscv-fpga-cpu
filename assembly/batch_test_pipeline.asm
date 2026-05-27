# ==============================================================================
# batch_test_pipeline.asm — RISC-V RV32I 基础功能测试 (流水线 CPU 专用)
# ==============================================================================
# 与 batch_test.asm 的区别:
#   case 0/1/2 的 lw 和 ALU 指令之间插入 NOP, 防止流水线 load-use 数据冒险
# ==============================================================================
#
# ==== 内存布局 (与 Host 差分测试框架约定) ====
#   Base 地址 = 0x00004000
#   (RARS仿真时改为0x00001000, 手动将lui s0,0x4改为lui s0,0x1)
#
#   DMem 地址          内容               谁写
#   0x4000 (Base+0)    CaseID (32-bit)    Host (通过 UART)
#   0x4004 (Base+4)    OperandA (32-bit)  Host (通过 UART)
#   0x4008 (Base+8)    OperandB (32-bit)  Host (通过 UART)
#   0x400C (Base+C)    Result  (32-bit)   CPU  (本程序写入)
#
# ==== 程序执行流程 ====
#   1. 上电复位, PC=0 → dispatcher
#   2. 循环读取 Base+0 处的 CaseID
#   3. 根据 CaseID (0~9) 跳转到对应 case 处理函数
#   4. case 函数读取操作数 → 计算 → 结果写入 Base+C
#   5. 跳回 dispatcher 继续读下一个 CaseID
#   6. 若 CaseID >= 10: 死循环等待 Host 控制
#
# ==== RARS 模拟器配置 (重要!) ====
#   由于 CPU 硬件 DMem 仅 64KB, Base 地址为 0x4000, 但 RARS 默认数据段
#   起始地址是 0x10010000, 不允许访问 0x4000 这样的"低地址"。
#   解决方法 -> RARS → Settings → Memory Configuration:
#     勾选 "Compact, Text at 0, Data at 0x1000"
#   或 将 "Data segment address" 设为 0x00000000
#   然后重启 RARS 即可正常访问 0x4000。
#
# ==== 编译 (使用课程提供的 RISC-V toolchain) ====
#   riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 batch_test.asm -o batch_test.o
#   riscv64-unknown-elf-ld -Ttext 0x00000000 batch_test.o -o batch_test.elf
#   riscv64-unknown-elf-objcopy -O verilog batch_test.elf batch_test.hex
#
# 或使用 RARS:
#   java -jar rars.jar a dump .text HexText batch_test.hex batch_test.asm
# ==============================================================================

.text
.globl _start

_start:
    # ===========================
    # 主调度器 (dispatcher)
    # ===========================
    # s0 = Base 地址
    #   硬件/Difftest: s0 = 0x00004000 (默认, 编译hex用)
    #   RARS仿真测试:  改为 lui s0, 0x1 → s0 = 0x00001000
    lui  s0, 0x4            # s0 = 0x00004000 (硬件/difftest)

dispatcher_loop:
    # 读取 CaseID (Base+0)
    lw   t0, 0(s0)          # t0 = CaseID (从 0x4000 读取)

    # 根据 CaseID 跳转 (使用减法比较避免 li 指令大量重复)
    # Case 0: AND
    addi t1, x0, 0
    beq  t0, t1, case0_and

    # Case 1: SLL
    addi t1, x0, 1
    beq  t0, t1, case1_sll

    # Case 2: SRA
    addi t1, x0, 2
    beq  t0, t1, case2_sra

    # Case 3: LUI + ADD
    addi t1, x0, 3
    beq  t0, t1, case3_lui_add

    # Case 4: JAL + AUIPC
    addi t1, x0, 4
    beq  t0, t1, case4_jal_auipc

    # Case 5: JAL + JALR
    addi t1, x0, 5
    beq  t0, t1, case5_jal_jalr

    # Case 6: Fibonacci
    addi t1, x0, 6
    beq  t0, t1, case6_fibonacci

    # Case 7: Popcount
    addi t1, x0, 7
    beq  t0, t1, case7_popcount

    # Case 8: IEEE754 浮点分类
    addi t1, x0, 8
    beq  t0, t1, case8_float_type

    # Case 9: 浮点→Q3.4 量化
    addi t1, x0, 9
    beq  t0, t1, case9_float_q34

    # 非法 CaseID (>=10): 死循环等待
dispatcher_dead:
    j    dispatcher_dead

# ==============================================================================
# Case 0: AND — 按位逻辑与
#   输入: OperandA, OperandB (32-bit)
#   输出: A & B
#   测试: A=0x00000f0f,B=0x00001234 → 0x00000204
#         A=0xffffffff,B=0x00001234 → 0x00001234
# ==============================================================================
case0_and:
    lw   t1, 4(s0)          # t1 = OperandA
    lw   t2, 8(s0)          # t2 = OperandB
    addi x0, x0, 0           # NOP: 防止流水线 load-use 数据冒险
    and  t3, t1, t2          # t3 = A & B
    sw   t3, 12(s0)          # 结果写入 Base+C
    j    dispatcher_loop

# ==============================================================================
# Case 1: SLL — 逻辑左移
#   输入: OperandA (被移位数), OperandB (移位量, 仅低5bit有效)
#   测试: A=0x12481248,B=0x4 → 0x24812480
#         A=0x1,B=0x2d     → 0x2000
# ==============================================================================
case1_sll:
    lw   t1, 4(s0)
    lw   t2, 8(s0)
    addi x0, x0, 0           # NOP: 防止流水线 load-use 数据冒险
    sll  t3, t1, t2          # t3 = A << B[4:0]
    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 2: SRA — 算术右移
#   输入: OperandA (被移位数), OperandB (移位量, 仅低5bit有效)
#   测试: A=0x71240000,B=0x18 → 0x00000071
#         A=0x81231234,B=0x24 → 0xf8123123
# ==============================================================================
case2_sra:
    lw   t1, 4(s0)
    lw   t2, 8(s0)
    addi x0, x0, 0           # NOP: 防止流水线 load-use 数据冒险
    sra  t3, t1, t2          # t3 = A >>> B[4:0] (算术右移, 保留符号)
    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 3: LUI + ADD — 加载高位立即数, 再加
#   代码片段: lui a0, 0x12345; add s3, t1, a0
#   输入: OperandA (t1), OperandB 忽略
#   测试: A=0x10000000 → 期望 0x22345000
#         A=0x1        → 期望 0x12345001
# ==============================================================================
case3_lui_add:
    lw   t1, 4(s0)           # t1 = OperandA
    lui  a0, 0x12345          # a0 = 0x12345000
    add  t3, t1, a0           # t3 = OperandA + 0x12345000
    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 4: JAL + AUIPC
#   代码: jal a0, target; target: auipc a1, 0x12345; sub s3, a1, a0; add s3, s3, t1
#   原理: jal 把下条指令地址(PC+4)写入a0, 跳到target.
#         在target处, auipc 把PC+0x12345000写入a1.
#         因为target紧接jal, a0==target的PC, 所以 a1-a0==0x12345000.
#         再加上 OperandA 即为最终结果.
#   测试: A=0x0  → 0x12345000
#         A=0x10 → 0x12345010
# ==============================================================================
case4_jal_auipc:
    lw   t1, 4(s0)           # t1 = OperandA
    jal  a0, case4_target     # a0 = PC+4 (即case4_target的地址), 跳到target
case4_target:
    auipc a1, 0x12345         # a1 = PC + 0x12345000 (此处PC = target地址)
    sub  t3, a1, a0           # t3 = a1 - a0 = 0x12345000
    add  t3, t3, t1           # t3 = 0x12345000 + OperandA
    sw   t3, 12(s0)
    j    dispatcher_loop

# ==============================================================================
# Case 5: JAL + JALR — 函数调用与返回, 然后加法
#   代码: jal func; add s3, t1, t2; func: jr ra
#   jal 跳到 func, ra=返回地址(下条指令地址).
#   func 中 jr ra 立即返回.
#   返回后执行 add s3, t1, t2.
#   测试: A=0x5,B=0x6 → 0xB
#         A=0x1,B=0x2 → 0x3
# ==============================================================================
case5_jal_jalr:
    lw   t1, 4(s0)           # t1 = OperandA
    lw   t2, 8(s0)           # t2 = OperandB
    jal  ra, case5_func       # ra = 返回地址, 跳到 func
    # func 返回后执行此处:
    add  t3, t1, t2           # t3 = t1 + t2
    sw   t3, 12(s0)
    j    dispatcher_loop

case5_func:
    jr   ra                   # JALR x0, ra, 0 → 返回

# ==============================================================================
# Case 6: Fibonacci — 斐波那契数列第n项 (保守NOP版: 每2条指令间2个NOP)
#   输入: OperandA = n (n >= 1, 8-bit)
#   输出: fib(n) (32-bit)
#   算法: 迭代法, fib(1)=fib(2)=1, fib(n)=fib(n-1)+fib(n-2)
#   测试: n=1→1, n=2→1, n=3→2, n=4→3
# ==============================================================================
case6_fibonacci:
    lw   t1, 4(s0)           # t1 = n (OperandA)
    addi x0, x0, 0           # NOP: 防流水线 load-use (1/3)
    addi x0, x0, 0           # NOP: 防流水线 load-use (2/3)
    addi x0, x0, 0           # NOP: 防流水线 load-use (3/3)

    # 若 n <= 2: 直接返回 1
    addi t2, x0, 2           # t2 = 2
    addi x0, x0, 0
    addi x0, x0, 0
    ble  t1, t2, fib_return_one   # n <= 2 时结果为1

    # 初始化: a = 1 (fib(1)), b = 1 (fib(2)), counter = n - 2
    addi a0, x0, 1           # a0 = 1
    addi x0, x0, 0
    addi x0, x0, 0
    addi a1, x0, 1           # a1 = 1
    addi x0, x0, 0
    addi x0, x0, 0
    addi t2, t1, -2          # t2 = n - 2
    addi x0, x0, 0
    addi x0, x0, 0

fib_loop:
    add  a2, a0, a1          # a2 = a + b
    addi x0, x0, 0
    addi x0, x0, 0
    addi a0, a1, 0           # a0 = b
    addi x0, x0, 0
    addi x0, x0, 0
    addi a1, a2, 0           # a1 = c
    addi x0, x0, 0
    addi x0, x0, 0
    addi t2, t2, -1          # counter--
    addi x0, x0, 0
    addi x0, x0, 0
    bgtz t2, fib_loop         # counter > 0 时继续循环

    addi t3, a1, 0           # result = a1 (= fib(n))
    addi x0, x0, 0
    addi x0, x0, 0
    j    fib_done

fib_return_one:
    addi t3, x0, 1           # fib(1) = fib(2) = 1
    addi x0, x0, 0
    addi x0, x0, 0

fib_done:
    sw   t3, 12(s0)
    addi x0, x0, 0
    addi x0, x0, 0
    j    dispatcher_loop

# ==============================================================================
# Case 7: Popcount — 统计8-bit数据中'1'的个数
#   输入: OperandA (低8bit有效)
#   输出: 二进制表示中1的个数 (8-bit)
#   算法: 分治法 (divide-and-conquer, 仅用6条指令)
#     x = (x & 0x55) + ((x >> 1) & 0x55)     # 每2bit一组的popcount
#     x = (x & 0x33) + ((x >> 2) & 0x33)     # 每4bit一组的popcount
#     x = (x & 0x0F) + ((x >> 4) & 0x0F)     # 每8bit一组的popcount
#   测试: A=0xC1 (0b11000001) → 3
#         A=0xF8 (0b11111000) → 5
# ==============================================================================
case7_popcount:
    lw   t1, 4(s0)           # t1 = data (OperandA, 低8bit有效)
    addi x0, x0, 0           # NOP: 防流水线 load-use (1/3)
    addi x0, x0, 0           # NOP: 防流水线 load-use (2/3)
    addi x0, x0, 0           # NOP: 防流水线 load-use (3/3)
    andi t1, t1, 0xFF         # 取低8bit

    # 分治 popcount — Step 1: 2-bit groups
    addi x0, x0, 0
    addi x0, x0, 0
    andi t2, t1, 0x55         # t2 = x & 0x55
    addi x0, x0, 0
    addi x0, x0, 0
    srli t3, t1, 1
    addi x0, x0, 0
    addi x0, x0, 0
    andi t3, t3, 0x55         # t3 = (x>>1) & 0x55
    addi x0, x0, 0
    addi x0, x0, 0
    add  t1, t2, t3           # x = popcount_2bit

    # Step 2: 4-bit groups
    addi x0, x0, 0
    addi x0, x0, 0
    andi t2, t1, 0x33         # t2 = x & 0x33
    addi x0, x0, 0
    addi x0, x0, 0
    srli t3, t1, 2
    addi x0, x0, 0
    addi x0, x0, 0
    andi t3, t3, 0x33         # t3 = (x>>2) & 0x33
    addi x0, x0, 0
    addi x0, x0, 0
    add  t1, t2, t3           # x = popcount_4bit

    # Step 3: 8-bit groups
    addi x0, x0, 0
    addi x0, x0, 0
    andi t2, t1, 0x0F         # t2 = x & 0x0F
    addi x0, x0, 0
    addi x0, x0, 0
    srli t3, t1, 4
    addi x0, x0, 0
    addi x0, x0, 0
    andi t3, t3, 0x0F         # t3 = (x>>4) & 0x0F
    addi x0, x0, 0
    addi x0, x0, 0
    add  t3, t2, t3           # t3 = popcount_8bit (结果)

    addi x0, x0, 0
    addi x0, x0, 0
    sw   t3, 12(s0)
    addi x0, x0, 0
    addi x0, x0, 0
    j    dispatcher_loop

# ==============================================================================
# Case 8: IEEE 754 半精度浮点数分类
#   输入: OperandA (低16bit有效: 符号1bit[15] + 指数5bit[14:10] + 尾数10bit[9:0])
#   输出: 类型编码 (8-bit)
#     0 = 正负零:      exp=0 且 mantissa=0
#     1 = 正负无穷大:   exp=31 且 mantissa=0
#     2 = NaN:          exp=31 且 mantissa!=0
#     3 = 规约化数:     1 <= exp <= 30
#     4 = 非规约化数:   exp=0 且 mantissa!=0
#   测试数据: 0x8000(负零)→0, 0x0000(正零)→0, 0x7C00(+∞)→1, 0xFC00(-∞)→1,
#            0xFC01(NaN)→2, 0x2026(规约)→3, 0xC202(规约)→3,
#            0x0003(非规约)→4, 0x80E1(非规约)→4
# ==============================================================================
case8_float_type:
    lw   t1, 4(s0)           # t1 = 16-bit float (OperandA)
    addi x0, x0, 0           # NOP: load-use (1/3)
    addi x0, x0, 0           # NOP: load-use (2/3)
    addi x0, x0, 0           # NOP: load-use (3/3)

    # 提取字段 (仅低16bit有效)
    slli t1, t1, 16          # 清除高16bit
    addi x0, x0, 0
    addi x0, x0, 0
    srli t1, t1, 16          # t1 = 16-bit 无符号浮点数

    addi x0, x0, 0
    addi x0, x0, 0
    srli t2, t1, 10          # t2 = exp
    addi x0, x0, 0
    addi x0, x0, 0
    andi t2, t2, 0x1F        # t2 = 5-bit 指数

    addi x0, x0, 0
    addi x0, x0, 0
    andi t3, t1, 0x3FF       # t3 = 10-bit 尾数

    # ---- 判断 exp == 0 ----
    addi x0, x0, 0
    addi x0, x0, 0
    bnez t2, case8_check_inf  # exp != 0 → 跳到无穷/NaN/规约判断

    # exp == 0:
    addi x0, x0, 0
    addi x0, x0, 0
    bnez t3, case8_denorm     # mantissa != 0 → 非规约化数 (type=4)
    addi x0, x0, 0
    addi x0, x0, 0
    addi t3, x0, 0            # mantissa == 0 → 零 (type=0)
    addi x0, x0, 0
    addi x0, x0, 0
    j    case8_done

case8_denorm:
    addi t3, x0, 4            # type = 4 (非规约化数)
    addi x0, x0, 0
    addi x0, x0, 0
    j    case8_done

case8_check_inf:
    addi t0, x0, 0x1F         # t0 = 31
    addi x0, x0, 0
    addi x0, x0, 0
    bne  t2, t0, case8_normal # exp != 31 → 规约化数 (type=3)

    # exp == 31:
    addi x0, x0, 0
    addi x0, x0, 0
    bnez t3, case8_nan        # mantissa != 0 → NaN (type=2)
    addi x0, x0, 0
    addi x0, x0, 0
    addi t3, x0, 1            # mantissa == 0 → 无穷大 (type=1)
    addi x0, x0, 0
    addi x0, x0, 0
    j    case8_done

case8_nan:
    addi t3, x0, 2            # type = 2 (NaN)
    addi x0, x0, 0
    addi x0, x0, 0
    j    case8_done

case8_normal:
    addi t3, x0, 3            # type = 3 (规约化数)
    addi x0, x0, 0
    addi x0, x0, 0

case8_done:
    sw   t3, 12(s0)
    addi x0, x0, 0
    addi x0, x0, 0
    j    dispatcher_loop

# ==============================================================================
# Case 9: IEEE 754 半精度浮点数 → Q3.4 定点数 量化
#   输入: OperandA (低16bit有效, IEEE 754 半精度, 仅规约化数)
#   输出: Q3.4 定点数 (8-bit: 符号1bit + 整数3bit + 小数4bit)
#         负数为补码形式
#
#   原理: half_value = (-1)^sign × 2^(exp-15) × (1 + mantissa/1024)
#         Q3.4值 = half_value × 16
#         = (1024 + mantissa) × 2^(exp-15) / 64
#         = M × 2^(exp-21)      (其中 M = 1024 + mantissa)
#
#   即: 若 exp >= 21: M 左移 (exp-21) 位
#       若 exp <  21: M 右移 (21-exp) 位
#       若 sign=1: 取补码
#
#   测试: 0x3C00(+1.0)   → 0x10 (+16 = +1.0×16)
#         0x3E00(+1.5)   → 0x18 (+24 = +1.5×16)
#         0x4200(+3.0)   → 0x30 (+48 = +3.0×16)
#         0xC400(-4.0)   → 0xC0 (192 = 两补码的-64)
#         0x4240(+3.125) → 0x32 (+50 = +3.125×16)
#         0xBF00(-1.75)  → 0xE4 (228 = 两补码的-28)
# ==============================================================================
case9_float_q34:
    lw   t1, 4(s0)           # t1 = 16-bit float (OperandA)
    addi x0, x0, 0           # NOP: load-use (1/3)
    addi x0, x0, 0           # NOP: load-use (2/3)
    addi x0, x0, 0           # NOP: load-use (3/3)

    # ---- 步骤1: 提取符号位 ----
    srli t2, t1, 15          # t2 = sign (0或1)
    addi x0, x0, 0
    addi x0, x0, 0

    # 清零高16bit, 保留16bit浮点数
    slli t1, t1, 16
    addi x0, x0, 0
    addi x0, x0, 0
    srli t1, t1, 16

    # ---- 步骤2: 提取指数 (bits [14:10]) ----
    addi x0, x0, 0
    addi x0, x0, 0
    srli t3, t1, 10
    addi x0, x0, 0
    addi x0, x0, 0
    andi t3, t3, 0x1F        # t3 = exponent

    # ---- 步骤3: 提取尾数 (bits [9:0]), 添加隐含leading 1 ----
    addi x0, x0, 0
    addi x0, x0, 0
    andi t4, t1, 0x3FF       # t4 = mantissa
    addi x0, x0, 0
    addi x0, x0, 0
    addi t4, t4, 1024         # t4 = M = 1024 + mantissa

    # ---- 步骤4: 计算 M × 2^(exp-21) ----
    addi x0, x0, 0
    addi x0, x0, 0
    addi t5, t3, -21          # t5 = exp - 21

    addi x0, x0, 0
    addi x0, x0, 0
    bge  t5, x0, case9_shift_left  # exp >= 21 → 左移

    # exp < 21: 右移
    sub  t5, x0, t5          # t5 = 21 - exp
    addi x0, x0, 0
    addi x0, x0, 0
    srl  a0, t4, t5          # a0 = M >> (21-exp)
    addi x0, x0, 0
    addi x0, x0, 0
    j    case9_sign_handle

case9_shift_left:
    sll  a0, t4, t5          # a0 = M << (exp-21)
    addi x0, x0, 0
    addi x0, x0, 0

    # ---- 步骤5: 处理符号 ----
case9_sign_handle:
    addi x0, x0, 0
    addi x0, x0, 0
    beqz t2, case9_positive   # sign == 0 → 正数

    # 负数: 取32-bit two's complement
    sub  a0, x0, a0          # a0 = -a0
    addi x0, x0, 0
    addi x0, x0, 0

case9_positive:
    andi t3, a0, 0xFF         # 截断到 8-bit (Q3.4 范围)
    addi x0, x0, 0
    addi x0, x0, 0
    sw   t3, 12(s0)
    addi x0, x0, 0
    addi x0, x0, 0
    j    dispatcher_loop

# ==============================================================================
# END — 文件结束
# ==============================================================================

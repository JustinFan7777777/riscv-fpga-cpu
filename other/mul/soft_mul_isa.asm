# ======================================================================
# soft_mul_isa.asm — 软件乘法(移位相加)的 ISA 风格测试用例
# 目标：按项目中 `isa_test.asm` 的格式组织，生成 hex 后可由 Difftest
# 流程直接加载到 IMem（PC_RESET=0x4000）并由工具通过 Debug 读取
# DMem 中的结果验证。
# ======================================================================
.text
.globl _start

# Dispatcher 风格：
#   Base = 0x00004000
#   Base+0  (0x4000) CaseID: 0 = unsigned mul, 1 = signed mul, >=2 -> exit/halt
#   Base+4  (0x4004) OperandA (a0)
#   Base+8  (0x4008) OperandB (a1)
#   Base+12 (0x400C) Result (CPU 写回)
#
# 这样 host/difftest 先把 CaseID 和操作数写到 DMem, CPU 轮询 CaseID 并执行。

_start:
    # 初始化栈指针，避免 signed 路径进入 multiply_signed 时对 0/非法地址做压栈
    li   sp, 0x0000FFC0

    # s0 = Base 地址 (0x00004000)
    lui  s0, 0x4

dispatch_loop:
    lw   t0, 0(s0)          # t0 = CaseID
    addi t1, x0, 0
    beq  t0, t1, case0_unsigned_mul
    addi t1, x0, 1
    beq  t0, t1, case1_signed_mul

    # CaseID >= 2: halt (循环等待 host 复位/下发新的 Case)
halt_loop:
    j    halt_loop

case0_unsigned_mul:
    lw   a0, 4(s0)          # operand A
    lw   a1, 8(s0)          # operand B
    jal  ra, multiply
    sw   a0, 12(s0)
    j    dispatch_loop

case1_signed_mul:
    lw   a0, 4(s0)
    lw   a1, 8(s0)
    jal  ra, multiply_signed
    sw   a0, 12(s0)
    j    dispatch_loop

# ======================================================================
# multiply — 无符号移位相加乘法
# 输入: a0 = multiplicand, a1 = multiplier
# 输出: a0 = low32(product)
# 破坏: t0,t1,t2
# ======================================================================
multiply:
    li   t0, 0       # accumulator
    li   t2, 32

mul_loop:
    andi t1, a1, 1
    beqz t1, mul_skip
    add  t0, t0, a0
mul_skip:
    slli a0, a0, 1
    srli a1, a1, 1
    addi t2, t2, -1
    bnez t2, mul_loop
    mv   a0, t0
    jalr x0, ra, 0

# ======================================================================
# multiply_signed — 有符号乘法: 取绝对值→无符号乘法→按符号恢复
# 破坏: t0 (符号标志), ra 保存到栈
# ======================================================================
multiply_signed:
    li   t0, 0
    bgez a0, ms_check_b
    sub  a0, x0, a0
    xori t0, t0, 1
ms_check_b:
    bgez a1, ms_do_mul
    sub  a1, x0, a1
    xori t0, t0, 1
ms_do_mul:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   t0, 4(sp)
    jal  ra, multiply
    lw   t0, 4(sp)
    lw   ra, 0(sp)
    addi sp, sp, 8
    beqz t0, ms_done
    sub  a0, x0, a0
ms_done:
    jalr x0, ra, 0

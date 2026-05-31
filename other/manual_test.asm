# ==============================================================================
# manual_test.asm — 上板手动验证程序 (开关 + 按键 + LED)
# ==============================================================================
#
# 操作方式:
#   SwitchIn[11:8]  = CaseID (0~9)
#   SwitchIn[7:0]   = Operand A (8-bit, 用于 Fibonacci 的 n 等)
#   ButtonIn[0]     = 按下触发执行
#   ButtonIn[4]     = 切换到下一个预设测试组
#   LED[7:0]        = 结果低 8 位
#   LED[15:8]       = 0x00=计算中, 0xFF=完成, 0xEE=错误
#
# 预设测试组 (按 btn[4] 循环):
#   组0: Case 6 Fibonacci — 开关[7:0]=n
#   组1: Case 8 IEEE754 分类 — 开关[15:0]=16-bit 浮点数
#   组2: Case 0 AND — 开关[7:0]=A, 开关[15:8]=B (需要 16-bit)
#
# 上板流程:
#   1. 通过 UART Debug 将本程序 hex 加载到 IMem 0x4000
#   2. 拨 SwitchIn[11:8] 选测试组, 拨 SwitchIn[7:0] 设操作数
#   3. 按 btn[0] → CPU 执行 → LED[7:0] 显示结果, LED[15:8]=0xFF
#   4. 按 btn[4] 切换测试组
#
# 编译: python3 assemble.py other/manual_test.asm other/manual_test.txt
# ==============================================================================

.text
.globl _start

_start:
    # s0 = MMIO 基址
    lui  s0, 0xFFFF0          # s0 = 0xFFFF0000

    # 初始状态: LED = 0
    sw   x0, 8(s0)            # LEDOut = 0

    # 当前测试组 (保存在 DMem 0x0000)
    sw   x0, 0(x0)            # test_group = 0

# ==============================================================================
# 主循环: 等待按键
# ==============================================================================
main_loop:
    # ---- 显示当前测试组到数码管 (可选, 简化: 用 LED 高 4 位) ----
    lw   t0, 0(x0)            # t0 = test_group
    slli t0, t0, 12           # 移到 LED[15:12]
    sw   t0, 8(s0)            # LED 高 4 位 = 测试组编号

    # ---- 检查 btn[4] → 切换测试组 ----
    lw   t0, 4(s0)            # ButtonIn
    xori t0, t0, 0x1F         # 取反 (EGO1 按下=0)
    andi t1, t0, 0x10         # btn[4]
    beqz t1, check_trigger

    # 切换测试组: (group + 1) % 3
    lw   t0, 0(x0)
    addi t0, t0, 1
    addi t1, x0, 3
    blt  t0, t1, save_group
    li   t0, 0                 # 回绕到 0
save_group:
    sw   t0, 0(x0)

    # 消抖等待
    jal  ra, debounce
    j    main_loop

check_trigger:
    # ---- 检查 btn[0] → 触发执行 ----
    lw   t0, 4(s0)
    xori t0, t0, 0x1F
    andi t0, t0, 0x01         # btn[0]
    beqz t0, main_loop

    # ---- 读开关 ----
    lw   t1, 0(s0)            # SwitchIn

    # ---- LED = 0 (清除旧结果) ----
    sw   x0, 8(s0)

    # ---- 根据 test_group 跳转 ----
    lw   t0, 0(x0)
    beqz t0, do_fib
    addi t0, t0, -1
    beqz t0, do_ieee
    # group=2: AND
    j    do_and

# ==============================================================================
# 测试组 0: Fibonacci
# 输入: SwitchIn[7:0] = n
# 输出: LED[7:0] = fib(n)
# ==============================================================================
do_fib:
    andi t1, t1, 0xFF         # t1 = n (0~255)

    # 防非法输入: n<1 → LED=0xEE
    addi t2, x0, 1
    blt  t1, t2, fib_error

    # n<=2 → 直接返回 1
    addi t2, x0, 2
    ble  t1, t2, fib_one

    # 迭代法: a=1, b=1, counter=n-2
    addi a0, x0, 1            # a = 1
    addi a1, x0, 1            # b = 1
    addi t2, t1, -2           # counter

fib_loop:
    add  a2, a0, a1           # c = a + b
    add  a0, a1, x0           # a = b
    add  a1, a2, x0           # b = c
    addi t2, t2, -1
    bgtz t2, fib_loop
    add  t3, a1, x0            # result = b
    j    show_result

fib_one:
    addi t3, x0, 1
    j    show_result

fib_error:
    li   t3, 0xEE
    j    show_result

# ==============================================================================
# 测试组 1: IEEE754 半精度浮点分类
# 输入: SwitchIn[15:0] = 16-bit 浮点数
# 输出: LED[7:0] = 类型码 (0~4)
# ==============================================================================
do_ieee:
    slli t1, t1, 16
    srli t1, t1, 16           # t1 = 16-bit float

    srli t2, t1, 10
    andi t2, t2, 0x1F         # t2 = exp [14:10]
    andi t3, t1, 0x3FF        # t3 = mantissa [9:0]

    bnez t2, ieee_chk_inf

    # exp == 0
    bnez t3, ieee_denorm      # mantissa != 0 → type 4
    li   t3, 0                 # type 0 (零)
    j    show_result

ieee_denorm:
    li   t3, 4                 # type 4
    j    show_result

ieee_chk_inf:
    addi t4, x0, 0x1F
    bne  t2, t4, ieee_normal  # exp != 31 → type 3

    bnez t3, ieee_nan
    li   t3, 1                 # type 1 (∞)
    j    show_result

ieee_nan:
    li   t3, 2                 # type 2 (NaN)
    j    show_result

ieee_normal:
    li   t3, 3                 # type 3

    j    show_result

# ==============================================================================
# 测试组 2: AND 按位与
# 输入: SwitchIn[15:8]=A, SwitchIn[7:0]=B
# 输出: LED[7:0] = A & B
# ==============================================================================
do_and:
    srli t2, t1, 8
    andi t2, t2, 0xFF         # A
    andi t3, t1, 0xFF         # B
    and  t3, t2, t3            # A & B
    j    show_result

# ==============================================================================
# 结果显示
# ==============================================================================
show_result:
    # LED[7:0] = result, LED[15:8] = 0xFF (完成标志)
    andi t3, t3, 0xFF
    addi t4, x0, 0xFF
    slli t4, t4, 8
    or   t3, t3, t4
    sw   t3, 8(s0)            # LEDOut = {0xFF, result}

    # 消抖
    jal  ra, debounce
    j    main_loop

# ==============================================================================
# 消抖子程序 (~10ms @ 12.5MHz)
# ==============================================================================
debounce:
    li   t6, 0xFFFF
db_loop:
    addi t6, t6, -1
    bnez t6, db_loop
    jalr x0, ra, 0

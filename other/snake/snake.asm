# ==============================================================================
# snake.asm — 贪吃蛇游戏 (RISC-V RV32I 汇编)
# ==============================================================================
#
# ==== 概述 ====
# 本程序是一个运行在自研 RISC-V CPU 上的贪吃蛇游戏，通过 MMIO 读取按键方向、
# 写入 VGA 帧缓冲来渲染画面。游戏在 80×60 字符的文本模式下运行。
#
# ==== 硬件依赖 ====
#   CPU:     RISC-V RV32I + MUL 单周期 (12.5MHz)
#   VGA:     640×480@60Hz 文本模式 (80列×60行)
#   MMIO:    0xFFFF_0004 = 按键输入 [4:0]
#            0xFFFF_0018 = J5-1 随机种子输入 bit0
#            0xFFFF_0100 = VGA 帧缓冲基址 (4800字 × 16-bit)
#
# ==== 按键映射 ====
#   btn[0] (R11) = 右 (Right), 按下=1
#   btn[1] (R17) = 下 (Down), 按下=1
#   btn[2] (R15) = 复位/重开 (Reset), 按下=1
#   btn[3] (V1)  = 左 (Left), 按下=1
#   btn[4] (U4)  = 上 (Up), 按下=1
#
# ==== 颜色编码 (I+R+G+B, 16色) ====
#   前景色 [11:8]:  [11]=I(亮度) [10]=R [9]=G [8]=B
#   背景色 [15:12]: 同上
#   VGA字 = {bg[3:0], fg[3:0], ascii[7:0]}
#
# ==== 内存布局 (DMem, 地址 0x0000_0000 起) ====
#   0x0000 – 0x07FF : SNAKE_X[0..511] (环形缓冲区, 512×4字节)
#   0x0800 – 0x0FFF : SNAKE_Y[0..511] (环形缓冲区)
#   0x2000 : GS_HEAD   (偏移 0)  — 蛇头在缓冲区中的索引
#   0x2004 : GS_TAIL   (偏移 4)  — 蛇尾在缓冲区中的索引
#   0x2008 : GS_LEN    (偏移 8)  — 蛇身当前长度
#   0x200C : GS_DIR    (偏移 12) — 当前方向 (0=上 1=下 2=左 3=右)
#   0x2010 : GS_FOOD_X (偏移 16) — 食物 X 坐标
#   0x2014 : GS_FOOD_Y (偏移 20) — 食物 Y 坐标
#   0x2018 : GS_STATE  (偏移 24) — 游戏状态 (0=运行中 1=游戏结束)
#   0x201C : GS_LFSR   (偏移 28) — 伪随机数发生器状态
#   0x2020 : GS_TEMP_X (偏移 32) — 临时变量
#   0x2024 : GS_TEMP_Y (偏移 36) — 临时变量
#   0x2028 : GS_SCORE  (偏移 40) — 得分
#   0x3000 : OBS_X[0..7] — 障碍物 X 坐标
#   0x3040 : OBS_Y[0..7] — 障碍物 Y 坐标
#
# ==== 寄存器约定 ====
#   s0 = VGA 帧缓冲基址 (0xFFFF_0100)
#   s1 = 按键 MMIO 地址 (0xFFFF_0004)
#   s2 = SNAKE_X 基址 (0x0000_0000)
#   s3 = SNAKE_Y 基址 (0x0000_0800)
#   s4 = 游戏状态基址 (0x0000_2000)
#   s5 = J5-1 随机种子 MMIO 地址 (0xFFFF_0018)
#   s6 = OBS_X 基址 (0x0000_3000)
#   s7 = OBS_Y 基址 (0x0000_3040)
#   sp = 栈指针 (0x0000_F000)
#
# ==== 编译命令 ====
#   riscv64-unknown-elf-as -march=rv32im -mabi=ilp32 snake.asm -o snake.o
#   riscv64-unknown-elf-ld -Ttext 0x00000000 snake.o -o snake.elf
#   riscv64-unknown-elf-objcopy -O verilog snake.elf snake.txt
# ==============================================================================

.text
.globl _start

# ==============================================================================
# 程序入口 — 初始化所有基址寄存器
# ==============================================================================
_start:
    # ---- 栈指针 (DMem 高地址 0x0000_F000) ----
    lui sp, 0xF

    # ---- s0 = VGA 帧缓冲基址 (0xFFFF_0100) ----
    lui  s0, 0xFFFF0
    addi s0, s0, 0x100

    # ---- s1 = 按键 MMIO 地址 (0xFFFF_0004) ----
    lui  s1, 0xFFFF0
    addi s1, s1, 0x4

    # ---- s2 = SNAKE_X 基址 (0x0000_0000) ----
    li s2, 0

    # ---- s3 = SNAKE_Y 基址 (0x0000_0800) ----
        # s3 = SNAKE_Y 基址 (0x0000_0800)
    li s3, 0x800          # s3 = 0x0000_0800
    # 使用 li 伪指令加载 0x800

    # ---- s4 = 游戏状态基址 (0x0000_2000) ----
    lui  s4, 2                  # s4 = 0x0000_2000 (2 << 12 = 0x2000)

    # ---- s5 = J5-1 随机种子输入 (0xFFFF_0018) ----
    lui  s5, 0xFFFF0
    addi s5, s5, 0x18

    # ---- 障碍物坐标数组 ----
    lui  s6, 3
    lui  s7, 3
    addi s7, s7, 0x40

    # ---- 清屏 + 绘制边界 + 初始化游戏 ----
    jal  ra, clear_screen
    jal  ra, draw_border
    jal  ra, init_game

# ==============================================================================
# 主游戏循环
# ==============================================================================
game_loop:
    jal  ra, read_input           # 步骤1: 读按键, 更新方向

    lw   t0, 0x18(s4)        # 步骤2: 检查游戏状态
    bnez t0, game_over_screen

    jal  ra, move_snake           # 步骤3: 移动蛇

    lw   t0, 0x18(s4)        # 步骤4: 移动后再次检查
    bnez t0, game_over_screen

    jal  ra, game_delay           # 步骤5: 延迟
    j    game_loop

# ==============================================================================
# 游戏结束画面 — 显示 "GAME OVER" 并等待复位
# ==============================================================================
game_over_screen:
    # 第 29 行居中显示 "GAME OVER" (9 字符, 从列 35 开始)
    li a0, 29

    li a1, 35
    li a2, 0xC47
    jal  ra, write_char

    li a1, 36
    li a2, 0xC41
    jal  ra, write_char

    li a1, 37
    li a2, 0xC4D
    jal  ra, write_char

    li a1, 38
    li a2, 0xC45
    jal  ra, write_char

    li a1, 39
    li a2, 0xF20
    jal  ra, write_char

    li a1, 40
    li a2, 0xC4F
    jal  ra, write_char

    li a1, 41
    li a2, 0xC56
    jal  ra, write_char

    li a1, 42
    li a2, 0xC45
    jal  ra, write_char

    li a1, 43
    li a2, 0xC52
    jal  ra, write_char

# ---- 等待 btn[2] 按下以重新开始 (含消抖) ----
game_over_loop:
    lw   t0, 0(s1)               # 读按键 (EGO1通用按键按下=1)
    andi t0, t0, 0x1F            # 只保留低5位按钮
    andi t0, t0, 0x04            # 检查 btn[2]
    beqz t0, game_over_loop      # 未按下 → 继续等待

    # 消抖: 延迟 ~10ms 后重新确认 (0xFFFF * 2 cycle ≈ 10.5ms @ 12.5MHz)
    li t6, 0xFFFF
debounce_delay:
    addi t6, t6, -1
    bnez t6, debounce_delay

    lw   t0, 0(s1)               # 重新读取按键
    andi t0, t0, 0x1F
    andi t0, t0, 0x04
    beqz t0, game_over_loop      # 抖动 → 回到等待

    # 确认按下 → 重新开始
    jal  ra, clear_screen
    jal  ra, draw_border
    jal  ra, init_game
    j    game_loop

# ==============================================================================
# init_game — 初始化游戏状态
# ==============================================================================
# 将蛇放在中央，方向向右，放置第一个食物
init_game:
    # ---- LFSR 种子 (混入 J5-1 和按键状态) ----
    li t0, 0x3A5C
    lw   t1, 0(s5)
    andi t1, t1, 1
    slli t1, t1, 15
    xor  t0, t0, t1
    sw   t0, 0x1C(s4)
    lw   t6, 0(s1)               # 读按键状态
    andi t6, t6, 0x1F            # 低5位 (0~31)
    lw   t1, 0(s5)
    andi t1, t1, 1
    add  t6, t6, t1
    addi t6, t6, 10              # 至少迭代 10 次
seed_loop:
    addi sp, sp, -4
    sw   ra, 0(sp)
    jal  ra, lfsr_rand           # 迭代 LFSR 一次
    lw   ra, 0(sp)
    addi sp, sp, 4
    addi t6, t6, -1
    bnez t6, seed_loop

    # ---- 缓冲区索引: HEAD=0, LEN=3 ----
    # 蛇身在环形缓冲区中从 HEAD 向后排列:
    #   buffer[HEAD] = 蛇头, buffer[(HEAD-1)&MASK] = 身体1, ...
    #   buffer[(HEAD-LEN+1)&MASK] = 蛇尾 (最旧)
    # 初始 HEAD=0, 则: buffer[0]=头, buffer[511]=身体1, buffer[510]=身体2(尾)
    sw   x0, 0x0(s4)              # HEAD = 0
    li t0, 0x3
    sw   t0, 0x8(s4)              # LEN = 3
    # TAIL = (HEAD - LEN + 1) & BUF_MASK = (0 - 3 + 1) & 0x1FF = 510
    li t0, 0x1FE                  # 510 = 0x1FE
    sw   t0, 0x4(s4)              # TAIL = 510

    # ---- 方向 = 右 ----
    li t0, 0x3
    sw   t0, 0xC(s4)

    # ---- 状态 = 运行中 ----
    sw   x0, 0x18(s4)
    sw   x0, 0x28(s4)

    # ---- 设置初始蛇身坐标 (环形缓冲区倒序存储) ----
    # buffer[HEAD] = buffer[0] = 蛇头 (40, 30)
    li t0, 40
    sw   t0, 0(s2)                # SNAKE_X[0] = 40
    li t0, 30
    sw   t0, 0(s3)                # SNAKE_Y[0] = 30

    # buffer[(0-1)&0x1FF] = buffer[511] = 身体1 (39, 30)
    li t0, 39
    sw   t0, 2044(s2)             # SNAKE_X[511] = 39 (511*4=2044)
    li t0, 30
    sw   t0, 2044(s3)             # SNAKE_Y[511] = 30

    # buffer[(0-2)&0x1FF] = buffer[510] = 身体2/蛇尾 (38, 30)
    li t0, 38
    sw   t0, 2040(s2)             # SNAKE_X[510] = 38 (510*4=2040)
    li t0, 30
    sw   t0, 2040(s3)             # SNAKE_Y[510] = 30

    # ---- 绘制蛇身 ----
    li a0, 30               # row=30
    li a1, 40               # col=40
    li a2, 0xA40
    jal  ra, write_char

    li a0, 30
    li a1, 39
    li a2, 0xA6F
    jal  ra, write_char

    li a0, 30
    li a1, 38
    li a2, 0xA6F
    jal  ra, write_char

    # ---- 放置随机障碍和第一个食物 ----
    jal  ra, place_obstacles

    # ---- 放置第一个食物 ----
    jal  ra, place_food

    j    game_loop

# ==============================================================================
# read_input — 读取按键并更新蛇的方向
# ==============================================================================
# 防止反向 (不能从 Up 直接变 Down，Left 不能变 Right)
read_input:
    lw   t0, 0(s1)               # t0 = ButtonIn (EGO1通用按键按下=1)
    andi t0, t0, 0x1F            # 只保留低5位按钮

    # btn[2]: 短按暂停, 长按重开
    andi t1, t0, 0x04
    bnez t1, handle_pause_key

    lw   t1, 0xC(s4)          # t1 = 当前方向

    # ---- btn[4] (上) ----
    andi t2, t0, 0x10
    beqz t2, check_down
    li t3, 0x1
    beq  t1, t3, check_down      # 当前是 DOWN → 忽略 UP
    li t1, 0x0
    sw   t1, 0xC(s4)
    jalr x0, ra, 0

check_down:
    # ---- btn[1] (下) ----
    andi t2, t0, 0x02
    beqz t2, check_left
    li t3, 0x0
    beq  t1, t3, check_left      # 当前是 UP → 忽略 DOWN
    li t1, 0x1
    sw   t1, 0xC(s4)
    jalr x0, ra, 0

check_left:
    # ---- btn[3] (左) ----
    andi t2, t0, 0x08
    beqz t2, check_right
    li t3, 0x3
    beq  t1, t3, check_right     # 当前是 RIGHT → 忽略 LEFT
    li t1, 0x2
    sw   t1, 0xC(s4)
    jalr x0, ra, 0

check_right:
    # ---- btn[0] (右) ----
    andi t2, t0, 0x01
    beqz t2, read_done
    li t3, 0x2
    beq  t1, t3, read_done       # 当前是 LEFT → 忽略 RIGHT
    li t1, 0x3
    sw   t1, 0xC(s4)

read_done:
    jalr x0, ra, 0

handle_pause_key:
    addi sp, sp, -4
    sw   ra, 0(sp)
    li t6, 0x80000
pause_first_hold:
    lw   t0, 0(s1)
    andi t0, t0, 0x04
    beqz t0, pause_short
    addi t6, t6, -1
    bnez t6, pause_first_hold
    j    pause_restart

pause_short:
    jal  ra, draw_paused
pause_wait_release:
    lw   t0, 0(s1)
    andi t0, t0, 0x04
    bnez t0, pause_wait_release
pause_wait_press:
    lw   t0, 0(s1)
    andi t0, t0, 0x04
    beqz t0, pause_wait_press
    li t6, 0x80000
pause_second_hold:
    lw   t0, 0(s1)
    andi t0, t0, 0x04
    beqz t0, pause_resume
    addi t6, t6, -1
    bnez t6, pause_second_hold
    j    pause_restart

pause_resume:
    jal  ra, clear_paused
    lw   ra, 0(sp)
    addi sp, sp, 4
    jalr x0, ra, 0

pause_restart:
    lw   ra, 0(sp)
    addi sp, sp, 4
    jal  ra, clear_screen
    jal  ra, draw_border
    jal  ra, init_game

# ==============================================================================
# move_snake — 移动蛇一步
# ==============================================================================
move_snake:
    # ---- 加载当前状态 ----
    lw   t0, 0x0(s4)         # t0 = head_index
    lw   t1, 0x8(s4)          # t1 = len
    lw   t2, 0xC(s4)          # t2 = direction

    # ---- 读取蛇头坐标 ----
    # SNAKE_X[head_index]: 地址 = s2 + head_index * 4
    # (t0 = head_index 从第311行加载, 此处仍有效)
    slli t3, t0, 2               # t3 = head_index * 4
    add  t0, s2, t3              # t0 = &SNAKE_X[head_index]
    lw   t4, 0(t0)               # t4 = head_x
    add  t0, s3, t3              # t0 = &SNAKE_Y[head_index]
    lw   t5, 0(t0)               # t5 = head_y

    # ---- 根据方向计算新蛇头坐标 ----
    # 减法链: dir=0→上, 1→下, 2→左, 3→右 (省去3条li)
    beqz t2, mv_up
    addi t2, t2, -1
    beqz t2, mv_down
    addi t2, t2, -1
    beqz t2, mv_left
    # dir=3: 右
    addi t4, t4, 1
    j    mv_check_wall
mv_up:
    addi t5, t5, -1
    j    mv_check_wall
mv_down:
    addi t5, t5, 1
    j    mv_check_wall
mv_left:
    addi t4, t4, -1

mv_check_wall:
    # ---- 墙壁碰撞检测 (x in [1,78], y in [2,57]) ----
    li t6, 1
    blt  t4, t6, mv_game_over     # x < 1
    li t6, 78
    blt  t6, t4, mv_game_over     # 78 < x → x > 78
    li t6, 2
    blt  t5, t6, mv_game_over     # y < 2
    li t6, 57
    blt  t6, t5, mv_game_over     # 57 < y → y > 57

    # ---- 障碍物碰撞检测 ----
    li t2, 0
mv_obs_loop:
    li t1, 8
    bge  t2, t1, mv_no_obstacle
    slli t3, t2, 2
    add  a3, s6, t3
    lw   a0, 0(a3)
    add  a3, s7, t3
    lw   a1, 0(a3)
    bne  t4, a0, mv_obs_next
    bne  t5, a1, mv_obs_next
    j    mv_game_over
mv_obs_next:
    addi t2, t2, 1
    j    mv_obs_loop

mv_no_obstacle:
    # ---- 保存新蛇头到临时变量 ----
    sw   t4, 0x20(s4)
    sw   t5, 0x24(s4)
    lw   t1, 0x8(s4)

    # ---- 自身碰撞检测 ----
    # 遍历环形缓冲区: 从 (HEAD - LEN + 1) 到 (HEAD - 1), 跳过 tail_index
    lw   t6, 0x4(s4)         # t6 = tail_index (即将被擦除, 不算碰撞)

    # 如果 len <= 1: 跳过
    li t2, 1
    ble  t1, t2, mv_no_self

    # start_idx = (HEAD - LEN + 1) & BUF_MASK (环形缓冲区起始位置)
    lw   t0, 0x0(s4)         # t0 = HEAD
    sub  t0, t0, t1           # t0 = HEAD - LEN
    addi t0, t0, 1            # start = HEAD - LEN + 1
    andi t0, t0, 0x1FF        # start_idx (环形取模)

    li t2, 0                  # t2 = 循环计数 i
mv_self_loop:
    add  t3, t0, t2           # t3 = start_idx + i
    andi t3, t3, 0x1FF        # 环形取模 → buffer index
    beq  t3, t6, mv_self_next # 跳过 tail_index

    slli t3, t3, 2            # 字偏移
    add  a3, s2, t3            # &SNAKE_X[idx]
    lw   a0, 0(a3)            # a0 = body_x
    add  a3, s3, t3            # &SNAKE_Y[idx]
    lw   a1, 0(a3)            # a1 = body_y
    bne  t4, a0, mv_self_next
    bne  t5, a1, mv_self_next
    j    mv_game_over          # 碰撞!
mv_self_next:
    addi t2, t2, 1
    blt  t2, t1, mv_self_loop

mv_no_self:
    # ---- 食物碰撞检测 ----
    lw   t2, 0x10(s4)
    lw   t3, 0x14(s4)
    bne  t4, t2, mv_no_food
    bne  t5, t3, mv_no_food

    # ---- 吃到食物: LEN++ ----
    lw   t1, 0x8(s4)
    addi t1, t1, 1
    sw   t1, 0x8(s4)
    lw   t0, 0x28(s4)
    addi t0, t0, 1
    sw   t0, 0x28(s4)

    # 检查最大长度
    li t2, 0x1F4
    blt  t1, t2, mv_grow
    j    mv_game_over             # 胜利!

mv_grow:
    # 放置新食物, 重载 new_x/new_y
    addi sp, sp, -4
    sw   ra, 0(sp)
    jal  ra, place_food
    lw   ra, 0(sp)
    addi sp, sp, 4
    lw   t4, 0x20(s4)
    lw   t5, 0x24(s4)
    j    mv_update_buf

mv_no_food:
    # ---- 擦除蛇尾 ----
    lw   t6, 0x4(s4)
    slli t2, t6, 2
    add  t0, s3, t2               # &SNAKE_Y[tail]
    lw   a0, 0(t0)               # a0 = tail_y (row)
    add  t0, s2, t2               # &SNAKE_X[tail]
    lw   a1, 0(t0)               # a1 = tail_x (col)

    li a2, 0x20
    # 保存 t4,t5,ra
    addi sp, sp, -12
    sw   t4, 0(sp)
    sw   t5, 4(sp)
    sw   ra, 8(sp)
    jal  ra, write_char
    lw   ra, 8(sp)
    lw   t5, 4(sp)
    lw   t4, 0(sp)
    addi sp, sp, 12

    # TAIL = (TAIL + 1) & 0x1FF
    lw   t6, 0x4(s4)
    addi t6, t6, 1
    andi t6, t6, 0x1FF
    sw   t6, 0x4(s4)

mv_update_buf:
    # ---- 更新蛇头 ----
    # HEAD = (HEAD + 1) & 0x1FF
    lw   t0, 0x0(s4)
    addi t0, t0, 1
    andi t0, t0, 0x1FF
    sw   t0, 0x0(s4)

    # buffer[HEAD] = (new_x, new_y)
    slli t2, t0, 2
    add  t3, s2, t2
    sw   t4, 0(t3)                # SNAKE_X[HEAD] = new_x
    add  t3, s3, t2
    sw   t5, 0(t3)                # SNAKE_Y[HEAD] = new_y

    # ---- 绘制新蛇头 ----
    add  a0, t5, x0
    add  a1, t4, x0
    li a2, 0xA40
    addi sp, sp, -4
    sw   ra, 0(sp)
    jal  ra, write_char
    lw   ra, 0(sp)
    addi sp, sp, 4

    # ---- 将旧蛇头变为蛇身 ----
    lw   t0, 0x0(s4)
    addi t0, t0, -1
    andi t0, t0, 0x1FF         # old_head_index = (HEAD - 1) & MASK
    slli t0, t0, 2
    add  t1, s2, t0
    lw   a1, 0(t1)               # a1 = old_head_x (col)
    add  t1, s3, t0
    lw   a0, 0(t1)               # a0 = old_head_y (row)

    lw   t2, 0x8(s4)
    li t3, 1
    ble  t2, t3, mv_done          # len <= 1 → 不画身体

    li a2, 0xA6F
    addi sp, sp, -4
    sw   ra, 0(sp)
    jal  ra, write_char
    lw   ra, 0(sp)
    addi sp, sp, 4

mv_done:
    jalr x0, ra, 0

mv_game_over:
    li t0, 0x1
    sw   t0, 0x18(s4)
    jalr x0, ra, 0

# ==============================================================================
# place_food — 在空白位置随机放置食物
# ==============================================================================
place_food:
    addi sp, sp, -4
    sw   ra, 0(sp)

pf_try:
    # ---- 生成 X (1~78), 拒绝采样保证均匀分布 ----
pf_x_gen:
    jal  ra, lfsr_rand
    andi t0, t0, 0x7F            # [0,127]
    li t1, 78
    bge  t0, t1, pf_x_gen        # >=78 → 重试
    addi t4, t0, 1               # t4 = food_x (1~78)

    # ---- 生成 Y (2~57), 拒绝采样保证均匀分布 ----
pf_y_gen:
    jal  ra, lfsr_rand
    andi t0, t0, 0x3F            # [0,63]
    li t1, 56
    bge  t0, t1, pf_y_gen        # >=56 → 重试
    addi t5, t0, 2               # t5 = food_y (2~57)

    # ---- 检查是否在蛇身上 ----
    lw   t1, 0x8(s4)
    lw   t0, 0x0(s4)
    sub  t0, t0, t1
    addi t0, t0, 1               # start = HEAD - LEN + 1
    li t2, 0               # i = 0

pf_body_loop:
    add  t3, t0, t2              # idx = start + i
    andi t3, t3, 0x1FF
    slli t3, t3, 2
    add  t6, s2, t3
    lw   a0, 0(t6)               # body_x
    add  t6, s3, t3
    lw   a1, 0(t6)               # body_y
    bne  t4, a0, pf_next
    bne  t5, a1, pf_next
    j    pf_try                  # 冲突 → 重试

pf_next:
    addi t2, t2, 1
    blt  t2, t1, pf_body_loop

    # ---- 检查是否在障碍物上 ----
    li t2, 0
pf_obs_loop:
    li t1, 8
    bge  t2, t1, pf_store
    slli t3, t2, 2
    add  t6, s6, t3
    lw   a0, 0(t6)
    add  t6, s7, t3
    lw   a1, 0(t6)
    bne  t4, a0, pf_obs_next
    bne  t5, a1, pf_obs_next
    j    pf_try
pf_obs_next:
    addi t2, t2, 1
    j    pf_obs_loop

    # ---- 存储并绘制食物 ----
pf_store:
    sw   t4, 0x10(s4)
    sw   t5, 0x14(s4)
    add  a0, t5, x0
    add  a1, t4, x0
    li a2, 0xE2A
    jal  ra, write_char

    lw   ra, 0(sp)
    addi sp, sp, 4
    jalr x0, ra, 0

# ==============================================================================
# place_obstacles — 随机放置障碍物
# ==============================================================================
place_obstacles:
    addi sp, sp, -4
    sw   ra, 0(sp)

    li t6, 0
po_try:
po_x_gen:
    jal  ra, lfsr_rand
    andi t0, t0, 0x7F
    li t1, 78
    bge  t0, t1, po_x_gen
    addi t4, t0, 1

po_y_gen:
    jal  ra, lfsr_rand
    andi t0, t0, 0x3F
    li t1, 56
    bge  t0, t1, po_y_gen
    addi t5, t0, 2

    # 避开蛇身
    lw   t1, 0x8(s4)
    lw   t0, 0x0(s4)
    sub  t0, t0, t1
    addi t0, t0, 1
    li t2, 0
po_snake_loop:
    add  t3, t0, t2
    andi t3, t3, 0x1FF
    slli t3, t3, 2
    add  a3, s2, t3
    lw   a0, 0(a3)
    add  a3, s3, t3
    lw   a1, 0(a3)
    bne  t4, a0, po_snake_next
    bne  t5, a1, po_snake_next
    j    po_try
po_snake_next:
    addi t2, t2, 1
    blt  t2, t1, po_snake_loop

    # 避开已有障碍
    li t2, 0
po_obs_loop:
    beq  t2, t6, po_store
    slli t3, t2, 2
    add  a3, s6, t3
    lw   a0, 0(a3)
    add  a3, s7, t3
    lw   a1, 0(a3)
    bne  t4, a0, po_obs_next
    bne  t5, a1, po_obs_next
    j    po_try
po_obs_next:
    addi t2, t2, 1
    j    po_obs_loop

po_store:
    slli t3, t6, 2
    add  a3, s6, t3
    sw   t4, 0(a3)
    add  a3, s7, t3
    sw   t5, 0(a3)

    add  a0, t5, x0
    add  a1, t4, x0
    li a2, 0xC23
    jal  ra, write_char

    addi t6, t6, 1
    li t0, 8
    blt  t6, t0, po_try

    lw   ra, 0(sp)
    addi sp, sp, 4
    jalr x0, ra, 0

# ==============================================================================
# lfsr_rand — 16-bit LFSR 伪随机数发生器
# ==============================================================================
# 反馈多项式: x^16 + x^15 + x^14 + x^13 + x^4 + 1
# (抽头: bits 15, 14, 13, 4, 0 — bit0=被移出的最低位)
# 返回: t0 = 新的 16-bit 随机值
# 注: bit[0] 参与反馈是 x^0 常数项, 保证最大周期 65535
lfsr_rand:
    lw   t0, 0x1C(s4)

    # new_bit = lfsr[15] ^ lfsr[14] ^ lfsr[13] ^ lfsr[4]
    srli t1, t0, 15
    srli t2, t0, 14
    andi t2, t2, 1
    xor  t1, t1, t2

    srli t2, t0, 13
    andi t2, t2, 1
    xor  t1, t1, t2

    srli t2, t0, 4
    andi t2, t2, 1
    xor  t1, t1, t2

    andi t2, t0, 1               # bit[0] (x^0 常数项, 参与反馈保证最大周期)
    xor  t1, t1, t2

    srli t0, t0, 1
    slli t1, t1, 15
    or   t0, t0, t1

    bnez t0, lfsr_save
    li t0, 0x3A5C          # 防零保护

lfsr_save:
    sw   t0, 0x1C(s4)
    jalr x0, ra, 0

# ==============================================================================
# draw_score — 已禁用（顶部不显示文字）
# ==============================================================================
draw_score:
    jalr x0, ra, 0

# ==============================================================================
# draw_paused / clear_paused — 暂停提示
# ==============================================================================
draw_paused:
    addi sp, sp, -4
    sw   ra, 0(sp)
    li a0, 0
    li a1, 28
    li a2, 0xE50
    jal  ra, write_char
    li a1, 29
    li a2, 0xE41
    jal  ra, write_char
    li a1, 30
    li a2, 0xE55
    jal  ra, write_char
    li a1, 31
    li a2, 0xE53
    jal  ra, write_char
    li a1, 32
    li a2, 0xE45
    jal  ra, write_char
    li a1, 33
    li a2, 0xE44
    jal  ra, write_char
    lw   ra, 0(sp)
    addi sp, sp, 4
    jalr x0, ra, 0

clear_paused:
    addi sp, sp, -4
    sw   ra, 0(sp)
    li a0, 0
    li a2, 0x20
    li a1, 28
    jal  ra, write_char
    li a1, 29
    jal  ra, write_char
    li a1, 30
    jal  ra, write_char
    li a1, 31
    jal  ra, write_char
    li a1, 32
    jal  ra, write_char
    li a1, 33
    jal  ra, write_char
    lw   ra, 0(sp)
    addi sp, sp, 4
    jalr x0, ra, 0

# ==============================================================================
# draw_help — 底边框操作提示
# ==============================================================================
draw_help:
    addi sp, sp, -4
    sw   ra, 0(sp)
    li a0, 59
    li a1, 28
    li a2, 0xE42
    jal  ra, write_char
    li a1, 29
    li a2, 0xE54
    jal  ra, write_char
    li a1, 30
    li a2, 0xE4E
    jal  ra, write_char
    li a1, 31
    li a2, 0xE32
    jal  ra, write_char
    li a1, 32
    li a2, 0xE20
    jal  ra, write_char
    li a1, 33
    li a2, 0xE50
    jal  ra, write_char
    li a1, 34
    li a2, 0xE41
    jal  ra, write_char
    li a1, 35
    li a2, 0xE55
    jal  ra, write_char
    li a1, 36
    li a2, 0xE53
    jal  ra, write_char
    li a1, 37
    li a2, 0xE45
    jal  ra, write_char
    li a1, 38
    li a2, 0xE20
    jal  ra, write_char
    li a1, 39
    li a2, 0xE48
    jal  ra, write_char
    li a1, 40
    li a2, 0xE4F
    jal  ra, write_char
    li a1, 41
    li a2, 0xE4C
    jal  ra, write_char
    li a1, 42
    li a2, 0xE44
    jal  ra, write_char
    li a1, 43
    li a2, 0xE20
    jal  ra, write_char
    li a1, 44
    li a2, 0xE52
    jal  ra, write_char
    li a1, 45
    li a2, 0xE45
    jal  ra, write_char
    li a1, 46
    li a2, 0xE53
    jal  ra, write_char
    li a1, 47
    li a2, 0xE45
    jal  ra, write_char
    li a1, 48
    li a2, 0xE54
    jal  ra, write_char
    lw   ra, 0(sp)
    addi sp, sp, 4
    jalr x0, ra, 0

# ==============================================================================
# write_char — 向 VGA 帧缓冲写入一个字符
# ==============================================================================
# 参数: a0=row (0~59), a1=col (0~79), a2=VGA字 (16-bit)
# 地址: VGA_BASE + 2*(row*80 + col) = s0 + 偏移
write_char:
    # 偏移 = 2 * (row*80 + col)
    li   t1, 80
    mul  t0, a0, t1              # t0 = row * 80
    add  t0, t0, a1              # t0 = row*80 + col
    slli t0, t0, 1               # t0 = 2 * (row*80 + col) = 字节偏移
    add  t0, s0, t0              # t0 = VGA 帧缓冲字节地址

    sh   a2, 0(t0)               # 写入 16-bit VGA 字符单元
    jalr x0, ra, 0

# ==============================================================================
# clear_screen — 清屏 (填充空格)
# ==============================================================================
clear_screen:
    li t0, 0               # 字节偏移 (0~9598, 步长2)
    li t1, 9600            # 4800 * 2
    li t3, 0x20            # 空格字符 (在循环外预加载, 节省4800次li)
cs_loop:
    add  t2, s0, t0              # VGA 地址
    sh   t3, 0(t2)
    addi t0, t0, 2
    blt  t0, t1, cs_loop
    jalr x0, ra, 0

# ==============================================================================
# draw_border — 绘制游戏边界
# ==============================================================================
draw_border:
    addi sp, sp, -4
    sw   ra, 0(sp)

    jal  ra, draw_help

    lw   ra, 0(sp)
    addi sp, sp, 4
    jalr x0, ra, 0

# ==============================================================================
# game_delay — 游戏延迟循环 (随分数增加而加速)
# ==============================================================================
game_delay:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   t0, 4(sp)

    lw   t2, 0x28(s4)
    slli t2, t2, 4
    li t0, 0x320
    sub  t0, t0, t2
    li t3, 0x100
    blt  t3, t0, gd_outer
    add  t0, t3, x0
gd_outer:
    li t1, 0x4B0
gd_inner:
    addi t1, t1, -1
    bnez t1, gd_inner
    addi t0, t0, -1
    bnez t0, gd_outer

    lw   t0, 4(sp)
    lw   ra, 0(sp)
    addi sp, sp, 8
    jalr x0, ra, 0

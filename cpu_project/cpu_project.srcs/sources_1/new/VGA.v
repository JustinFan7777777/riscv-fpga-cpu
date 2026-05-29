// =============================================================================
// Module      : VGA.v
// Description : VGA 文本模式显示控制器 — 80列×30行，8×16像素字符，640×480@60Hz
// =============================================================================
//
// ================================ 中文说明 ================================
// 【功能】VGA 文本模式显示控制器，输出 640×480@60Hz 模拟 VGA 信号。
//         内嵌 128 字符 × 8×16 像素的字模 ROM（分布式 RAM，组合逻辑读出），
//         通过外部帧缓冲 BRAM（位于 DataMemory.v 中，双端口）读取待显示字符
//         的 ASCII 码和颜色属性。
//
// 【在项目中的位置】
//   DataMemory(帧缓冲Port B) ──(fb_data)──▶ VGA ──▶ vga_hs, vga_vs
//                                           │         vga_r[3:0]
//                                           │         vga_g[3:0]
//                                           └──────── vga_b[3:0]
//   VGA ──(fb_addr)──▶ DataMemory(帧缓冲Port B)
//
// 【显示规格】
//   分辨率:     640×480@60Hz
//   像素时钟:   25MHz (100MHz / 4, 来自 TopDebug 的 clk_div[1])
//   字符网格:   80 列 × 30 行
//   字符大小:   8×16 像素
//   帧缓冲:     2400 × 16-bit (4800 字节)
//               [7:0]   = ASCII 码 (低7位有效, 128字符)
//               [11:8]  = 前景色 (I+R+G+B, 共16色)
//               [15:12] = 背景色 (I+R+G+B, 共16色)
//
// 【VGA 时序参数 (640×480@60Hz, 25MHz 像素时钟)】
//   水平时序:
//     H_ACTIVE=640  H_FRONT=16  H_SYNC=96  H_BACK=48  H_TOTAL=800
//   垂直时序:
//     V_ACTIVE=480  V_FRONT=10  V_SYNC=2   V_BACK=33  V_TOTAL=525
//
//   注意: 标准 VGA 640×480@60Hz 需要 25.175MHz 像素时钟。
//         本项目使用 25MHz (100MHz/4), 误差仅 0.7%, 兼容绝大多数显示器。
//
// 【像素输出流水线 (2 级流水, 合计 1 周期延迟)】
//   第 0 级 (组合逻辑): h_cnt/v_cnt → fb_addr (提前 2 像素预取)
//   第 1 级 (寄存器):    fb_data 锁存 → 字模 ROM 组合读出 → 取像素 bit → 着色
//
//   fb_addr 在每字符倒数第 2 个像素 (h_cnt[2:0]==6) 时切换到下一个字符,
//   保证 BRAM 读出数据在第 0 号像素到达。每行首个字符在水平消隐期预取。
//
// 【字模 ROM (font_rom)】
//   分布式 RAM (LUT), 2048 × 8-bit:
//     地址 = {ascii[6:0], row_in_char[3:0]}
//     ascii  = 7-bit 字符编码 (0~127)
//     row_in_char = 当前扫描行在字符内的行号 (0~15)
//   数据由 $readmemh 从 font_rom.hex 加载, 每字符 16 行, 共 128 字符。
//
// 【颜色属性编码】
//   前景色 char_data[11:8]:  [11]=亮度I  [10]=R  [9]=G  [8]=B
//   背景色 char_data[15:12]: [15]=亮度I  [14]=R  [13]=G  [12]=B
//   每个 VGA 通道 4-bit 输出:
//     R[3:0] = {R, R, R, I}  (例如 亮红=I+R=1011→14, 暗红=0010→4)
//   共 16 种前景色 × 16 种背景色 = 256 种颜色组合。
//
// 【跨时钟域】
//   VGA 使用 25MHz 像素时钟 (clk_pix), 帧缓冲的 CPU 写入端使用 12.5MHz。
//   双端口 BRAM (位于 DataMemory.v) 的 Port A 和 Port B 分别使用独立时钟,
//   天然支持跨时钟域操作, 无需额外同步逻辑。
//
// 【输入/输出端口】
//   A) 时钟和复位
//   B) 帧缓冲读口: fb_addr(输出地址) → fb_data(输入数据)
//   C) VGA 物理信号: vga_hs, vga_vs, vga_r[3:0], vga_g[3:0], vga_b[3:0]
// =============================================================================
`timescale 1ns / 1ps

module VGA #(
    // ===== 显示参数 (可配置, 但通常保持默认) =====
    parameter H_ACTIVE = 10'd640,   // 水平有效像素
    parameter H_FRONT  = 10'd16,    // 水平前沿 (front porch)
    parameter H_SYNC   = 10'd96,    // 水平同步脉冲宽度
    parameter H_BACK   = 10'd48,    // 水平后沿 (back porch)
    parameter H_TOTAL  = 10'd800,   // 水平总像素 (640+16+96+48)

    parameter V_ACTIVE = 10'd480,   // 垂直有效行
    parameter V_FRONT  = 10'd10,    // 垂直前沿
    parameter V_SYNC   = 10'd2,     // 垂直同步脉冲宽度
    parameter V_BACK   = 10'd33,    // 垂直后沿
    parameter V_TOTAL  = 10'd525,   // 垂直总行数 (480+10+2+33)

    // 字符网格
    parameter CHAR_W   = 4'd8,      // 字符宽度 (像素, 8需要4-bit)
    parameter CHAR_H   = 5'd16,     // 字符高度 (像素, 16需要5-bit)
    parameter COLS     = 7'd80,     // 列数
    parameter ROWS     = 5'd30,     // 行数

    // 字模 ROM 初始化文件路径
    // 路径相对于本 Verilog 源文件所在目录: ../../../../other/vga/font_rom.hex
    //   ../ = sources_1/  →  ../../ = cpu_project.srcs/  →  ../../../ = cpu_project/
    //   ../../../../ = 仓库根目录  →  other/vga/font_rom.hex
    parameter FONT_FILE = "../../../../other/vga/font_rom.hex"
)(
    // ===== 时钟和复位 =====
    input         clk_pix,         // 25MHz 像素时钟 (来自 TopDebug 的 clk_div[1] + BUFG)
    input         rst_n,           // 异步复位 (低有效)

    // ===== 帧缓冲读口 (连接 DataMemory.v 内的双端口 BRAM Port B) =====
    output [11:0] fb_addr,         // 帧缓冲字地址 (0~2399, 对应 80×30 字符网格)
    input  [15:0] fb_data,         // 帧缓冲读数据: [7:0]=ASCII, [15:8]=颜色属性

    // ===== VGA 物理输出 =====
    output        vga_hs,          // 水平同步 (低有效脉冲)
    output        vga_vs,          // 垂直同步 (低有效脉冲)
    output [3:0]  vga_r,           // 红色通道 (4-bit)
    output [3:0]  vga_g,           // 绿色通道 (4-bit)
    output [3:0]  vga_b            // 蓝色通道 (4-bit)
);

    // ==========================================================================
    // fb_addr 预取时序常量 (由模块参数派生, 避免硬编码魔法数字)
    // ==========================================================================
    localparam H_PREFETCH      = H_TOTAL - 3;  // 797 — 行末预取触发点 (字模BRAM需额外1拍)
    localparam CHAR_SWITCH_PIX = CHAR_W - 3;   // 5   — 字符切换触发像素 (提前3像素预取)
    localparam CHAR_LAST_PIX   = CHAR_W - 1;   // 7   — 字符内最后像素

    // ==========================================================================
    // 第 1 部分 — 水平/垂直像素计数器
    // ==========================================================================
    // h_cnt: 0 → H_TOTAL-1 (800), 循环计数
    // v_cnt: 0 → V_TOTAL-1 (525), 在 h_cnt 回绕时递增
    // 这两个计数器构成了 VGA 时序的"心跳", 所有其他信号都由此派生。
    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                // 水平回绕: h_cnt 归零, v_cnt 递增
                h_cnt <= 10'd0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 10'd0;    // 垂直回绕: 一帧结束, 从头开始
                else
                    v_cnt <= v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    // ==========================================================================
    // 第 2 部分 — VGA 同步信号 (组合逻辑)
    // ==========================================================================
    // hsync: 水平同步脉冲, h_cnt 在 [H_ACTIVE+H_FRONT, H_ACTIVE+H_FRONT+H_SYNC) 区间为低
    // vsync: 垂直同步脉冲, v_cnt 在 [V_ACTIVE+V_FRONT, V_ACTIVE+V_FRONT+V_SYNC) 区间为低
    assign vga_hs = (h_cnt >= (H_ACTIVE + H_FRONT) && h_cnt < (H_ACTIVE + H_FRONT + H_SYNC)) ? 1'b0 : 1'b1;
    assign vga_vs = (v_cnt >= (V_ACTIVE + V_FRONT) && v_cnt < (V_ACTIVE + V_FRONT + V_SYNC)) ? 1'b0 : 1'b1;

    // 有效显示区域标志
    wire in_display;
    assign in_display = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

    // ==========================================================================
    // 第 3 部分 — 字模 ROM (BRAM, 寄存器读出)
    // ==========================================================================
    // 128 个 ASCII 字符 × 16 行/字符 = 2048 个 8-bit 条目
    // 使用 BRAM 实现 (ram_style="block"), 节省 LUT 资源 (避免 LUT-as-Memory 耗尽)。
    // BRAM 读延迟为 1 周期, 需在像素流水线中额外延迟 1 拍补偿。
    // 地址映射: font_rom[{ascii[6:0], row_in_char[3:0]}] → 该字符第 row_in_char 行的 8-bit 位图
    (* ram_style = "block" *)
    reg [7:0] font_rom [0:2047];

    // ---- 从 hex 文件加载字模数据 ----
    initial begin
        if (FONT_FILE != "")
            $readmemh(FONT_FILE, font_rom);
    end

    // ==========================================================================
    // 第 4 部分 — 帧缓冲预取流水线 (3 级流水)
    // ==========================================================================
    // 设计思路:
    //   DataMemory 帧缓冲 BRAM 读延迟 = 1 周期 (寄存器输出),
    //   字模 ROM 为 BRAM (ram_style="block"), 读延迟 = 1 周期,
    //   总流水延迟 = 2 周期。
    //
    //   为了在每个字符的第 0 个像素就有正确的像素数据:
    //     - 在当前字符的第 5 个像素 (h_cnt[2:0]==5) 时,
    //       将 fb_addr 切换到下一个字符的地址
    //     - 1 周期后 fb_data 到达 → 字模 ROM 地址设置
    //     - 再 1 周期后 font_data 到达 → 像素输出
    //
    //   每行首个字符的 fb_addr 在水平消隐期 (h_cnt==797) 预取,
    //   确保新行开始 (h_cnt==0) 时已有数据。
    //
    //   流水寄存器:
    //     char_data:    fb_data 锁存 (1 周期延迟)
    //     font_data:    字模 ROM 读出锁存 (2 周期延迟)
    //     h_d1/v_d1:   延迟 1 拍 (字模 ROM 地址阶段)
    //     h_d2/v_d2:   延迟 2 拍 (像素输出阶段)

    reg [11:0] fb_addr_reg;      // fb_addr 输出寄存器
    reg [15:0] char_data;        // 锁存的帧缓冲数据 (ASCII + 颜色), 1 周期延迟
    reg [7:0]  font_data;        // 锁存的字模位图行, 2 周期延迟
    reg [9:0]  h_d1,  v_d1;     // 延迟 1 拍的计数器 (字模 ROM 地址阶段)
    reg [9:0]  h_d2,  v_d2;     // 延迟 2 拍的计数器 (像素输出阶段)

    assign fb_addr = fb_addr_reg;

    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            fb_addr_reg <= 12'd0;
            char_data    <= 16'd0;
            font_data    <= 8'd0;
            h_d1         <= 10'd0;
            v_d1         <= 10'd0;
            h_d2         <= 10'd0;
            v_d2         <= 10'd0;
        end else begin
            // ---- 第 1 级: 锁存 BRAM 读出数据 (帧缓冲 → char_data) ----
            char_data <= fb_data;

            // ---- 第 2 级: 字模 ROM 读出 (BRAM, 1 周期延迟) ----
            font_data <= font_rom[{char_data[6:0], v_d1[3:0]}];

            // ---- 延迟计数器: 用于像素输出阶段, 与 char_data / font_data 对齐 ----
            h_d1 <= h_cnt;
            v_d1 <= v_cnt;
            h_d2 <= h_d1;
            v_d2 <= v_d1;

            // ---- fb_addr 预取控制 ----
            // 情况 1: 水平消隐末期 (h_cnt==798), 预取当前行首字符
            //         (h_cnt==799→0 时 v_cnt 递增, 所以需要提前指向新行)
            if (h_cnt == H_PREFETCH) begin
                if (v_cnt < (V_ACTIVE - 1)) begin
                    // 不是最后一行: 指向下一行的第 0 列
                    // v_cnt 即将递增为 v_cnt+1, 新字符行号 = (v_cnt+1) >> 4
                    // 只有当 v_cnt[3:0]==15 (字符行边界) 时才进入下一字符行,
                    // 其余 15 条扫描线保持在同一字符行内。
                    fb_addr_reg <= ((v_cnt[3:0] == 4'd15)
                                    ? (v_cnt[9:4] + 5'd1)   // 字符行边界 → 下一行
                                    : v_cnt[9:4])            // 同字符行内 → 不动
                                   * COLS + 7'd0;
                end else begin
                    // 最后一行或垂直消隐: 回到第 0 行第 0 列 (准备下一帧)
                    fb_addr_reg <= 12'd0;
                end
            end
            // 情况 2: 当前字符的倒数第 2 个像素 (h_cnt[2:0]==6),
            //         切换到下一个字符的帧缓冲地址
            //         限制: 仅在有效显示区域 (h<640, v<480) 内更新
            else if (h_cnt[2:0] == CHAR_SWITCH_PIX && h_cnt < H_ACTIVE && v_cnt < V_ACTIVE) begin
                if (h_cnt[9:3] == (COLS - 1)) begin
                    // 当前已是最后一列: 指向同行的第 0 列
                    // (实际显示时已进入消隐, 不会用到此数据)
                    fb_addr_reg <= v_cnt[9:4] * COLS + 7'd0;
                end else begin
                    // 正常情况: 指向同一行的下一个字符列
                    fb_addr_reg <= v_cnt[9:4] * COLS + (h_cnt[9:3] + 7'd1);
                end
            end
        end
    end

    // ==========================================================================
    // 第 5 部分 — 像素生成 (组合逻辑)
    // ==========================================================================
    // font_data 是字模 ROM (BRAM) 的寄存器输出, 在 always 块中已锁存:
    //   font_data <= font_rom[{char_data[6:0], v_d1[3:0]}]
    // 使用延迟 2 拍的计数器 (h_d2, v_d2) 与 font_data 对齐。
    //
    // 流程:
    //   1. font_data 包含当前字符当前扫描行的 8-bit 位图 (已注册)
    //   2. 用 h_d2[2:0] 选择位图中的具体 bit (bit7=最左, bit0=最右)
    //   3. 若该 bit=1 → 输出前景色; 若 bit=0 → 输出背景色
    //   4. 若在消隐期 ((h_d2 >= 640) 或 (v_d2 >= 480)) → 输出全 0 (黑屏)

    // 提取前景色 / 背景色字段
    wire [3:0] fg_color;   // [3]=I  [2]=R  [1]=G  [0]=B
    wire [3:0] bg_color;   // 同上
    assign fg_color = char_data[11:8];
    assign bg_color = char_data[15:12];

    // 空白帧缓冲单元默认显示为黑色背景（之前为白色）
    wire screen_default_white;
    assign screen_default_white = 1'b0;

    // 当前像素在字符内的水平位置 (0=最左, 7=最右)
    // 注: 数据路径 (fb_addr→BRAM→char_data→font_rom→font_data) 比计数器路径
    // (h_cnt→h_d1→h_d2) 多 1 拍延迟, 需 +2 补偿像素对齐 (3-bit 自动 wrap)
    wire [2:0] pix_x;
    assign pix_x = h_d2[2:0] + 3'd2;

    // 从已注册的位图中取出对应 bit (bit7 对应 pix_x=0)
    wire pixel_on;
    assign pixel_on = font_data[CHAR_LAST_PIX - pix_x];

    // ---- 生成 4-bit RGB 通道输出 ----
    // 颜色扩展: 将 1-bit 通道色 + 1-bit 亮度 扩展为 4-bit 输出
    // 公式: 4-bit通道 = {通道色×3, 亮度}  (bit[3]=亮度, bit[2:0]=通道色)
    wire in_active;
    assign in_active = (h_d2 < H_ACTIVE) && (v_d2 < V_ACTIVE);

    // 预计算前景/背景各通道的 4-bit 值 (消除三通道间复制粘贴)
    wire [3:0] fg_r, fg_g, fg_b, bg_r, bg_g, bg_b;
    assign fg_r = {fg_color[2], fg_color[2], fg_color[2], fg_color[3]};
    assign fg_g = {fg_color[1], fg_color[1], fg_color[1], fg_color[3]};
    assign fg_b = {fg_color[0], fg_color[0], fg_color[0], fg_color[3]};
    assign bg_r = {bg_color[2], bg_color[2], bg_color[2], bg_color[3]};
    assign bg_g = {bg_color[1], bg_color[1], bg_color[1], bg_color[3]};
    assign bg_b = {bg_color[0], bg_color[0], bg_color[0], bg_color[3]};

    assign vga_r = in_active ? (screen_default_white ? 4'hF : (pixel_on ? fg_r : bg_r)) : 4'd0;
    assign vga_g = in_active ? (screen_default_white ? 4'hF : (pixel_on ? fg_g : bg_g)) : 4'd0;
    assign vga_b = in_active ? (screen_default_white ? 4'hF : (pixel_on ? fg_b : bg_b)) : 4'd0;

endmodule

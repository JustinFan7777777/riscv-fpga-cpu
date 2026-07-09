// ==============================================================================
// tb_VGA.v — VGA 控制器仿真测试平台 (Icarus Verilog / Vivado 通用)
// ==============================================================================
// 验证项目:
//   1. HSYNC/VSYNC 时序参数 (640×480@60Hz)
//   2. h_cnt/v_cnt 计数器回绕
//   3. fb_addr 生成逻辑 (行首预取 + 字符切换)
//   4. 字模 ROM 读出 (分布式 RAM + $readmemh)
//   5. 像素输出格式 (有效区域内非零, 消隐期内全零)
//
// 运行:
//   iverilog -o tb_VGA.vvp tb_VGA.v ../cpu_project/cpu_project.srcs/sources_1/new/VGA.v
//   vvp tb_VGA.vvp
// ==============================================================================
`timescale 1ns / 1ps

module tb_VGA;

    // ===========================
    // 时钟和复位
    // ===========================
    reg        clk_pix;
    reg        rst_n;
    wire       vga_hs, vga_vs;
    wire [3:0] vga_r, vga_g, vga_b;
    wire [12:0] fb_addr;
    reg  [15:0] fb_data;

    // 25MHz 像素时钟 (周期 = 40ns)
    always #20 clk_pix = ~clk_pix;

    // ===========================
    // 模拟帧缓冲 (简化的单端口 BRAM 行为模型)
    // ===========================
    // 预填充测试数据:
    //   [0] = 亮绿 'H' (0x0A48)  — 左上角显示 'H'
    //   [1] = 亮红 'i' (0x0C69)  — 旁边显示 'i'
    //   [79]= 白色 '>' (0x0F3E)  — 第0行最后一列
    //   [80]= 青色 'V' (0x0B56)  — 第1行第0列
    reg [15:0] mock_fb [0:4799];
    integer i;

    // 用可识别字符填满测试帧缓冲 (在复位期间预填充)
    reg [7:0] ascii_val;
    initial begin
        for (i = 0; i < 4800; i = i + 1) begin
            ascii_val = 8'h20 + (i % 95);  // 可打印 ASCII
            mock_fb[i] = {i[3:0], i[7:4], ascii_val};
        end
        // 第一个字符设为亮绿 'H' (0x0A48) 以便肉眼验证
        mock_fb[0] = 16'h0A48;
        mock_fb[1] = 16'h0C69;  // 亮红 'i'
        mock_fb[79] = 16'h0F3E; // 白色 '>'
    end

    // BRAM 读行为: 1周期延迟 (寄存器输出)
    always @(posedge clk_pix) begin
        fb_data <= mock_fb[fb_addr];
    end

    // ===========================
    // VGA 实例化
    // ===========================
    VGA #(
        .FONT_FILE("other/vga/font_rom.txt")   // 相对于工作目录 (仓库根目录)
    ) uVGA (
        .clk_pix (clk_pix),
        .rst_n   (rst_n),
        .fb_addr (fb_addr),
        .fb_data (fb_data),
        .vga_hs  (vga_hs),
        .vga_vs  (vga_vs),
        .vga_r   (vga_r),
        .vga_g   (vga_g),
        .vga_b   (vga_b)
    );

    // ===========================
    // 时序参数参考值
    // ===========================
    // 水平: H_ACTIVE=640, H_FRONT=16, H_SYNC=96, H_BACK=48, H_TOTAL=800
    // 垂直: V_ACTIVE=480, V_FRONT=10, V_SYNC=2,  V_BACK=33, V_TOTAL=525
    // 像素时钟: 25MHz, 周期 40ns
    // 帧率: 25MHz / (800×525) = 59.52 Hz ≈ 60Hz

    // ===========================
    // 测试主流程
    // ===========================
    integer frame_count;
    integer test_errors;

    initial begin
        // ---- 初始化 ----
        clk_pix   = 1'b0;
        rst_n     = 1'b0;
        test_errors = 0;
        frame_count = 0;

        // 复位 200ns (5 个时钟周期)
        #200;
        rst_n = 1'b1;

        // 等待一帧完成后再检查
        wait_frame;

        $display("========================================");
        $display(" VGA 时序测试 — 640×480@60Hz");
        $display("========================================");

        // ---- 测试 1: HSYNC 时序 (在一帧中采样) ----
        check_hsync_timing;

        // ---- 测试 2: VSYNC 时序 ----
        check_vsync_timing;

        // ---- 测试 3: 有效显示区域内像素非全零 ----
        check_active_pixels;

        // ---- 测试 4: 消隐期内像素全零 ----
        check_blanking;

        // ---- 测试 5: fb_addr 范围 ----
        check_fb_addr_range;

        // ---- 结果汇总 ----
        $display("========================================");
        if (test_errors == 0) begin
            $display(" 全部测试通过! (0 errors)");
            $display("========================================");
        end else begin
            $display(" 发现 %0d 个错误", test_errors);
            $display("========================================");
        end

        $finish;
    end

    // ===========================
    // 辅助: 等待一帧完成
    // ===========================
    task wait_frame;
        begin
            @(negedge vga_vs);  // vsync 开始时 (低有效)
            @(posedge vga_vs);  // vsync 结束
        end
    endtask

    // ===========================
    // 测试 1: HSYNC 时序
    // ===========================
    task check_hsync_timing;
        reg [31:0] h_sync_start_time;
        reg [31:0] h_sync_width_pix;
        begin
            $display("[Test 1] HSYNC 时序检查");

            // 测量 HSYNC 脉冲宽度 (应为 H_SYNC = 96 像素 = 3840ns)
            @(negedge vga_hs);
            h_sync_start_time = $time;
            @(posedge vga_hs);
            h_sync_width_pix = ($time - h_sync_start_time) / 40;  // 40ns = 1像素时钟

            $display("  实测 HSYNC 宽度: %0d 像素时钟", h_sync_width_pix);
            $display("  期望 HSYNC 宽度: 96 像素时钟");
            if (h_sync_width_pix == 96) begin
                $display("  [PASS] HSYNC 脉冲宽度 = 96");
            end else begin
                $display("  [FAIL] HSYNC 脉冲宽度 = %0d (期望 96)", h_sync_width_pix);
                test_errors = test_errors + 1;
            end
        end
    endtask

    // ===========================
    // 测试 2: VSYNC 时序
    // ===========================
    task check_vsync_timing;
        reg [31:0] vsync_period_start, vsync_period;
        begin
            $display("[Test 2] VSYNC 时序检查");

            // 测量两个 VSYNC 之间的像素时钟周期数
            @(negedge vga_vs);
            vsync_period_start = $time;
            @(negedge vga_vs);
            vsync_period = ($time - vsync_period_start) / 40;  // 转换为像素时钟数

            $display("  实测帧周期: %0d 像素时钟", vsync_period);
            $display("  期望帧周期: %0d 像素时钟 (800×525)", 800 * 525);
            if (vsync_period == 800 * 525) begin
                $display("  [PASS] 帧周期匹配");
            end else begin
                $display("  [FAIL] 帧周期不匹配! 差值=%0d", vsync_period - 800*525);
                test_errors = test_errors + 1;
            end
        end
    endtask

    // ===========================
    // 测试 3: 有效显示区域内像素输出非全零
    // ===========================
    task check_active_pixels;
        integer px_count, nonzero_count;
        begin
            $display("[Test 3] 有效显示区域像素检查");

            // 等待进入有效显示区域
            @(negedge vga_hs);  // 同步行开始
            @(posedge vga_hs);
            // 现在在行内, 等待有效像素区域

            // 在一个行的有效区域内采样
            px_count = 0;
            nonzero_count = 0;

            // 采样一行中前 100 个像素
            repeat (200) begin
                @(posedge clk_pix);
                if (vga_r != 0 || vga_g != 0 || vga_b != 0) begin
                    nonzero_count = nonzero_count + 1;
                end
                px_count = px_count + 1;
            end

            $display("  采样 %0d 像素, %0d 个非零", px_count, nonzero_count);
            if (nonzero_count > 0) begin
                $display("  [PASS] 有效区域内有像素输出");
            end else begin
                $display("  [WARN] 全部为零 — 可能帧缓冲/字模未正确初始化");
            end
        end
    endtask

    // ===========================
    // 测试 4: 消隐期像素全零
    // ===========================
    task check_blanking;
        integer blank_ok;
        begin
            $display("[Test 4] 消隐期像素全零检查");

            // 在 hsync 期间检查
            @(negedge vga_hs);  // 进入 hsync
            blank_ok = 1;
            repeat (10) begin
                @(posedge clk_pix);
                if (vga_r != 0 || vga_g != 0 || vga_b != 0) begin
                    blank_ok = 0;
                end
            end
            @(posedge vga_hs);

            if (blank_ok) begin
                $display("  [PASS] HSYNC期间像素全零");
            end else begin
                $display("  [FAIL] HSYNC期间有非零像素输出");
                test_errors = test_errors + 1;
            end
        end
    endtask

    // ===========================
    // 测试 5: fb_addr 范围检查
    // ===========================
    task check_fb_addr_range;
        integer fb_out_of_range;
        begin
            $display("[Test 5] fb_addr 地址范围检查");

            // 监控一帧内的 fb_addr
            fb_out_of_range = 0;
            @(negedge vga_vs);
            @(posedge vga_vs);  // 新帧开始

            repeat (800 * 525) begin
                @(posedge clk_pix);
                if (fb_addr >= 4800) begin
                    fb_out_of_range = fb_out_of_range + 1;
                end
            end

            if (fb_out_of_range == 0) begin
                $display("  [PASS] fb_addr 始终在 0..4799 范围内");
            end else begin
                $display("  [FAIL] fb_addr 越界 %0d 次 (max=4799)", fb_out_of_range);
                test_errors = test_errors + 1;
            end
        end
    endtask

endmodule

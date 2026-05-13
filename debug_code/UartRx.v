// -----------------------------------------------------------------------------
// Module      : UartRx.v
// Author      : Yuhui Bai
// Description : UART receiver
// -----------------------------------------------------------------------------
//
// ================================ 中文说明 ================================
// 【功能】UART 接收器 —— 把 Host（上位机）发来的串口数据转成 8-bit 并行字节。
//
// 【在项目中的角色】
//   Host（上位机）---(USB转串口)---> UartRx ---(rx_data, rx_valid)---> DebugController
//   UartRx 负责把串口线上一比特一比特过来的数据"拼"成完整的命令字节，
//   然后交给 DebugController 去解析和执行。
//
// 【数据帧格式】
//   1 起始位(低电平) + 8 数据位(LSB 优先) + 1 停止位(高电平)
//   无校验位。波特率 115200，系统时钟 100MHz。
//
// 【关键设计】
//   1. 两级触发器同步(rx_sync1→rx_sync2)：消除外部异步 RX 引脚的亚稳态。
//   2. 半 bit 二次确认：检测到下降沿后，先等半个 bit 周期再确认是否还是
//      低电平。如果是毛刺而非真正的起始位，就退回 IDLE，大幅提高抗干扰。
//   3. 中点采样：确认起始位有效后，每个数据 bit 都在 bit 周期的正中间采样
//      （即等完整个 bit 周期再采），这是离两边边沿最远的稳定点。
//   4. rx_valid 是单周期脉冲：收到一个完整字节后拉高一个 clk 周期，
//      正好对接 DebugController 的握手协议。
//
// 【参数(Parameter)】
//   CLK_FREQ = 100_000_000 (系统时钟)
//   BAUD     = 115200       (波特率)
//   自动计算：每个 bit 持续 CLK_FREQ/BAUD ≈ 868 个时钟周期。
//
// 【接口信号】
//   输入: clk, rst_n, rx_pin(UART接收引脚)
//   输出: rx_data[7:0](收到的字节), rx_valid(单周期有效脉冲)
// ========================================================================
`timescale 1ns / 1ps

module UartRx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input       clk,
    input       rst_n,
    input       rx_pin,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;
    localparam HALF_BIT     = CLKS_PER_BIT / 2;

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  rx_shift;
    reg        rx_sync1, rx_sync2;

    // Double flip-flop sync to remove metastability
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx_pin;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            rx_shift <= 0;
            rx_data  <= 0;
            rx_valid <= 0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (rx_sync2 == 1'b0) begin
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (clk_cnt == HALF_BIT - 1) begin
                        if (rx_sync2 == 1'b0) begin
                            clk_cnt <= 0;
                            state   <= S_DATA;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        rx_shift[bit_idx] <= rx_sync2;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_data  <= rx_shift;
                        rx_valid <= 1'b1;
                        state    <= S_IDLE;
                        clk_cnt  <= 0;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

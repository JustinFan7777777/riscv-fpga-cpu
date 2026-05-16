// -----------------------------------------------------------------------------
// Module      : UartTx.v
// Author      : Yuhui Bai
// Description : UART transmitter
// -----------------------------------------------------------------------------
//
// ================================ 中文说明 ================================
// 【功能】UART 发送器 —— 把 8-bit 并行字节转成串口数据发回给 Host（上位机）。
//
// 【在项目中的角色】
//   DebugController ---(tx_data, tx_start)---> UartTx ---(USB转串口)---> Host（上位机）
//   DebugController 处理好命令后把响应数据交给 UartTx，UartTx 负责"拆"
//   成串行 bit 流发给 Host（上位机）。
//
// 【数据帧格式】
//   1 起始位(低电平) + 8 数据位(LSB 优先) + 1 停止位(高电平)
//   无校验位。波特率 115200，系统时钟 100MHz。
//
// 【关键设计】
//   1. tx_busy 握手：一旦开始发送就拉高 tx_busy，stop bit 结束后才拉低。
//      上位机(DebugController)通过检查 !tx_busy 来判断是否可以发下一字节。
//   2. LSB first：tx_shift[bit_idx] 按 bit 0→1→...→7 的顺序依次输出，
//      即最先送出的是 tx_data[0]（最低位），最后是 tx_data[7]（最高位）。
//   3. 空闲高电平：空闲时 tx_pin 保持高电平(1)，start bit 拉低(0)，
//      stop bit 拉高(1)，完全符合标准 UART 协议。
//
// 【参数(Parameter)】
//   CLK_FREQ = 100_000_000 (系统时钟)
//   BAUD     = 115200       (波特率)
//   每个 bit 持续 CLK_FREQ/BAUD ≈ 868 个时钟周期。
//
// 【接口信号】
//   输入: clk, rst_n, tx_data[7:0](要发送的字节), tx_start(启动脉冲)
//   输出: tx_pin(UART发送引脚), tx_busy(忙碌标志，1=发送中 0=空闲)
// ========================================================================
`timescale 1ns / 1ps

module UartTx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input       clk,
    input       rst_n,
    input [7:0] tx_data,
    input       tx_start,
    output reg        tx_busy,
    output reg        tx_pin
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD;

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  tx_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            tx_shift <= 0;
            tx_busy  <= 1'b0;
            tx_pin   <= 1'b1;
        end else begin
            case (state)
                S_IDLE: begin
                    tx_pin  <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (tx_start) begin
                        tx_shift <= tx_data;
                        tx_busy  <= 1'b1;
                        state    <= S_START;
                    end
                end

                S_START: begin
                    tx_pin <= 1'b0; // start bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    tx_pin <= tx_shift[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
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
                    tx_pin <= 1'b1; // stop bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        tx_busy <= 1'b0;
                        state   <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

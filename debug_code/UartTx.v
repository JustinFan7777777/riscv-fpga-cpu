// -----------------------------------------------------------------------------
// Module      : UartTx.v
// Author      : Yuhui Bai
// Description : UART transmitter
// -----------------------------------------------------------------------------
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

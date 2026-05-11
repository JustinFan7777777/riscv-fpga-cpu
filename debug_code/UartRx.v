// -----------------------------------------------------------------------------
// Module      : UartRx.v
// Author      : Yuhui Bai
// Description : UART receiver
// -----------------------------------------------------------------------------
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

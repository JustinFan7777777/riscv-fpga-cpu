// -----------------------------------------------------------------------------
// Module      : DebugController.v
// Author      : Yuhui Bai
// Description : Debug UART command controller
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module DebugController (
    input        clk,       // 100MHz system clock
    input        rst_n,      // Active-low reset

    // UART interface
    input [7:0]  rx_data,
    input        rx_valid,
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input        tx_busy,

    // CPU control
    output reg         cpu_halt,
    output reg         cpu_step,      // Single-step pulse signal
    output reg         cpu_reset,

    // Debug: register read
    output reg  [4:0]  dbg_reg_addr,
    input [31:0] dbg_reg_data,

    // Debug: instruction memory
    output reg         inst_dbg_en,    // 1=debug access
    output reg         inst_wr_en,     // 1=write enable
    output reg  [31:0] inst_dbg_addr,  // byte address
    output reg  [31:0] inst_wr_data,   // write data
    input [31:0] inst_rd_data,   // read data (instruction)

    // Debug: data memory
    output reg         dmem_dbg_en,    // 1=debug access
    output reg         dmem_wr_en,     // 1=write enable
    output reg  [31:0] dmem_dbg_addr,  // byte address
    output reg  [31:0] dmem_wr_data,   // write data
    input [31:0] dmem_rd_data,   // read data

    // Debug: PC
    input [31:0] dbg_pc
);

    // ================================
    // Command code definitions
    // ================================
    localparam CMD_PING       = 8'h00;
    localparam CMD_RESET      = 8'h01;
    localparam CMD_RUN        = 8'h02;
    localparam CMD_HALT       = 8'h03;
    localparam CMD_STEP       = 8'h04;    // Single-step
    localparam CMD_READ_REG   = 8'h21;
    localparam CMD_READ_PC    = 8'h22;
    localparam CMD_READ_INST  = 8'h23;
    localparam CMD_READ_DMEM  = 8'h24;
    localparam CMD_WRITE_INST = 8'h40;
    localparam CMD_WRITE_DMEM = 8'h41;

    // Response code definitions
    localparam RESP_PONG   = 8'h80;
    localparam RESP_ACK    = 8'h81;
    localparam RESP_DATA32 = 8'h82;
    localparam RESP_ERR    = 8'hFF;

    // ================================
    // State machine
    // ================================
    localparam S_IDLE         = 4'd0;
    localparam S_RECV_PAYLOAD = 4'd1;
    localparam S_EXECUTE      = 4'd2;
    localparam S_SEND_RESP    = 4'd3;
    localparam S_SEND_WAIT    = 4'd4;
    localparam S_MEM_WAIT     = 4'd5;

    reg [3:0]  state;
    reg [7:0]  cmd_reg;
    reg [3:0]  payload_cnt;      // received payload bytes
    reg [3:0]  payload_need;     // needed payload bytes
    reg [7:0]  payload [0:7];    // payload buffer (max 8 bytes: WRITE_INST addr[4]+data[4])
    reg [3:0]  step_countdown;   // Step counter: multiple cycles to cover one 25MHz period

    reg [31:0] resp_data;        // 32-bit data to send
    reg [2:0]  resp_len;         // response total length (incl. code)
    reg [2:0]  resp_idx;         // current send byte index
    reg [7:0]  resp_buf [0:4];   // response buffer

    // Memory read wait counter (cross clock domain: 100MHz → 25MHz uram)
    // uram at 25MHz needs 1 cycle to output data = 4 cycles at 100MHz
    // Write needs signal stable for at least one full 25MHz rising edge, use 20 cycles for margin
    localparam MEM_WAIT_CYCLES = 5'd20;
    localparam STEP_COUNTDOWN_INIT = 4'd4;  // Step pulse width (100MHz cycles), adjust to cover one 25MHz period
    reg [4:0]  mem_wait_cnt;

    // Get payload length for each command
    function [3:0] cmd_payload_len;
        input [7:0] cmd;
        begin
            case (cmd)
                CMD_PING:       cmd_payload_len = 0;
                CMD_RESET:      cmd_payload_len = 0;
                CMD_RUN:        cmd_payload_len = 0;
                CMD_HALT:       cmd_payload_len = 0;
                CMD_STEP:       cmd_payload_len = 0;  // Single-step
                CMD_READ_REG:   cmd_payload_len = 1;  // regnum[1B]
                CMD_READ_PC:    cmd_payload_len = 0;
                CMD_READ_INST:  cmd_payload_len = 4;  // addr[4B]
                CMD_READ_DMEM:  cmd_payload_len = 4;  // addr[4B]
                CMD_WRITE_INST: cmd_payload_len = 8;  // addr[4B] + data[4B]
                CMD_WRITE_DMEM: cmd_payload_len = 8;  // addr[4B] + data[4B]
                default:        cmd_payload_len = 0;
            endcase
        end
    endfunction

    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            cmd_reg      <= 0;
            payload_cnt  <= 0;
            payload_need <= 0;
            cpu_halt     <= 1'b0;
            cpu_step     <= 1'b0;
            step_countdown <= 4'b0000;
            cpu_reset    <= 1'b0;
            dbg_reg_addr <= 0;
            inst_dbg_en  <= 0;
            inst_wr_en   <= 0;
            inst_dbg_addr <= 0;
            inst_wr_data <= 0;
            dmem_dbg_en  <= 0;
            dmem_wr_en   <= 0;
            dmem_dbg_addr <= 0;
            dmem_wr_data <= 0;
            mem_wait_cnt <= 0;
            tx_data      <= 0;
            tx_start     <= 0;
            resp_len     <= 0;
            resp_idx     <= 0;
        end else begin
            tx_start    <= 1'b0;
            cpu_reset   <= 1'b0;
            inst_dbg_en  <= 1'b0;
            inst_wr_en   <= 1'b0;
            dmem_dbg_en  <= 1'b0;
            dmem_wr_en   <= 1'b0;
            
            // cpu_step logic:
            // If not halt mode, allow CPU to run normally (cpu_step=1)
            // If halt and step_countdown > 0, allow single-step (cpu_step=1)
            // Otherwise pause CPU (cpu_step=0)
            if (!cpu_halt) begin
                cpu_step <= 1'b1;  // Normal run mode
            end else if (step_countdown > 0) begin
                cpu_step <= 1'b1;  // Single-step pulse
                step_countdown <= step_countdown - 1;  // Countdown
            end else begin
                cpu_step <= 1'b0;  // Pause mode
            end

            case (state)
                // =============================================================
                S_IDLE: begin
                    if (rx_valid) begin
                        cmd_reg      <= rx_data;
                        payload_need <= cmd_payload_len(rx_data);
                        payload_cnt  <= 0;
                        if (cmd_payload_len(rx_data) == 0) begin
                            state <= S_EXECUTE;
                        end else begin
                            state <= S_RECV_PAYLOAD;
                        end
                    end
                end

                // =============================================================
                S_RECV_PAYLOAD: begin
                    if (rx_valid) begin
                        payload[payload_cnt] <= rx_data;
                        if (payload_cnt + 1 == payload_need) begin
                            state <= S_EXECUTE;
                        end
                        payload_cnt <= payload_cnt + 1;
                    end
                end

                // =============================================================
                S_EXECUTE: begin
                    case (cmd_reg)
                        CMD_PING: begin
                            resp_buf[0] <= RESP_PONG;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_RESET: begin
                            cpu_halt    <= 1'b1;
                            cpu_reset   <= 1'b1;
                            step_countdown <= 4'b0000;    // Clear step
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_RUN: begin
                            cpu_halt    <= 1'b0;
                            step_countdown <= 4'b0000;    // Clear step
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_HALT: begin
                            cpu_halt    <= 1'b1;
                            step_countdown <= 4'b0000;    // Clear step
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_STEP: begin
                            cpu_halt    <= 1'b1;    // Keep paused
                            step_countdown <= STEP_COUNTDOWN_INIT;    // Use parameterized step pulse width
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_READ_REG: begin
                            dbg_reg_addr <= payload[0][4:0];
                            // Register is combinational read, but still need to wait for cross-clock domain stability
                            mem_wait_cnt <= MEM_WAIT_CYCLES;
                            state        <= S_MEM_WAIT;
                        end

                        CMD_READ_PC: begin
                            resp_buf[0] <= RESP_DATA32;
                            resp_buf[1] <= dbg_pc[31:24];
                            resp_buf[2] <= dbg_pc[23:16];
                            resp_buf[3] <= dbg_pc[15:8];
                            resp_buf[4] <= dbg_pc[7:0];
                            resp_len    <= 5;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end

                        CMD_READ_INST: begin
                            inst_dbg_addr <= {payload[0], payload[1], payload[2], payload[3]};
                            inst_dbg_en   <= 1'b1;
                            inst_wr_en    <= 1'b0;
                            mem_wait_cnt  <= MEM_WAIT_CYCLES;
                            state         <= S_MEM_WAIT;
                        end

                        CMD_WRITE_INST: begin
                            inst_dbg_addr <= {payload[0], payload[1], payload[2], payload[3]};
                            inst_wr_data  <= {payload[4], payload[5], payload[6], payload[7]};
                            inst_dbg_en   <= 1'b1;
                            inst_wr_en    <= 1'b1;
                            mem_wait_cnt  <= MEM_WAIT_CYCLES;
                            state         <= S_MEM_WAIT;
                        end

                        CMD_READ_DMEM: begin
                            dmem_dbg_addr <= {payload[0], payload[1], payload[2], payload[3]};
                            dmem_dbg_en   <= 1'b1;
                            dmem_wr_en    <= 1'b0;
                            mem_wait_cnt  <= MEM_WAIT_CYCLES;
                            state         <= S_MEM_WAIT;
                        end

                        CMD_WRITE_DMEM: begin
                            dmem_dbg_addr <= {payload[0], payload[1], payload[2], payload[3]};
                            dmem_wr_data  <= {payload[4], payload[5], payload[6], payload[7]};
                            dmem_dbg_en   <= 1'b1;
                            dmem_wr_en    <= 1'b1;
                            mem_wait_cnt  <= MEM_WAIT_CYCLES;
                            state         <= S_MEM_WAIT;
                        end

                        default: begin
                            resp_buf[0] <= RESP_ERR;
                            resp_buf[1] <= 8'h01; // unknown command
                            resp_len    <= 2;
                            resp_idx    <= 0;
                            state       <= S_SEND_RESP;
                        end
                    endcase
                end

                // =============================================================
                // Wait for memory/register read result (multi-cycle delay, cross clock domain)
                S_MEM_WAIT: begin
                    // Keep signal high, override default clear
                    if (cmd_reg == CMD_READ_INST || cmd_reg == CMD_WRITE_INST) begin
                        inst_dbg_en <= 1'b1;
                        if (cmd_reg == CMD_WRITE_INST)
                            inst_wr_en <= 1'b1;
                    end
                    if (cmd_reg == CMD_READ_DMEM || cmd_reg == CMD_WRITE_DMEM) begin
                        dmem_dbg_en <= 1'b1;
                        if (cmd_reg == CMD_WRITE_DMEM)
                            dmem_wr_en <= 1'b1;
                    end

                    if (mem_wait_cnt > 0) begin
                        mem_wait_cnt <= mem_wait_cnt - 1;
                    end else begin
                        // Wait done, sample data or finish write
                        if (cmd_reg == CMD_READ_REG) begin
                            resp_buf[0] <= RESP_DATA32;
                            resp_buf[1] <= dbg_reg_data[31:24];
                            resp_buf[2] <= dbg_reg_data[23:16];
                            resp_buf[3] <= dbg_reg_data[15:8];
                            resp_buf[4] <= dbg_reg_data[7:0];
                            resp_len    <= 5;
                            resp_idx    <= 0;
                        end else if (cmd_reg == CMD_READ_INST) begin
                            resp_buf[0] <= RESP_DATA32;
                            resp_buf[1] <= inst_rd_data[31:24];
                            resp_buf[2] <= inst_rd_data[23:16];
                            resp_buf[3] <= inst_rd_data[15:8];
                            resp_buf[4] <= inst_rd_data[7:0];
                            resp_len    <= 5;
                            resp_idx    <= 0;
                        end else if (cmd_reg == CMD_WRITE_INST) begin
                            inst_wr_en  <= 1'b0;
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                        end else if (cmd_reg == CMD_READ_DMEM) begin
                            resp_buf[0] <= RESP_DATA32;
                            resp_buf[1] <= dmem_rd_data[31:24];
                            resp_buf[2] <= dmem_rd_data[23:16];
                            resp_buf[3] <= dmem_rd_data[15:8];
                            resp_buf[4] <= dmem_rd_data[7:0];
                            resp_len    <= 5;
                            resp_idx    <= 0;
                        end else if (cmd_reg == CMD_WRITE_DMEM) begin
                            dmem_wr_en  <= 1'b0;
                            resp_buf[0] <= RESP_ACK;
                            resp_len    <= 1;
                            resp_idx    <= 0;
                        end
                        state <= S_SEND_RESP;
                    end
                end

                // =============================================================
                S_SEND_RESP: begin
                    if (!tx_busy) begin
                        tx_data  <= resp_buf[resp_idx];
                        tx_start <= 1'b1;
                        state    <= S_SEND_WAIT;
                    end
                end

                // =============================================================
                S_SEND_WAIT: begin
                    // Wait for current byte to finish sending
                    if (!tx_busy && !tx_start) begin
                        if (resp_idx + 1 == resp_len) begin
                            state <= S_IDLE;
                        end else begin
                            resp_idx <= resp_idx + 1;
                            state    <= S_SEND_RESP;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`timescale 1ns / 1ps

module tb_debug_controller_reset;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] rx_data = 8'd0;
    reg rx_valid = 1'b0;

    wire [7:0] tx_data;
    wire tx_start;
    wire cpu_halt, cpu_step, cpu_reset;
    wire [4:0] dbg_reg_addr;
    wire inst_dbg_en, inst_wr_en, dmem_dbg_en, dmem_wr_en;
    wire [31:0] inst_dbg_addr, inst_wr_data, dmem_dbg_addr, dmem_wr_data;

    always #5 clk = ~clk;

    DebugController u_debug (
        .clk(clk), .rst_n(rst_n),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .tx_data(tx_data), .tx_start(tx_start), .tx_busy(1'b0),
        .cpu_halt(cpu_halt), .cpu_step(cpu_step), .cpu_reset(cpu_reset),
        .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(32'd0),
        .inst_dbg_en(inst_dbg_en), .inst_wr_en(inst_wr_en),
        .inst_dbg_addr(inst_dbg_addr), .inst_wr_data(inst_wr_data),
        .inst_rd_data(32'd0),
        .dmem_dbg_en(dmem_dbg_en), .dmem_wr_en(dmem_wr_en),
        .dmem_dbg_addr(dmem_dbg_addr), .dmem_wr_data(dmem_wr_data),
        .dmem_rd_data(32'd0),
        .dbg_pc(32'h00004000)
    );

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk); #1;

        if (cpu_halt !== 1'b0)
            $fatal(1, "DebugController must run after physical reset");
        if (cpu_step !== 1'b1)
            $fatal(1, "DebugController must step continuously while running");

        @(negedge clk);
        rx_data = 8'h01;  // CMD_RESET
        rx_valid = 1'b1;
        @(negedge clk);
        rx_valid = 1'b0;
        repeat (3) @(posedge clk); #1;

        if (cpu_halt !== 1'b1)
            $fatal(1, "UART RESET command must leave CPU halted");
        if (cpu_step !== 1'b0)
            $fatal(1, "DebugController must not step after UART RESET");

        $display("DEBUG_CONTROLLER_RESET PASS");
        $finish;
    end
endmodule

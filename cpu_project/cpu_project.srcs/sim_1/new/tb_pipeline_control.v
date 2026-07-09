`timescale 1ns / 1ps

module tb_pipeline_control;
    reg clk = 1'b0;
    reg clk_vga = 1'b0;
    reg rst_n = 1'b0;
    reg cpu_halt = 1'b0;
    reg cpu_step = 1'b0;
    reg cpu_reset = 1'b0;

    wire [31:0] dbg_reg_data, inst_rd_data, dmem_rd_data, dbg_pc;
    wire [15:0] LEDOut, vga_fb_data;
    wire [7:0] seg_cs, seg_data_0, seg_data_1;

    always #5 clk = ~clk;
    always #10 clk_vga = ~clk_vga;

    CPUTopPipeline u_pipe (
        .clk(clk), .rst_n(rst_n),
        .cpu_halt(cpu_halt), .cpu_step(cpu_step), .cpu_reset(cpu_reset),
        .dbg_reg_addr(5'd0), .dbg_reg_data(dbg_reg_data),
        .inst_dbg_en(1'b0), .inst_wr_en(1'b0),
        .inst_dbg_addr(32'd0), .inst_wr_data(32'd0), .inst_rd_data(inst_rd_data),
        .dmem_dbg_en(1'b0), .dmem_wr_en(1'b0),
        .dmem_dbg_addr(32'd0), .dmem_wr_data(32'd0), .dmem_rd_data(dmem_rd_data),
        .dbg_pc(dbg_pc),
        .SwitchIn(16'd0), .ButtonIn(5'd0), .SeedIn(1'b0),
        .LEDOut(LEDOut), .seg_cs(seg_cs),
        .seg_data_0(seg_data_0), .seg_data_1(seg_data_1),
        .clk_vga(clk_vga), .vga_fb_addr(13'd0), .vga_fb_data(vga_fb_data)
    );

    reg [31:0] pc_hold, ifid_hold, idex_hold, exmem_hold, memwb_hold;

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        cpu_halt = 1'b1;
        @(posedge clk); #1;
        pc_hold    = dbg_pc;
        ifid_hold  = u_pipe.uPipeRegs.ifid_inst;
        idex_hold  = {u_pipe.uPipeRegs.idex_regwrite, u_pipe.uPipeRegs.idex_memwrite,
                      u_pipe.uPipeRegs.idex_rd_addr, u_pipe.uPipeRegs.idex_pc[24:0]};
        exmem_hold = {u_pipe.uPipeRegs.exmem_regwrite, u_pipe.uPipeRegs.exmem_memwrite,
                      u_pipe.uPipeRegs.exmem_rd_addr, u_pipe.uPipeRegs.exmem_aluresult[24:0]};
        memwb_hold = {u_pipe.uPipeRegs.memwb_regwrite, u_pipe.uPipeRegs.memwb_memtoreg,
                      u_pipe.uPipeRegs.memwb_rd_addr, u_pipe.uPipeRegs.memwb_aluresult[24:0]};

        repeat (5) @(posedge clk); #1;
        if (dbg_pc !== pc_hold ||
            u_pipe.uPipeRegs.ifid_inst !== ifid_hold ||
            {u_pipe.uPipeRegs.idex_regwrite, u_pipe.uPipeRegs.idex_memwrite,
             u_pipe.uPipeRegs.idex_rd_addr, u_pipe.uPipeRegs.idex_pc[24:0]} !== idex_hold ||
            {u_pipe.uPipeRegs.exmem_regwrite, u_pipe.uPipeRegs.exmem_memwrite,
             u_pipe.uPipeRegs.exmem_rd_addr, u_pipe.uPipeRegs.exmem_aluresult[24:0]} !== exmem_hold ||
            {u_pipe.uPipeRegs.memwb_regwrite, u_pipe.uPipeRegs.memwb_memtoreg,
             u_pipe.uPipeRegs.memwb_rd_addr, u_pipe.uPipeRegs.memwb_aluresult[24:0]} !== memwb_hold) begin
            $fatal(1, "pipeline changed while halted");
        end

        cpu_reset = 1'b1;
        @(posedge clk); #1;
        cpu_reset = 1'b0;
        if (dbg_pc !== 32'h00004000)
            $fatal(1, "pipeline reset did not restore PC");

        $display("PIPELINE_CONTROL PASS");
        $finish;
    end
endmodule

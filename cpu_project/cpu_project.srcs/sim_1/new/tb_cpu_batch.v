`timescale 1ns / 1ps

module tb_cpu_batch;
    reg clk = 1'b0;
    reg clk_vga = 1'b0;
    reg rst_n = 1'b0;

    wire [31:0] single_dbg_reg, single_inst_rd, single_dmem_rd, single_pc;
    wire [15:0] single_led;
    wire [7:0] single_seg_cs, single_seg0, single_seg1;
    wire [15:0] single_vga_fb;

    wire [31:0] pipe_dbg_reg, pipe_inst_rd, pipe_dmem_rd, pipe_pc;
    wire [15:0] pipe_led;
    wire [7:0] pipe_seg_cs, pipe_seg0, pipe_seg1;
    wire [15:0] pipe_vga_fb;

    integer pass_count = 0;
    integer fail_count = 0;

    always #5 clk = ~clk;
    always #10 clk_vga = ~clk_vga;

    CPUTop u_single (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_halt(1'b0),
        .cpu_step(1'b0),
        .cpu_reset(1'b0),
        .dbg_reg_addr(5'd0),
        .dbg_reg_data(single_dbg_reg),
        .inst_dbg_en(1'b0),
        .inst_wr_en(1'b0),
        .inst_dbg_addr(32'd0),
        .inst_wr_data(32'd0),
        .inst_rd_data(single_inst_rd),
        .dmem_dbg_en(1'b0),
        .dmem_wr_en(1'b0),
        .dmem_dbg_addr(32'd0),
        .dmem_wr_data(32'd0),
        .dmem_rd_data(single_dmem_rd),
        .dbg_pc(single_pc),
        .SwitchIn(16'd0),
        .ButtonIn(5'd0),
        .LEDOut(single_led),
        .seg_cs(single_seg_cs),
        .seg_data_0(single_seg0),
        .seg_data_1(single_seg1),
        .clk_vga(clk_vga),
        .vga_fb_addr(12'd0),
        .vga_fb_data(single_vga_fb)
    );

    CPUTopPipeline u_pipe (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_halt(1'b0),
        .cpu_step(1'b0),
        .cpu_reset(1'b0),
        .dbg_reg_addr(5'd0),
        .dbg_reg_data(pipe_dbg_reg),
        .inst_dbg_en(1'b0),
        .inst_wr_en(1'b0),
        .inst_dbg_addr(32'd0),
        .inst_wr_data(32'd0),
        .inst_rd_data(pipe_inst_rd),
        .dmem_dbg_en(1'b0),
        .dmem_wr_en(1'b0),
        .dmem_dbg_addr(32'd0),
        .dmem_wr_data(32'd0),
        .dmem_rd_data(pipe_dmem_rd),
        .dbg_pc(pipe_pc),
        .SwitchIn(16'd0),
        .ButtonIn(5'd0),
        .LEDOut(pipe_led),
        .seg_cs(pipe_seg_cs),
        .seg_data_0(pipe_seg0),
        .seg_data_1(pipe_seg1),
        .clk_vga(clk_vga),
        .vga_fb_addr(12'd0),
        .vga_fb_data(pipe_vga_fb)
    );

    task run_case;
        input integer case_id;
        input [31:0] operand_a;
        input [31:0] operand_b;
        input [31:0] expected;
        integer cycles;
        begin
            rst_n = 1'b0;

            u_single.uDataMemory.mem[14'h1000] = case_id[31:0];
            u_single.uDataMemory.mem[14'h1001] = operand_a;
            u_single.uDataMemory.mem[14'h1002] = operand_b;
            u_single.uDataMemory.mem[14'h1003] = 32'hdead_beef;

            u_pipe.uDataMemory.mem[14'h1000] = case_id[31:0];
            u_pipe.uDataMemory.mem[14'h1001] = operand_a;
            u_pipe.uDataMemory.mem[14'h1002] = operand_b;
            u_pipe.uDataMemory.mem[14'h1003] = 32'hdead_beef;

            repeat (4) @(posedge clk);
            rst_n = 1'b1;

            cycles = 0;
            while (cycles < 20000 &&
                   (u_single.uDataMemory.mem[14'h1003] !== expected ||
                    u_pipe.uDataMemory.mem[14'h1003] !== expected)) begin
                @(posedge clk);
                cycles = cycles + 1;
            end

            if (u_single.uDataMemory.mem[14'h1003] === expected &&
                u_pipe.uDataMemory.mem[14'h1003] === expected) begin
                pass_count = pass_count + 1;
                $display("PASS case=%0d a=%h b=%h expected=%h cycles=%0d",
                         case_id, operand_a, operand_b, expected, cycles);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL case=%0d a=%h b=%h expected=%h single=%h pipe=%h",
                         case_id, operand_a, operand_b, expected,
                         u_single.uDataMemory.mem[14'h1003],
                         u_pipe.uDataMemory.mem[14'h1003]);
            end
        end
    endtask

    initial begin
        run_case(0, 32'h00000f0f, 32'h00001234, 32'h00000204);
        run_case(0, 32'hffffffff, 32'h00001234, 32'h00001234);
        run_case(1, 32'h12481248, 32'h00000004, 32'h24812480);
        run_case(1, 32'h00000001, 32'h0000002d, 32'h00002000);
        run_case(2, 32'h71240000, 32'h00000018, 32'h00000071);
        run_case(2, 32'h81231234, 32'h00000024, 32'hf8123123);
        run_case(3, 32'h10000000, 32'h00000000, 32'h22345000);
        run_case(3, 32'h00000001, 32'h00000000, 32'h12345001);
        run_case(4, 32'h00000000, 32'h00000000, 32'h12345000);
        run_case(4, 32'h00000010, 32'h00000000, 32'h12345010);
        run_case(5, 32'h00000005, 32'h00000006, 32'h0000000b);
        run_case(5, 32'h00000001, 32'h00000002, 32'h00000003);
        run_case(6, 32'h00000001, 32'h00000000, 32'h00000001);
        run_case(6, 32'h00000002, 32'h00000000, 32'h00000001);
        run_case(6, 32'h00000003, 32'h00000000, 32'h00000002);
        run_case(6, 32'h00000004, 32'h00000000, 32'h00000003);
        run_case(7, 32'h000000c1, 32'h00000000, 32'h00000003);
        run_case(7, 32'h000000f8, 32'h00000000, 32'h00000005);
        run_case(8, 32'h00008000, 32'h00000000, 32'h00000000);
        run_case(8, 32'h00000000, 32'h00000000, 32'h00000000);
        run_case(8, 32'h00007c00, 32'h00000000, 32'h00000001);
        run_case(8, 32'h0000fc00, 32'h00000000, 32'h00000001);
        run_case(8, 32'h0000fc01, 32'h00000000, 32'h00000002);
        run_case(8, 32'h00002026, 32'h00000000, 32'h00000003);
        run_case(8, 32'h0000c202, 32'h00000000, 32'h00000003);
        run_case(8, 32'h00000003, 32'h00000000, 32'h00000004);
        run_case(8, 32'h000080e1, 32'h00000000, 32'h00000004);
        run_case(9, 32'h00003c00, 32'h00000000, 32'h00000010);
        run_case(9, 32'h00003e00, 32'h00000000, 32'h00000018);
        run_case(9, 32'h00004200, 32'h00000000, 32'h00000030);
        run_case(9, 32'h0000c400, 32'h00000000, 32'h000000c0);
        run_case(9, 32'h00004240, 32'h00000000, 32'h00000032);
        run_case(9, 32'h0000bf00, 32'h00000000, 32'h000000e4);

        $display("RESULT pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count != 0)
            $fatal;
        $finish;
    end
endmodule

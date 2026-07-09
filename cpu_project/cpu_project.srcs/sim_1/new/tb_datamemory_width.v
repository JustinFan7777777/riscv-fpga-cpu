`timescale 1ns / 1ps

module tb_datamemory_width;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clk_vga = 1'b0;
    reg MemWrite = 1'b0;
    reg [2:0] MemFunct3 = 3'b010;
    reg [31:0] Addr = 32'd0;
    reg [31:0] WriteData = 32'd0;
    wire [31:0] ReadData;
    wire [15:0] LEDOut;
    wire [7:0] seg_cs, seg_data_0, seg_data_1;
    wire [31:0] dmem_rd_data;
    wire [15:0] vga_fb_data;
    reg dmem_dbg_en = 1'b0;
    reg dmem_wr_en = 1'b0;
    reg [31:0] dmem_dbg_addr = 32'd0;
    reg [31:0] dmem_wr_data = 32'd0;
    reg [12:0] vga_fb_addr = 13'd0;

    always #5 clk = ~clk;
    always #10 clk_vga = ~clk_vga;

    DataMemory dut (
        .clk(clk), .rst_n(rst_n), .clk_vga(clk_vga),
        .MemWrite(MemWrite), .MemFunct3(MemFunct3),
        .Addr(Addr), .WriteData(WriteData), .ReadData(ReadData),
        .SwitchIn(16'd0), .ButtonIn(5'd0), .SeedIn(1'b1),
        .LEDOut(LEDOut), .seg_cs(seg_cs),
        .seg_data_0(seg_data_0), .seg_data_1(seg_data_1),
        .dmem_dbg_en(dmem_dbg_en), .dmem_wr_en(dmem_wr_en),
        .dmem_dbg_addr(dmem_dbg_addr), .dmem_wr_data(dmem_wr_data),
        .dmem_rd_data(dmem_rd_data),
        .vga_fb_addr(vga_fb_addr), .vga_fb_data(vga_fb_data)
    );

    task store;
        input [31:0] addr;
        input [31:0] data;
        input [2:0] funct3;
        begin
            @(posedge clk);
            Addr = addr;
            WriteData = data;
            MemFunct3 = funct3;
            MemWrite = 1'b1;
            @(negedge clk);
            #1 MemWrite = 1'b0;
        end
    endtask

    task debug_vga_store_expect;
        input [31:0] addr;
        input [31:0] data;
        begin
            dmem_dbg_addr = addr;
            dmem_wr_data = data;
            dmem_dbg_en = 1'b1;
            dmem_wr_en = 1'b1;
            @(negedge clk);
            @(posedge clk);
            dmem_dbg_en = 1'b0;
            dmem_wr_en = 1'b0;
            vga_fb_addr = addr[13:1] - 13'd128;
            @(posedge clk_vga);
            @(posedge clk_vga);
            if (vga_fb_data !== data[15:0]) begin
                $display("FAIL debug VGA write got=%h expected=%h", vga_fb_data, data[15:0]);
                $finish;
            end
        end
    endtask

    task load_expect;
        input [31:0] addr;
        input [2:0] funct3;
        input [31:0] expected;
        begin
            @(posedge clk);
            Addr = addr;
            MemFunct3 = funct3;
            MemWrite = 1'b0;
            @(negedge clk);
            #1;
            if (ReadData !== expected) begin
                $display("FAIL addr=%h funct3=%b got=%h expected=%h", addr, funct3, ReadData, expected);
                $finish;
            end
        end
    endtask

    initial begin
        #12 rst_n = 1'b1;

        store(32'h0000_0000, 32'h80FF_7F01, 3'b010); // SW
        load_expect(32'h0000_0000, 3'b000, 32'h0000_0001); // LB
        load_expect(32'h0000_0001, 3'b000, 32'h0000_007F); // LB
        load_expect(32'h0000_0002, 3'b000, 32'hFFFF_FFFF); // LB
        load_expect(32'h0000_0003, 3'b000, 32'hFFFF_FF80); // LB
        load_expect(32'h0000_0002, 3'b100, 32'h0000_00FF); // LBU
        load_expect(32'h0000_0000, 3'b001, 32'h0000_7F01); // LH
        load_expect(32'h0000_0002, 3'b001, 32'hFFFF_80FF); // LH
        load_expect(32'h0000_0002, 3'b101, 32'h0000_80FF); // LHU

        store(32'h0000_0004, 32'h0000_0000, 3'b010); // SW
        store(32'h0000_0005, 32'h0000_00AA, 3'b000); // SB
        load_expect(32'h0000_0004, 3'b010, 32'h0000_AA00);
        store(32'h0000_0006, 32'h0000_BEEF, 3'b001); // SH
        load_expect(32'h0000_0004, 3'b010, 32'hBEEF_AA00);
        load_expect(32'hFFFF_0018, 3'b010, 32'h0000_0001);
        debug_vga_store_expect(32'hFFFF_0100, 32'h0000_0E2A);

        $display("tb_datamemory_width PASS");
        $finish;
    end
endmodule

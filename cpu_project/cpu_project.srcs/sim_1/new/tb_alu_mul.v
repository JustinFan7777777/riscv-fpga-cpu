`timescale 1ns / 1ps

module tb_alu_mul;
    reg [31:0] A;
    reg [31:0] B;
    reg [31:0] inst;
    reg [3:0] ALUControl;
    wire [31:0] ALUResult;
    wire [3:0] decoded_alucontrol;
    wire Zero;

    ALU dut (
        .A(A),
        .B(B),
        .ALUControl(ALUControl),
        .ALUResult(ALUResult),
        .Zero(Zero)
    );

    Decoder decoder (
        .inst(inst),
        .RegWrite(),
        .ALUSrc(),
        .MemtoReg(),
        .MemWrite(),
        .Branch(),
        .Jump(),
        .JALRSrc(),
        .ALUOp(),
        .ALUControl(decoded_alucontrol)
    );

    task expect_mul;
        input [31:0] a;
        input [31:0] b;
        input [31:0] expected;
        begin
            A = a;
            B = b;
            #1;
            if (ALUResult !== expected) begin
                $display("FAIL %h * %h got=%h expected=%h", a, b, ALUResult, expected);
                $finish;
            end
        end
    endtask

    initial begin
        ALUControl = 4'b1010;
        expect_mul(32'd7, 32'd6, 32'd42);
        expect_mul(32'hFFFF_FFFF, 32'd2, 32'hFFFF_FFFE);
        expect_mul(32'h0001_0000, 32'h0001_0000, 32'h0000_0000);

        inst = 32'h027302B3; #1; // mul t0,t1,t2
        if (decoded_alucontrol !== 4'b1010) begin
            $display("FAIL MUL decode got=%b", decoded_alucontrol);
            $finish;
        end
        inst = 32'h007302B3; #1; // add t0,t1,t2
        if (decoded_alucontrol !== 4'b0000) begin
            $display("FAIL ADD decode got=%b", decoded_alucontrol);
            $finish;
        end
        inst = 32'h407302B3; #1; // sub t0,t1,t2
        if (decoded_alucontrol !== 4'b0001) begin
            $display("FAIL SUB decode got=%b", decoded_alucontrol);
            $finish;
        end

        $display("tb_alu_mul PASS");
        $finish;
    end
endmodule

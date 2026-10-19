//-----------------------------------------------------------------------------
// File: tb_mac_unit.sv
// Module: tb_mac_unit
// Description: Unit testbench for the DSP MAC unit.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_mac_unit;

    logic clk;
    logic rst_n;
    logic en;
    logic clr;
    logic signed [7:0]  din_a;
    logic signed [7:0]  din_b;
    logic signed [31:0] din_c;
    logic signed [31:0] dout;

    mac_unit #(
        .DATA_WIDTH(8),
        .WEIGHT_WIDTH(8),
        .ACCUM_WIDTH(32)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .clr   (clr),
        .din_a (din_a),
        .din_b (din_b),
        .din_c (din_c),
        .dout  (dout)
    );

    always #5 clk = ~clk;

    int error_count = 0;

    initial begin
        clk   = 0;
        rst_n = 0;
        en    = 1;
        clr   = 0;
        din_a = 0;
        din_b = 0;
        din_c = 0;

        #20 rst_n = 1;
        #10;

        // Test case 1: 12 * 5 + 10 = 70
        @(posedge clk);
        din_a <= 8'sd12;
        din_b <= 8'sd5;
        din_c <= 32'sd10;

        // Pipeline latency is 3 cycles (reg_a/b -> mult_reg -> accum_reg)
        repeat(3) @(posedge clk);
        #1;
        if (dout !== 32'sd70) begin
            $display("ERROR: Test 1 failed! Expected 70, got %0d", dout);
            error_count++;
        end else begin
            $display("PASS: Test 1 (12*5 + 10 = %0d)", dout);
        end

        // Test case 2: -15 * 8 + 200 = 80
        @(posedge clk);
        din_a <= -8'sd15;
        din_b <= 8'sd8;
        din_c <= 32'sd200;

        repeat(3) @(posedge clk);
        #1;
        if (dout !== 32'sd80) begin
            $display("ERROR: Test 2 failed! Expected 80, got %0d", dout);
            error_count++;
        end else begin
            $display("PASS: Test 2 (-15*8 + 200 = %0d)", dout);
        end

        // Test case 3: Clear
        @(posedge clk);
        clr <= 1'b1;
        repeat(3) @(posedge clk);
        #1;
        if (dout !== 32'sd0) begin
            $display("ERROR: Test 3 Clear failed! Expected 0, got %0d", dout);
            error_count++;
        end else begin
            $display("PASS: Test 3 Clear verified (0)");
        end

        #20;
        if (error_count == 0) begin
            $display("========================================");
            $display(">>> ALL MAC UNIT TESTS PASSED! <<<");
            $display("========================================");
        end else begin
            $fatal(1, "MAC UNIT TESTS FAILED with %0d errors", error_count);
        end
        $finish;
    end

endmodule

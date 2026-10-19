//-----------------------------------------------------------------------------
// File: tb_maxpool.sv
// Module: tb_maxpool
// Description: Unit testbench for streaming 2x2 Max Pooling unit.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_maxpool;

    parameter int W = 4;
    parameter int H = 4;

    logic clk;
    logic rst_n;
    logic valid_in;
    logic signed [7:0] din;
    logic signed [7:0] dout;
    logic valid_out;

    maxpool_unit #(
        .DATA_WIDTH(8),
        .FEATURE_WIDTH(W),
        .FEATURE_HEIGHT(H)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (valid_in),
        .din       (din),
        .dout      (dout),
        .valid_out (valid_out)
    );

    always #5 clk = ~clk;

    // Test matrix (4x4):
    // [  1,  5,   2,  4 ]
    // [  9,  3,   8,  6 ] -> MaxPool 2x2 -> [ 9,  8 ]
    // [ 12, 15,  20, 18 ]                   [ 15, 25 ]
    // [ 14, 11,  25, 22 ]
    logic signed [7:0] test_img [0:15] = '{
        8'sd1,  8'sd5,  8'sd2,  8'sd4,
        8'sd9,  8'sd3,  8'sd8,  8'sd6,
        8'sd12, 8'sd15, 8'sd20, 8'sd18,
        8'sd14, 8'sd11, 8'sd25, 8'sd22
    };

    logic signed [7:0] expected_pooled [0:3] = '{
        8'sd9,  8'sd8,
        8'sd15, 8'sd25
    };

    int pooled_count = 0;
    int error_count = 0;

    initial begin
        clk = 0;
        rst_n = 0;
        valid_in = 0;
        din = 0;

        #20 rst_n = 1;
        #10;

        for (int i = 0; i < 16; i++) begin
            @(posedge clk);
            valid_in <= 1'b1;
            din      <= test_img[i];

            @(negedge clk);
            if (valid_out) begin
                $display("Pooled output #%0d: got %0d, expected %0d", 
                         pooled_count, dout, expected_pooled[pooled_count]);
                if (dout !== expected_pooled[pooled_count]) begin
                    $display("ERROR mismatch!");
                    error_count++;
                end
                pooled_count++;
            end
        end

        @(posedge clk);
        valid_in <= 1'b0;

        repeat(5) begin
            @(negedge clk);
            if (valid_out) begin
                $display("Pooled output #%0d: got %0d, expected %0d", 
                         pooled_count, dout, expected_pooled[pooled_count]);
                if (dout !== expected_pooled[pooled_count]) begin
                    $display("ERROR mismatch!");
                    error_count++;
                end
                pooled_count++;
            end
            @(posedge clk);
        end

        if (error_count == 0 && pooled_count == 4) begin
            $display("========================================");
            $display(">>> ALL MAXPOOL UNIT TESTS PASSED! <<<");
            $display("========================================");
        end else begin
            $fatal(1, "MAXPOOL TESTS FAILED! (Errors: %0d, Count: %0d)", error_count, pooled_count);
        end

        $finish;
    end

endmodule

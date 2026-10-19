//-----------------------------------------------------------------------------
// File: tb_line_buffer.sv
// Module: tb_line_buffer
// Description: Unit testbench for streaming 2D line buffer and 3x3 window generator.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tb_line_buffer;

    parameter int W = 8;
    parameter int H = 8;

    logic clk;
    logic rst_n;
    logic pixel_valid_in;
    logic signed [7:0] pixel_in;
    logic signed [7:0] window_out [0:2][0:2];
    logic window_valid_out;
    logic frame_done_out;

    line_buffer #(
        .DATA_WIDTH(8),
        .IMG_WIDTH(W),
        .IMG_HEIGHT(H)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .pixel_valid_in   (pixel_valid_in),
        .pixel_in         (pixel_in),
        .window_out       (window_out),
        .window_valid_out (window_valid_out),
        .frame_done_out   (frame_done_out)
    );

    always #5 clk = ~clk;

    int valid_window_count = 0;

    initial begin
        clk = 0;
        rst_n = 0;
        pixel_valid_in = 0;
        pixel_in = 0;

        #20 rst_n = 1;
        #10;

        $display("Streaming %0dx%0d image pixels...", W, H);

        for (int r = 0; r < H; r++) begin
            for (int c = 0; c < W; c++) begin
                @(posedge clk);
                pixel_valid_in <= 1'b1;
                // pixel value = row * 10 + col
                pixel_in <= (r * 10) + c;

                @(negedge clk);
                if (window_valid_out) begin
                    valid_window_count++;
                end
            end
        end

        @(posedge clk);
        pixel_valid_in <= 1'b0;

        // Drain any remaining cycles
        repeat(5) @(posedge clk);

        $display("Total valid windows captured = %0d", valid_window_count);
        $display("Expected valid windows for %0dx%0d valid conv = %0d", W, H, (W-2)*(H-2));

        if (valid_window_count >= (W-2)*(H-2)) begin
            $display("========================================");
            $display(">>> LINE BUFFER TESTS PASSED! <<<");
            $display("========================================");
        end else begin
            $fatal(1, "Line buffer did not produce expected number of windows!");
        end

        $finish;
    end

endmodule

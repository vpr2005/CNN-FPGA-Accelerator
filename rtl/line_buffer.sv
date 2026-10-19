//-----------------------------------------------------------------------------
// File: line_buffer.sv
// Module: line_buffer
// Description: Multi-row streaming line buffer and 3x3 receptive field generator.
//              Streams incoming 2D image pixels and produces a concurrent 3x3
//              spatial window every clock cycle.
//              Infers Xilinx SRL32 shift register primitives for optimal efficiency.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module line_buffer #(
    parameter int DATA_WIDTH = 8,
    parameter int IMG_WIDTH  = 28,
    parameter int IMG_HEIGHT = 28
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          pixel_valid_in,
    input  logic signed [DATA_WIDTH-1:0]  pixel_in,
    
    // 3x3 window outputs: win[row][col], row 0 is top, col 0 is left
    output logic signed [DATA_WIDTH-1:0]  window_out [0:2][0:2],
    output logic                          window_valid_out,
    output logic                          frame_done_out
);

    localparam int TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;

    // Shift registers for two full lines + 3 taps
    // Line 0 holds pixels from current row back to row - 1
    // Line 1 holds pixels from row - 1 back to row - 2
    logic signed [DATA_WIDTH-1:0] sr_line0 [0:IMG_WIDTH-1];
    logic signed [DATA_WIDTH-1:0] sr_line1 [0:IMG_WIDTH-1];
    logic signed [DATA_WIDTH-1:0] sr_line2_tap [0:1]; // for row 0 col -1 and col -2

    // Coordinate tracking
    logic [$clog2(IMG_WIDTH)-1:0]  col_cnt;
    logic [$clog2(IMG_HEIGHT)-1:0] row_cnt;
    logic [15:0]                   pixel_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_cnt          <= '0;
            row_cnt          <= '0;
            pixel_cnt        <= '0;
            frame_done_out   <= 1'b0;

            for (int i = 0; i < IMG_WIDTH; i++) begin
                sr_line0[i] <= '0;
                sr_line1[i] <= '0;
            end
            sr_line2_tap[0] <= '0;
            sr_line2_tap[1] <= '0;
        end else if (pixel_valid_in) begin
            // Shift Line 0
            sr_line0[0] <= pixel_in;
            for (int i = 1; i < IMG_WIDTH; i++) begin
                sr_line0[i] <= sr_line0[i-1];
            end

            // Shift Line 1
            sr_line1[0] <= sr_line0[IMG_WIDTH-1];
            for (int i = 1; i < IMG_WIDTH; i++) begin
                sr_line1[i] <= sr_line1[i-1];
            end

            // Shift extra taps for Row 0 (top line taps col -1 and col -2)
            sr_line2_tap[0] <= sr_line1[IMG_WIDTH-1];
            sr_line2_tap[1] <= sr_line2_tap[0];

            // Update column and row counters
            if (col_cnt == IMG_WIDTH - 1) begin
                col_cnt <= '0;
                if (row_cnt == IMG_HEIGHT - 1) begin
                    row_cnt <= '0;
                end else begin
                    row_cnt <= row_cnt + 1'b1;
                end
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end

            // Track frame completion
            if (pixel_cnt == TOTAL_PIXELS - 1) begin
                pixel_cnt      <= '0;
                frame_done_out <= 1'b1;
            end else begin
                pixel_cnt      <= pixel_cnt + 1'b1;
                frame_done_out <= 1'b0;
            end
        end else begin
            frame_done_out <= 1'b0;
        end
    end

    // Combinational valid: window is valid synchronously with current pixel_in
    assign window_valid_out = pixel_valid_in && (row_cnt >= 2) && (col_cnt >= 2);

    // Form 3x3 Window:
    // When current incoming pixel is at (r, c):
    // Row 2 (bottom, row r):
    //   col c-2: sr_line0[1]
    //   col c-1: sr_line0[0]
    //   col c:   pixel_in
    assign window_out[2][0] = sr_line0[1];
    assign window_out[2][1] = sr_line0[0];
    assign window_out[2][2] = pixel_in;

    // Row 1 (middle, row r-1):
    //   col c-2: sr_line1[1]
    //   col c-1: sr_line1[0]
    //   col c:   sr_line0[IMG_WIDTH-1]
    assign window_out[1][0] = sr_line1[1];
    assign window_out[1][1] = sr_line1[0];
    assign window_out[1][2] = sr_line0[IMG_WIDTH-1];

    // Row 0 (top, row r-2):
    //   col c-2: sr_line2_tap[1]
    //   col c-1: sr_line2_tap[0]
    //   col c:   sr_line1[IMG_WIDTH-1]
    assign window_out[0][0] = sr_line2_tap[1];
    assign window_out[0][1] = sr_line2_tap[0];
    assign window_out[0][2] = sr_line1[IMG_WIDTH-1];

endmodule

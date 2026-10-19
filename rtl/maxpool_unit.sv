//-----------------------------------------------------------------------------
// File: maxpool_unit.sv
// Module: maxpool_unit
// Description: Streaming 2x2 Max Pooling unit with Stride 2.
//              Utilizes an internal line buffer of size (WIDTH/2) to compute
//              2x2 spatial downsampling on-the-fly with minimal memory footprint.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module maxpool_unit #(
    parameter int DATA_WIDTH     = 8,
    parameter int FEATURE_WIDTH  = 28,
    parameter int FEATURE_HEIGHT = 28
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          valid_in,
    input  logic signed [DATA_WIDTH-1:0]  din,
    output logic signed [DATA_WIDTH-1:0]  dout,
    output logic                          valid_out
);

    localparam int OUT_WIDTH  = FEATURE_WIDTH / 2;
    localparam int OUT_HEIGHT = FEATURE_HEIGHT / 2;

    // Line buffer to store pairwise maximums from even rows
    logic signed [DATA_WIDTH-1:0] pool_line_buf [0:OUT_WIDTH-1];

    // Coordinate tracking
    logic [$clog2(FEATURE_WIDTH)-1:0]  col_cnt;
    logic [$clog2(FEATURE_HEIGHT)-1:0] row_cnt;

    // Registers to hold previous column sample
    logic signed [DATA_WIDTH-1:0] col_even_reg;
    logic signed [DATA_WIDTH-1:0] row0_max;
    logic signed [DATA_WIDTH-1:0] row1_max;
    logic signed [DATA_WIDTH-1:0] pooled_val;
    logic pooled_valid;

    // Coordinate counters
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_cnt <= '0;
            row_cnt <= '0;
        end else if (valid_in) begin
            if (col_cnt == FEATURE_WIDTH - 1) begin
                col_cnt <= '0;
                if (row_cnt == FEATURE_HEIGHT - 1) begin
                    row_cnt <= '0;
                end else begin
                    row_cnt <= row_cnt + 1'b1;
                end
            end else begin
                col_cnt <= col_cnt + 1'b1;
            end
        end
    end

    // Streaming 2x2 pooling state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_even_reg <= '0;
            pooled_val   <= '0;
            pooled_valid <= 1'b0;
        end else if (valid_in) begin
            if (col_cnt[0] == 1'b0) begin
                // Even column: latch pixel
                col_even_reg <= din;
                pooled_valid <= 1'b0;
            end else begin
                // Odd column: compute row max between (col_even_reg) and (din)
                logic signed [DATA_WIDTH-1:0] curr_row_max;
                curr_row_max = (din > col_even_reg) ? din : col_even_reg;

                if (row_cnt[0] == 1'b0) begin
                    // Even row: store into line buffer at (col_cnt / 2)
                    pool_line_buf[col_cnt >> 1] <= curr_row_max;
                    pooled_valid <= 1'b0;
                end else begin
                    // Odd row: read previous row max and take overall 2x2 max
                    logic signed [DATA_WIDTH-1:0] prev_row_max;
                    prev_row_max = pool_line_buf[col_cnt >> 1];

                    pooled_val   <= (curr_row_max > prev_row_max) ? curr_row_max : prev_row_max;
                    pooled_valid <= 1'b1;
                end
            end
        end else begin
            pooled_valid <= 1'b0;
        end
    end

    assign dout      = pooled_val;
    assign valid_out = pooled_valid;

endmodule

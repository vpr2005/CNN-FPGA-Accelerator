//-----------------------------------------------------------------------------
// File: relu_unit.sv
// Module: relu_unit
// Description: Pipelined Activation and Re-quantization unit.
//              Applies ReLU non-linearity, arithmetic right-shift (scaling),
//              and saturation clamping to INT8 range [0, 127].
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module relu_unit #(
    parameter int IN_WIDTH   = 32,
    parameter int OUT_WIDTH  = 8,
    parameter int SHIFT_BITS = 8
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          valid_in,
    input  logic signed [IN_WIDTH-1:0]    din,
    output logic signed [OUT_WIDTH-1:0]   dout,
    output logic                          valid_out
);

    logic signed [IN_WIDTH-1:0] relu_val;
    logic signed [IN_WIDTH-1:0] shifted_val;
    logic signed [OUT_WIDTH-1:0] clamped_val;
    logic valid_reg;

    always_comb begin
        // ReLU Activation
        if (din > 0) begin
            relu_val = din;
        end else begin
            relu_val = '0;
        end

        // Re-quantization scaling (Arithmetic Right Shift)
        shifted_val = relu_val >>> SHIFT_BITS;

        // Saturation clamping to 8-bit range [0, 127]
        if (shifted_val > 127) begin
            clamped_val = 8'sd127;
        end else if (shifted_val < 0) begin
            clamped_val = 8'sd0;
        end else begin
            clamped_val = shifted_val[OUT_WIDTH-1:0];
        end
    end

    // Pipeline register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout      <= '0;
            valid_reg <= 1'b0;
        end else begin
            dout      <= clamped_val;
            valid_reg <= valid_in;
        end
    end

    assign valid_out = valid_reg;

endmodule

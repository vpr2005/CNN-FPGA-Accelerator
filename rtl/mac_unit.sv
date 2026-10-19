//-----------------------------------------------------------------------------
// File: mac_unit.sv
// Module: mac_unit
// Description: Pipelined Multiply-Accumulate (MAC) unit targeting FPGA DSP48 blocks.
//              Computes: P = (A * B) + C (or accumulates)
//              Synthesizable with explicit DSP mapping directives.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module mac_unit #(
    parameter int DATA_WIDTH = 8,
    parameter int WEIGHT_WIDTH = 8,
    parameter int ACCUM_WIDTH = 32
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          en,
    input  logic                          clr,        // Clear accumulator / pipeline
    input  logic signed [DATA_WIDTH-1:0]  din_a,      // Feature pixel
    input  logic signed [WEIGHT_WIDTH-1:0]din_b,      // Kernel weight
    input  logic signed [ACCUM_WIDTH-1:0] din_c,      // Bias or cascade accumulate
    output logic signed [ACCUM_WIDTH-1:0] dout        // Pipelined MAC output
);

    // DSP mapping directive for Vivado synthesis
    (* use_dsp = "yes" *)
    logic signed [DATA_WIDTH-1:0]           a_reg;
    logic signed [WEIGHT_WIDTH-1:0]         b_reg;
    logic signed [DATA_WIDTH+WEIGHT_WIDTH-1:0] mult_reg;
    logic signed [ACCUM_WIDTH-1:0]          c_reg;
    logic signed [ACCUM_WIDTH-1:0]          accum_reg;

    // Stage 1: Input pipeline registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg <= '0;
            b_reg <= '0;
            c_reg <= '0;
        end else if (en) begin
            if (clr) begin
                a_reg <= '0;
                b_reg <= '0;
                c_reg <= '0;
            end else begin
                a_reg <= din_a;
                b_reg <= din_b;
                c_reg <= din_c;
            end
        end
    end

    // Stage 2: Multiplier register (maps to DSP48 multiplier)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_reg <= '0;
        end else if (en) begin
            if (clr) begin
                mult_reg <= '0;
            end else begin
                mult_reg <= a_reg * b_reg;
            end
        end
    end

    // Stage 3: Accumulate with C register (maps to DSP48 post-adder)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_reg <= '0;
        end else if (en) begin
            if (clr) begin
                accum_reg <= '0;
            end else begin
                accum_reg <= mult_reg + c_reg;
            end
        end
    end

    assign dout = accum_reg;

endmodule

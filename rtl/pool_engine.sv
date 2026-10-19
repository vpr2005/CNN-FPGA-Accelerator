//-----------------------------------------------------------------------------
// File: pool_engine.sv
// Module: pool_engine
// Description: Multi-channel Parallel Max Pooling Engine.
//              Instantiates NUM_FILTERS streaming 2x2 maxpool units to downsample
//              all feature map channels simultaneously.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module pool_engine #(
    parameter int DATA_WIDTH     = 8,
    parameter int FEATURE_WIDTH  = 26,
    parameter int FEATURE_HEIGHT = 26,
    parameter int NUM_FILTERS    = 4
)(
    input  logic                               clk,
    input  logic                               rst_n,
    input  logic                               valid_in,
    input  logic signed [DATA_WIDTH-1:0]       features_in [0:NUM_FILTERS-1],
    output logic signed [DATA_WIDTH-1:0]       pooled_out  [0:NUM_FILTERS-1],
    output logic                               valid_out
);

    logic [NUM_FILTERS-1:0] pool_valid;

    genvar f;
    generate
        for (f = 0; f < NUM_FILTERS; f++) begin : gen_pool
            maxpool_unit #(
                .DATA_WIDTH     (DATA_WIDTH),
                .FEATURE_WIDTH  (FEATURE_WIDTH),
                .FEATURE_HEIGHT (FEATURE_HEIGHT)
            ) u_maxpool (
                .clk       (clk),
                .rst_n     (rst_n),
                .valid_in  (valid_in),
                .din       (features_in[f]),
                .dout      (pooled_out[f]),
                .valid_out (pool_valid[f])
            );
        end
    endgenerate

    assign valid_out = pool_valid[0];

endmodule

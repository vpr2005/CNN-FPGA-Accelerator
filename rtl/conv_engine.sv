//-----------------------------------------------------------------------------
// File: conv_engine.sv
// Module: conv_engine
// Description: Multi-channel 2D Convolution Engine.
//              Combines streaming line buffer, parallel DSP PE array, and
//              pipelined ReLU activation units for NUM_FILTERS channels.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module conv_engine #(
    parameter int DATA_WIDTH   = 8,
    parameter int WEIGHT_WIDTH = 8,
    parameter int ACCUM_WIDTH  = 32,
    parameter int IMG_WIDTH    = 28,
    parameter int IMG_HEIGHT   = 28,
    parameter int NUM_FILTERS  = 4,
    parameter int SHIFT_BITS   = 7
)(
    input  logic                               clk,
    input  logic                               rst_n,
    
    // Streaming pixel input
    input  logic                               pixel_valid_in,
    input  logic signed [DATA_WIDTH-1:0]       pixel_in,
    
    // Weights and Biases
    input  logic signed [WEIGHT_WIDTH-1:0]     weights [0:NUM_FILTERS-1][0:2][0:2],
    input  logic signed [ACCUM_WIDTH-1:0]      biases  [0:NUM_FILTERS-1],
    
    // Multi-channel activated feature outputs
    output logic signed [DATA_WIDTH-1:0]       features_out [0:NUM_FILTERS-1],
    output logic                               features_valid_out,
    output logic                               frame_done_out
);

    // Internal signals from line buffer
    logic signed [DATA_WIDTH-1:0] window [0:2][0:2];
    logic                         win_valid;
    logic                         line_buf_frame_done;

    // Internal signals from PE array
    logic signed [ACCUM_WIDTH-1:0] pe_conv_out [0:NUM_FILTERS-1];
    logic                          pe_valid_out;

    // ReLU outputs
    logic signed [DATA_WIDTH-1:0]  relu_dout [0:NUM_FILTERS-1];
    logic [NUM_FILTERS-1:0]        relu_valid;

    // 1. Line Buffer & Receptive Field Generator
    line_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) u_line_buffer (
        .clk              (clk),
        .rst_n            (rst_n),
        .pixel_valid_in   (pixel_valid_in),
        .pixel_in         (pixel_in),
        .window_out       (window),
        .window_valid_out (win_valid),
        .frame_done_out   (line_buf_frame_done)
    );

    // 2. Parallel Processing Element Array (DSP48-based)
    pe_array #(
        .DATA_WIDTH   (DATA_WIDTH),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .ACCUM_WIDTH  (ACCUM_WIDTH),
        .NUM_FILTERS  (NUM_FILTERS)
    ) u_pe_array (
        .clk          (clk),
        .rst_n        (rst_n),
        .valid_in     (win_valid),
        .window_in    (window),
        .weights      (weights),
        .biases       (biases),
        .conv_out     (pe_conv_out),
        .valid_out    (pe_valid_out)
    );

    // 3. Parallel ReLU Activation & Scaling Units
    genvar f;
    generate
        for (f = 0; f < NUM_FILTERS; f++) begin : gen_relu
            relu_unit #(
                .IN_WIDTH   (ACCUM_WIDTH),
                .OUT_WIDTH  (DATA_WIDTH),
                .SHIFT_BITS (SHIFT_BITS)
            ) u_relu (
                .clk       (clk),
                .rst_n     (rst_n),
                .valid_in  (pe_valid_out),
                .din       (pe_conv_out[f]),
                .dout      (relu_dout[f]),
                .valid_out (relu_valid[f])
            );

            assign features_out[f] = relu_dout[f];
        end
    endgenerate

    assign features_valid_out = relu_valid[0];

    // Delayed frame done to match pipeline depth (LineBuf -> PE (4) -> ReLU (1))
    logic [5:0] frame_done_pipe;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_done_pipe <= '0;
        end else begin
            frame_done_pipe <= {frame_done_pipe[4:0], line_buf_frame_done};
        end
    end

    assign frame_done_out = frame_done_pipe[5];

endmodule

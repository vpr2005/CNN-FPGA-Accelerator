//-----------------------------------------------------------------------------
// File: pe_array.sv
// Module: pe_array
// Description: Parallel Processing Element (PE) Array for 2D Convolution.
//              Computes dot products across NUM_FILTERS filters simultaneously
//              using dedicated DSP multiplier blocks and pipelined adder trees.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module pe_array #(
    parameter int DATA_WIDTH   = 8,
    parameter int WEIGHT_WIDTH = 8,
    parameter int ACCUM_WIDTH  = 32,
    parameter int NUM_FILTERS  = 4
)(
    input  logic                               clk,
    input  logic                               rst_n,
    input  logic                               valid_in,
    
    // 3x3 receptive field window
    input  logic signed [DATA_WIDTH-1:0]       window_in [0:2][0:2],
    
    // Weights: [filter_idx][kernel_row][kernel_col]
    input  logic signed [WEIGHT_WIDTH-1:0]     weights [0:NUM_FILTERS-1][0:2][0:2],
    // Biases: [filter_idx]
    input  logic signed [ACCUM_WIDTH-1:0]      biases [0:NUM_FILTERS-1],
    
    // Outputs
    output logic signed [ACCUM_WIDTH-1:0]      conv_out [0:NUM_FILTERS-1],
    output logic                               valid_out
);

    // Flatten window into 9-element array for simpler iteration
    logic signed [DATA_WIDTH-1:0] win_flat [0:8];
    assign win_flat[0] = window_in[0][0];
    assign win_flat[1] = window_in[0][1];
    assign win_flat[2] = window_in[0][2];
    assign win_flat[3] = window_in[1][0];
    assign win_flat[4] = window_in[1][1];
    assign win_flat[5] = window_in[1][2];
    assign win_flat[6] = window_in[2][0];
    assign win_flat[7] = window_in[2][1];
    assign win_flat[8] = window_in[2][2];

    // Multiplier pipeline registers: 9 products per filter
    (* use_dsp = "yes" *)
    logic signed [DATA_WIDTH+WEIGHT_WIDTH-1:0] mult_stage [0:NUM_FILTERS-1][0:8];

    // Adder Tree Pipeline Stage 1
    logic signed [ACCUM_WIDTH-1:0] tree_s1_01 [0:NUM_FILTERS-1];
    logic signed [ACCUM_WIDTH-1:0] tree_s1_23 [0:NUM_FILTERS-1];
    logic signed [ACCUM_WIDTH-1:0] tree_s1_45 [0:NUM_FILTERS-1];
    logic signed [ACCUM_WIDTH-1:0] tree_s1_67 [0:NUM_FILTERS-1];
    logic signed [ACCUM_WIDTH-1:0] tree_s1_8  [0:NUM_FILTERS-1];
    logic signed [ACCUM_WIDTH-1:0] bias_pipe1 [0:NUM_FILTERS-1];

    // Adder Tree Pipeline Stage 2
    logic signed [ACCUM_WIDTH-1:0] tree_s2_0123  [0:NUM_FILTERS-1];
    logic signed [ACCUM_WIDTH-1:0] tree_s2_45678 [0:NUM_FILTERS-1];
    logic signed [ACCUM_WIDTH-1:0] bias_pipe2    [0:NUM_FILTERS-1];

    // Final Stage: Sum + Bias
    logic signed [ACCUM_WIDTH-1:0] final_sum [0:NUM_FILTERS-1];

    // Valid signal pipeline (4 cycles latency: Mult -> Stage1 -> Stage2 -> Stage3)
    logic [3:0] valid_pipe;

    // Parallel processing across all filters
    genvar f, i;
    generate
        for (f = 0; f < NUM_FILTERS; f++) begin : gen_filter
            // Multiplier stage: 9 DSP multipliers per filter
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int k = 0; k < 9; k++) begin
                        mult_stage[f][k] <= '0;
                    end
                end else if (valid_in) begin
                    mult_stage[f][0] <= win_flat[0] * weights[f][0][0];
                    mult_stage[f][1] <= win_flat[1] * weights[f][0][1];
                    mult_stage[f][2] <= win_flat[2] * weights[f][0][2];
                    mult_stage[f][3] <= win_flat[3] * weights[f][1][0];
                    mult_stage[f][4] <= win_flat[4] * weights[f][1][1];
                    mult_stage[f][5] <= win_flat[5] * weights[f][1][2];
                    mult_stage[f][6] <= win_flat[6] * weights[f][2][0];
                    mult_stage[f][7] <= win_flat[7] * weights[f][2][1];
                    mult_stage[f][8] <= win_flat[8] * weights[f][2][2];
                end
            end

            // Adder Tree Stage 1
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    tree_s1_01[f] <= '0;
                    tree_s1_23[f] <= '0;
                    tree_s1_45[f] <= '0;
                    tree_s1_67[f] <= '0;
                    tree_s1_8[f]  <= '0;
                    bias_pipe1[f] <= '0;
                end else begin
                    tree_s1_01[f] <= mult_stage[f][0] + mult_stage[f][1];
                    tree_s1_23[f] <= mult_stage[f][2] + mult_stage[f][3];
                    tree_s1_45[f] <= mult_stage[f][4] + mult_stage[f][5];
                    tree_s1_67[f] <= mult_stage[f][6] + mult_stage[f][7];
                    tree_s1_8[f]  <= mult_stage[f][8];
                    bias_pipe1[f] <= biases[f];
                end
            end

            // Adder Tree Stage 2
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    tree_s2_0123[f]  <= '0;
                    tree_s2_45678[f] <= '0;
                    bias_pipe2[f]    <= '0;
                end else begin
                    tree_s2_0123[f]  <= tree_s1_01[f] + tree_s1_23[f];
                    tree_s2_45678[f] <= tree_s1_45[f] + tree_s1_67[f] + tree_s1_8[f];
                    bias_pipe2[f]    <= bias_pipe1[f];
                end
            end

            // Stage 3: Total Sum + Bias
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    final_sum[f] <= '0;
                end else begin
                    final_sum[f] <= tree_s2_0123[f] + tree_s2_45678[f] + bias_pipe2[f];
                end
            end

            assign conv_out[f] = final_sum[f];
        end
    endgenerate

    // Pipeline valid signal
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= '0;
        end else begin
            valid_pipe <= {valid_pipe[2:0], valid_in};
        end
    end

    assign valid_out = valid_pipe[3];

endmodule

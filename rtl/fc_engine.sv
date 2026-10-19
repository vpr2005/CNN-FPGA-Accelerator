//-----------------------------------------------------------------------------
// File: fc_engine.sv
// Module: fc_engine
// Description: Fully Connected (Dense) Layer Accelerator with parallel DSP MACs
//              and hardware Argmax classification engine.
//              Computes 10 output class logits over 676 input features.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module fc_engine #(
    parameter int DATA_WIDTH     = 8,
    parameter int WEIGHT_WIDTH   = 8,
    parameter int ACCUM_WIDTH    = 32,
    parameter int NUM_FEATURES   = 169, // 13x13 spatial locations
    parameter int NUM_CHANNELS   = 4,
    parameter int NUM_CLASSES    = 10,
    // Default memory filenames
    parameter     WEIGHT_FILE    = "fc_weights.mem",
    parameter     BIAS_FILE      = "fc_biases.mem"
)(
    input  logic                          clk,
    input  logic                          rst_n,
    
    // Control interface
    input  logic                          start,
    output logic                          done,
    output logic                          busy,
    
    // Feature RAM read port
    output logic                          feat_re,
    output logic [$clog2(NUM_FEATURES)-1:0] feat_addr,
    input  logic [(NUM_CHANNELS*DATA_WIDTH)-1:0] feat_data,
    
    // Output classification
    output logic [3:0]                    predicted_class,
    output logic signed [ACCUM_WIDTH-1:0] max_logit,
    output logic signed [ACCUM_WIDTH-1:0] logits_out [0:NUM_CLASSES-1]
);

    localparam int ADDR_WIDTH = $clog2(NUM_FEATURES);

    // Weight storage: 10 classes, each has NUM_FEATURES words of 32 bits (4 channels * 8-bit)
    (* ram_style = "block" *)
    logic [(NUM_CHANNELS*WEIGHT_WIDTH)-1:0] weights_mem [0:NUM_CLASSES-1][0:NUM_FEATURES-1];

    // Class Biases (32-bit signed)
    logic signed [ACCUM_WIDTH-1:0] biases [0:NUM_CLASSES-1];

    // Initialize weights and biases
    initial begin
        for (int c = 0; c < NUM_CLASSES; c++) begin
            biases[c] = '0;
            for (int s = 0; s < NUM_FEATURES; s++) begin
                weights_mem[c][s] = '0;
            end
        end
        $readmemh(WEIGHT_FILE, weights_mem);
        $readmemh(BIAS_FILE, biases);
    end

    // FSM States
    typedef enum logic [2:0] {
        IDLE,
        COMPUTE,
        DRAIN,
        ADD_BIAS,
        ARGMAX,
        FINISHED
    } state_t;

    state_t state;

    // Address & loop counter
    logic [ADDR_WIDTH-1:0] addr_cnt;
    logic [2:0]            drain_cnt;

    // Pipeline valid flags
    logic pipe_v1, pipe_v2;

    // Registered read data (Stage 1)
    logic signed [DATA_WIDTH-1:0] feat_unpacked [0:NUM_CHANNELS-1];
    logic signed [WEIGHT_WIDTH-1:0] w_unpacked [0:NUM_CLASSES-1][0:NUM_CHANNELS-1];

    // Unpack features
    always_comb begin
        for (int ch = 0; ch < NUM_CHANNELS; ch++) begin
            feat_unpacked[ch] = feat_data[(ch*DATA_WIDTH) +: DATA_WIDTH];
        end
    end

    // Read weights for all classes
    logic [(NUM_CHANNELS*WEIGHT_WIDTH)-1:0] w_read [0:NUM_CLASSES-1];
    always_ff @(posedge clk) begin
        if (state == COMPUTE || state == IDLE) begin
            for (int c = 0; c < NUM_CLASSES; c++) begin
                w_read[c] <= weights_mem[c][addr_cnt];
            end
        end
    end

    // Unpack read weights
    always_comb begin
        for (int c = 0; c < NUM_CLASSES; c++) begin
            for (int ch = 0; ch < NUM_CHANNELS; ch++) begin
                w_unpacked[c][ch] = w_read[c][(ch*WEIGHT_WIDTH) +: WEIGHT_WIDTH];
            end
        end
    end

    // Multipliers (Stage 2): NUM_CLASSES * NUM_CHANNELS DSP multipliers
    (* use_dsp = "yes" *)
    logic signed [DATA_WIDTH+WEIGHT_WIDTH-1:0] products [0:NUM_CLASSES-1][0:NUM_CHANNELS-1];
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int c = 0; c < NUM_CLASSES; c++) begin
                for (int ch = 0; ch < NUM_CHANNELS; ch++) begin
                    products[c][ch] <= '0;
                end
            end
        end else if (pipe_v1) begin
            for (int c = 0; c < NUM_CLASSES; c++) begin
                for (int ch = 0; ch < NUM_CHANNELS; ch++) begin
                    products[c][ch] <= feat_unpacked[ch] * w_unpacked[c][ch];
                end
            end
        end
    end

    // Accumulators for 10 classes
    logic signed [ACCUM_WIDTH-1:0] accum [0:NUM_CLASSES-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int c = 0; c < NUM_CLASSES; c++) begin
                accum[c] <= '0;
            end
        end else if (state == IDLE && start) begin
            for (int c = 0; c < NUM_CLASSES; c++) begin
                accum[c] <= '0;
            end
        end else if (pipe_v2) begin
            for (int c = 0; c < NUM_CLASSES; c++) begin
                accum[c] <= accum[c] + 
                            products[c][0] + products[c][1] + 
                            products[c][2] + products[c][3];
            end
        end
    end

    // Pipeline valid shift register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_v1 <= 1'b0;
            pipe_v2 <= 1'b0;
        end else begin
            pipe_v1 <= (state == COMPUTE);
            pipe_v2 <= pipe_v1;
        end
    end

    // Final Logits & Argmax registers
    logic signed [ACCUM_WIDTH-1:0] final_logits [0:NUM_CLASSES-1];
    logic [3:0]                    best_class_reg;
    logic signed [ACCUM_WIDTH-1:0] best_score_reg;

    // Pipelined Argmax Comparator Tree
    // Stage 1: 5 pairwise winners
    logic [3:0] tree_s1_idx [0:4];
    logic signed [ACCUM_WIDTH-1:0] tree_s1_val [0:4];
    
    // Stage 2: 2 second-level winners + pass 5th
    logic [3:0] tree_s2_idx [0:2];
    logic signed [ACCUM_WIDTH-1:0] tree_s2_val [0:2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 5; i++) begin
                tree_s1_idx[i] <= '0;
                tree_s1_val[i] <= '0;
            end
            for (int i = 0; i < 3; i++) begin
                tree_s2_idx[i] <= '0;
                tree_s2_val[i] <= '0;
            end
        end else if (state == ADD_BIAS) begin
            // Tree Stage 1: Compare pairs (0,1), (2,3), (4,5), (6,7), (8,9)
            for (int i = 0; i < 5; i++) begin
                logic signed [ACCUM_WIDTH-1:0] op_a, op_b;
                op_a = accum[2*i] + biases[2*i];
                op_b = accum[2*i+1] + biases[2*i+1];
                if (op_b > op_a) begin
                    tree_s1_val[i] <= op_b;
                    tree_s1_idx[i] <= (2*i + 1);
                end else begin
                    tree_s1_val[i] <= op_a;
                    tree_s1_idx[i] <= (2*i);
                end
            end
        end else if (state == ARGMAX) begin
            // Tree Stage 2: Compare pairs (s1[0], s1[1]) and (s1[2], s1[3])
            if (tree_s1_val[1] > tree_s1_val[0]) begin
                tree_s2_val[0] <= tree_s1_val[1];
                tree_s2_idx[0] <= tree_s1_idx[1];
            end else begin
                tree_s2_val[0] <= tree_s1_val[0];
                tree_s2_idx[0] <= tree_s1_idx[0];
            end

            if (tree_s1_val[3] > tree_s1_val[2]) begin
                tree_s2_val[1] <= tree_s1_val[3];
                tree_s2_idx[1] <= tree_s1_idx[3];
            end else begin
                tree_s2_val[1] <= tree_s1_val[2];
                tree_s2_idx[1] <= tree_s1_idx[2];
            end

            tree_s2_val[2] <= tree_s1_val[4];
            tree_s2_idx[2] <= tree_s1_idx[4];
        end
    end

    // Main Control FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            addr_cnt        <= '0;
            drain_cnt       <= '0;
            feat_re         <= 1'b0;
            feat_addr       <= '0;
            done            <= 1'b0;
            busy            <= 1'b0;
            best_class_reg  <= '0;
            best_score_reg  <= '0;
            for (int c = 0; c < NUM_CLASSES; c++) begin
                final_logits[c] <= '0;
            end
        end else begin
            case (state)
                IDLE: begin
                    done      <= 1'b0;
                    addr_cnt  <= '0;
                    drain_cnt <= '0;
                    if (start) begin
                        busy      <= 1'b1;
                        feat_re   <= 1'b1;
                        feat_addr <= '0;
                        state     <= COMPUTE;
                    end else begin
                        busy    <= 1'b0;
                        feat_re <= 1'b0;
                    end
                end

                COMPUTE: begin
                    if (addr_cnt == NUM_FEATURES - 1) begin
                        feat_re   <= 1'b0;
                        state     <= DRAIN;
                        drain_cnt <= 3'd2; // Drain remaining 2 pipeline stages
                    end else begin
                        addr_cnt  <= addr_cnt + 1'b1;
                        feat_addr <= addr_cnt + 1'b1;
                    end
                end

                DRAIN: begin
                    if (drain_cnt == '0) begin
                        state <= ADD_BIAS;
                    end else begin
                        drain_cnt <= drain_cnt - 1'b1;
                    end
                end

                ADD_BIAS: begin
                    for (int c = 0; c < NUM_CLASSES; c++) begin
                        final_logits[c] <= accum[c] + biases[c];
                    end
                    state <= ARGMAX;
                end

                ARGMAX: begin
                    state <= FINISHED;
                end

                FINISHED: begin
                    // Final Stage 3: Choose among tree_s2[0], tree_s2[1], tree_s2[2]
                    logic [3:0] win_01_idx;
                    logic signed [ACCUM_WIDTH-1:0] win_01_val;
                    if (tree_s2_val[1] > tree_s2_val[0]) begin
                        win_01_val = tree_s2_val[1];
                        win_01_idx = tree_s2_idx[1];
                    end else begin
                        win_01_val = tree_s2_val[0];
                        win_01_idx = tree_s2_idx[0];
                    end

                    if (tree_s2_val[2] > win_01_val) begin
                        best_score_reg <= tree_s2_val[2];
                        best_class_reg <= tree_s2_idx[2];
                    end else begin
                        best_score_reg <= win_01_val;
                        best_class_reg <= win_01_idx;
                    end

                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Output assignments
    assign predicted_class = best_class_reg;
    assign max_logit       = best_score_reg;
    assign logits_out      = final_logits;

endmodule

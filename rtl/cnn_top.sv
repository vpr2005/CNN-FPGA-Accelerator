//-----------------------------------------------------------------------------
// File: cnn_top.sv
// Module: cnn_top
// Description: Top-Level High-Performance CNN FPGA Accelerator.
//              Integrates streaming 2D Convolution, Parallel DSP PE Array,
//              Pipelined ReLU Activation, Streaming Max Pooling, Feature RAM,
//              and Parallel Fully-Connected (FC) Classification Engine with
//              standard AXI4-Stream interfaces.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module cnn_top #(
    parameter int DATA_WIDTH     = 8,
    parameter int WEIGHT_WIDTH   = 8,
    parameter int ACCUM_WIDTH    = 32,
    parameter int IMG_WIDTH      = 28,
    parameter int IMG_HEIGHT     = 28,
    parameter int NUM_FILTERS    = 4,
    parameter int SHIFT_BITS     = 7,
    parameter int POOL_WIDTH     = 13,
    parameter int POOL_HEIGHT    = 13,
    parameter int NUM_CLASSES    = 10,
    parameter     FC_WEIGHT_FILE = "fc_weights.mem",
    parameter     FC_BIAS_FILE   = "fc_biases.mem",
    parameter     CONV_WEIGHT_FILE = "conv_weights.mem",
    parameter     CONV_BIAS_FILE   = "conv_biases.mem"
)(
    input  logic                          clk,
    input  logic                          rst_n,
    
    //-------------------------------------------------------------------------
    // AXI4-Stream Slave Interface (Input Feature Map / Image)
    //-------------------------------------------------------------------------
    input  logic signed [DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                          s_axis_tvalid,
    output logic                          s_axis_tready,
    input  logic                          s_axis_tlast,
    
    //-------------------------------------------------------------------------
    // AXI4-Stream Master Interface (Inference Prediction Output)
    //-------------------------------------------------------------------------
    output logic [31:0]                   m_axis_tdata,
    output logic                          m_axis_tvalid,
    input  logic                          m_axis_tready,
    output logic                          m_axis_tlast,
    
    //-------------------------------------------------------------------------
    // Status & Direct Diagnostics Interface
    //-------------------------------------------------------------------------
    output logic                          busy,
    output logic                          done,
    output logic [3:0]                    predicted_class,
    output logic signed [ACCUM_WIDTH-1:0] max_logit,
    output logic signed [ACCUM_WIDTH-1:0] logits_out [0:NUM_CLASSES-1]
);

    localparam int TOTAL_PIXELS = IMG_WIDTH * IMG_HEIGHT;
    localparam int NUM_FEATURES = POOL_WIDTH * POOL_HEIGHT; // 169

    //-------------------------------------------------------------------------
    // Conv Weights and Biases Storage
    //-------------------------------------------------------------------------
    logic signed [WEIGHT_WIDTH-1:0] conv_weights [0:NUM_FILTERS-1][0:2][0:2];
    logic signed [ACCUM_WIDTH-1:0]  conv_biases  [0:NUM_FILTERS-1];

    initial begin
        for (int f = 0; f < NUM_FILTERS; f++) begin
            conv_biases[f] = '0;
            for (int r = 0; r < 3; r++) begin
                for (int c = 0; c < 3; c++) begin
                    conv_weights[f][r][c] = '0;
                end
            end
        end
        $readmemh(CONV_WEIGHT_FILE, conv_weights);
        $readmemh(CONV_BIAS_FILE, conv_biases);
    end

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] conv_features [0:NUM_FILTERS-1];
    logic                         conv_valid;
    logic                         conv_frame_done;

    logic signed [DATA_WIDTH-1:0] pooled_features [0:NUM_FILTERS-1];
    logic                         pooled_valid;

    // Feature RAM signals
    logic                         feat_we;
    logic [$clog2(NUM_FEATURES)-1:0] feat_wr_addr;
    logic [(NUM_FILTERS*DATA_WIDTH)-1:0] feat_wr_data;
    
    logic                         feat_re;
    logic [$clog2(NUM_FEATURES)-1:0] feat_rd_addr;
    logic [(NUM_FILTERS*DATA_WIDTH)-1:0] feat_rd_data;

    // FC signals
    logic                         fc_start;
    logic                         fc_done;
    logic                         fc_busy;
    logic [3:0]                    fc_class;
    logic signed [ACCUM_WIDTH-1:0] fc_score;
    logic signed [ACCUM_WIDTH-1:0] fc_logits [0:NUM_CLASSES-1];

    // Global FSM states
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_STREAM_IMAGE,
        ST_WAIT_POOL,
        ST_FC_RUN,
        ST_EMIT_RESULT,
        ST_DONE
    } top_state_t;

    top_state_t state;

    logic [15:0] pixel_counter;
    logic [3:0]  pool_drain_timer;

    // Pack 4 channels into 32-bit RAM data
    always_comb begin
        for (int ch = 0; ch < NUM_FILTERS; ch++) begin
            feat_wr_data[(ch*DATA_WIDTH) +: DATA_WIDTH] = pooled_features[ch];
        end
    end

    //-------------------------------------------------------------------------
    // 1. Convolution Engine (Line Buffer + DSP PE Array + ReLU)
    //-------------------------------------------------------------------------
    logic pixel_in_valid;
    assign pixel_in_valid = s_axis_tvalid && s_axis_tready;

    conv_engine #(
        .DATA_WIDTH   (DATA_WIDTH),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .ACCUM_WIDTH  (ACCUM_WIDTH),
        .IMG_WIDTH    (IMG_WIDTH),
        .IMG_HEIGHT   (IMG_HEIGHT),
        .NUM_FILTERS  (NUM_FILTERS),
        .SHIFT_BITS   (SHIFT_BITS)
    ) u_conv_engine (
        .clk                (clk),
        .rst_n              (rst_n),
        .pixel_valid_in     (pixel_in_valid),
        .pixel_in           (s_axis_tdata),
        .weights            (conv_weights),
        .biases             (conv_biases),
        .features_out       (conv_features),
        .features_valid_out (conv_valid),
        .frame_done_out     (conv_frame_done)
    );

    //-------------------------------------------------------------------------
    // 2. Pooling Engine (Parallel 2x2 Max Pooling)
    //-------------------------------------------------------------------------
    pool_engine #(
        .DATA_WIDTH     (DATA_WIDTH),
        .FEATURE_WIDTH  (IMG_WIDTH - 2),  // 26
        .FEATURE_HEIGHT (IMG_HEIGHT - 2), // 26
        .NUM_FILTERS    (NUM_FILTERS)
    ) u_pool_engine (
        .clk         (clk),
        .rst_n       (rst_n),
        .valid_in    (conv_valid),
        .features_in (conv_features),
        .pooled_out  (pooled_features),
        .valid_out   (pooled_valid)
    );

    //-------------------------------------------------------------------------
    // 3. Feature RAM (Ping-Pong Buffer / Intermediate Feature Store)
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            feat_wr_addr <= '0;
            feat_we      <= 1'b0;
        end else if (state == ST_IDLE) begin
            feat_wr_addr <= '0;
            feat_we      <= 1'b0;
        end else if (pooled_valid) begin
            feat_we      <= 1'b1;
            feat_wr_addr <= feat_wr_addr + 1'b1;
        end else begin
            feat_we      <= 1'b0;
        end
    end

    feature_ram #(
        .DATA_WIDTH (NUM_FILTERS * DATA_WIDTH), // 32 bits
        .DEPTH      (NUM_FEATURES)              // 169 entries
    ) u_feature_ram (
        .clk    (clk),
        .we_a   (pooled_valid),
        .addr_a (feat_wr_addr),
        .din_a  (feat_wr_data),
        .re_b   (feat_re),
        .addr_b (feat_rd_addr),
        .dout_b (feat_rd_data)
    );

    //-------------------------------------------------------------------------
    // 4. Fully Connected (FC) Engine & Argmax
    //-------------------------------------------------------------------------
    fc_engine #(
        .DATA_WIDTH     (DATA_WIDTH),
        .WEIGHT_WIDTH   (WEIGHT_WIDTH),
        .ACCUM_WIDTH    (ACCUM_WIDTH),
        .NUM_FEATURES   (NUM_FEATURES),
        .NUM_CHANNELS   (NUM_FILTERS),
        .NUM_CLASSES    (NUM_CLASSES),
        .WEIGHT_FILE    (FC_WEIGHT_FILE),
        .BIAS_FILE      (FC_BIAS_FILE)
    ) u_fc_engine (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (fc_start),
        .done            (fc_done),
        .busy            (fc_busy),
        .feat_re         (feat_re),
        .feat_addr       (feat_rd_addr),
        .feat_data       (feat_rd_data),
        .predicted_class (fc_class),
        .max_logit       (fc_score),
        .logits_out      (fc_logits)
    );

    //-------------------------------------------------------------------------
    // Global Accelerator Sequencer FSM
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            pixel_counter    <= '0;
            pool_drain_timer <= '0;
            fc_start         <= 1'b0;
            s_axis_tready    <= 1'b0;
            m_axis_tdata     <= '0;
            m_axis_tvalid    <= 1'b0;
            m_axis_tlast     <= 1'b0;
            busy             <= 1'b0;
            done             <= 1'b0;
            predicted_class  <= '0;
            max_logit        <= '0;
            for (int c = 0; c < NUM_CLASSES; c++) begin
                logits_out[c] <= '0;
            end
        end else begin
            case (state)
                ST_IDLE: begin
                    done          <= 1'b0;
                    pixel_counter <= '0;
                    fc_start      <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    s_axis_tready <= 1'b1; // Ready to receive pixel stream

                    if (s_axis_tvalid) begin
                        busy          <= 1'b1;
                        pixel_counter <= pixel_counter + 1'b1;
                        state         <= ST_STREAM_IMAGE;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                ST_STREAM_IMAGE: begin
                    s_axis_tready <= 1'b1;
                    if (s_axis_tvalid) begin
                        if (pixel_counter == TOTAL_PIXELS - 1 || s_axis_tlast) begin
                            s_axis_tready    <= 1'b0;
                            pool_drain_timer <= 4'd12; // Wait for conv+pool pipelines to drain
                            state            <= ST_WAIT_POOL;
                        end else begin
                            pixel_counter <= pixel_counter + 1'b1;
                        end
                    end
                end

                ST_WAIT_POOL: begin
                    s_axis_tready <= 1'b0;
                    if (pool_drain_timer == '0) begin
                        fc_start <= 1'b1;
                        state    <= ST_FC_RUN;
                    end else begin
                        pool_drain_timer <= pool_drain_timer - 1'b1;
                    end
                end

                ST_FC_RUN: begin
                    fc_start <= 1'b0;
                    if (fc_done) begin
                        predicted_class <= fc_class;
                        max_logit       <= fc_score;
                        logits_out      <= fc_logits;
                        
                        // Output format: [31:16] = max_logit (truncated), [15:4] = 0, [3:0] = class
                        m_axis_tdata    <= {fc_score[15:0], 12'd0, fc_class};
                        m_axis_tvalid   <= 1'b1;
                        m_axis_tlast    <= 1'b1;
                        state           <= ST_EMIT_RESULT;
                    end
                end

                ST_EMIT_RESULT: begin
                    if (m_axis_tready) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast  <= 1'b0;
                        done          <= 1'b1;
                        state         <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    done  <= 1'b0;
                    busy  <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

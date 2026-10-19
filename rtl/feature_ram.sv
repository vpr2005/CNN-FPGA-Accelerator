//-----------------------------------------------------------------------------
// File: feature_ram.sv
// Module: feature_ram
// Description: Dual-port Synchronous Feature RAM.
//              Buffers intermediate multi-channel feature maps between
//              Convolution/Pooling engine and Fully-Connected engine.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module feature_ram #(
    parameter int DATA_WIDTH = 32, // 4 channels * 8-bit = 32 bits per entry
    parameter int DEPTH      = 256,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  logic                   clk,
    
    // Write Port A (from Pooling Engine)
    input  logic                   we_a,
    input  logic [ADDR_WIDTH-1:0]  addr_a,
    input  logic [DATA_WIDTH-1:0]  din_a,
    
    // Read Port B (to Fully Connected Engine)
    input  logic                   re_b,
    input  logic [ADDR_WIDTH-1:0]  addr_b,
    output logic [DATA_WIDTH-1:0]  dout_b
);

    // RAM declaration (maps to Block RAM or Distributed RAM)
    (* ram_style = "block" *)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Port A: Write
    always_ff @(posedge clk) begin
        if (we_a) begin
            mem[addr_a] <= din_a;
        end
    end

    // Port B: Read with registered output
    logic [DATA_WIDTH-1:0] read_data_reg;
    always_ff @(posedge clk) begin
        if (re_b) begin
            read_data_reg <= mem[addr_b];
        end
    end

    assign dout_b = read_data_reg;

endmodule

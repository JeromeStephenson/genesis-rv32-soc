
`timescale 1ns / 1ps

`include "riscv_defs.sv"

module simple_data_mem #(
    parameter int ADDR_WIDTH     = 32,
    parameter int DATA_WIDTH     = 32,
    parameter int MEM_SIZE_BYTES = 4096,
    parameter int MEM_DEPTH      = MEM_SIZE_BYTES / 4,
    parameter string HEX_FILE    = ""
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // Word-aligned address (byte addr[31:2])
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic [DATA_WIDTH-1:0] write_data,   // Already shifted by store_unit
    input  logic [3:0]            byte_mask,    // Per-byte write enable
    input  logic                  mem_write,

    output logic [DATA_WIDTH-1:0] read_data
);

    localparam int WORD_ADDR_WIDTH = $clog2(MEM_DEPTH);
    logic [WORD_ADDR_WIDTH-1:0] word_addr;

    assign word_addr = addr[WORD_ADDR_WIDTH+1 : 2];

    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // -------------------------------------------------------------------------
    // Init
    // -------------------------------------------------------------------------
    initial begin
        for (int i = 0; i < MEM_DEPTH; i++) mem[i] = '0;
        if (HEX_FILE != "") $readmemh(HEX_FILE, mem);
    end

    // -------------------------------------------------------------------------
    // Byte-masked synchronous write
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (mem_write) begin
            if (byte_mask[0]) mem[word_addr][7:0]   <= write_data[7:0];
            if (byte_mask[1]) mem[word_addr][15:8]  <= write_data[15:8];
            if (byte_mask[2]) mem[word_addr][23:16] <= write_data[23:16];
            if (byte_mask[3]) mem[word_addr][31:24] <= write_data[31:24];
        end
    end

    // -------------------------------------------------------------------------
    // Combinational read
    // -------------------------------------------------------------------------
    assign read_data = mem[word_addr];

endmodule



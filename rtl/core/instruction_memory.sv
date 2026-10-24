`timescale 1ns / 1ps


module instruction_memory #(
    parameter  int ADDR_WIDTH = 32,
    parameter  int DATA_WIDTH = 32,
    parameter  int MEM_DEPTH  = 4096,              // 256 words = 1KB
    parameter  string HEX_FILE = "program.hex"
)(
    input  logic [ADDR_WIDTH-1:0] pc,             // Byte address from PC
    output logic [DATA_WIDTH-1:0] instr 
              // Combinational read data
);

    // -------------------------------------------------------------------------
    // Local Constants
    // -------------------------------------------------------------------------
    localparam int WORD_ADDR_WIDTH = $clog2(MEM_DEPTH);

    // -------------------------------------------------------------------------
    // Memory Array
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // Word-aligned index extracted from PC
    logic [WORD_ADDR_WIDTH-1:0] word_addr;

    // -------------------------------------------------------------------------
    // Combinational Address Decode
    // -------------------------------------------------------------------------
    assign word_addr = pc[WORD_ADDR_WIDTH + 1 : 2];   // Drop byte offset [1:0]
    assign instr     = mem[word_addr];

    // -------------------------------------------------------------------------
    // Memory Initialization
    // -------------------------------------------------------------------------
    initial begin
        for (int i = 0; i < MEM_DEPTH; i++) begin
            mem[i] = '0;
        end
        if (HEX_FILE != "")
            $readmemh(HEX_FILE, mem);
    end

    // -------------------------------------------------------------------------
    // Combinational Assertions (simulation only)
    // -------------------------------------------------------------------------
    always_comb begin
        if (pc[1:0] != 2'b00)
            $error("[IMEM] PC not word-aligned: 0x%08x", pc);
        if (pc[31:2] >= MEM_DEPTH)
            $error("[IMEM] PC out of bounds: 0x%08x", pc);
    end

endmodule

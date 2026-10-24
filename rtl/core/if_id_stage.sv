
`timescale 1ns / 1ps



module if_id_stage #(
    parameter  int DATA_WIDTH = 32,
    parameter  int ADDR_WIDTH = 32
)(
    input  logic                  clk,
    input  logic                  rst_n,          // Active-low (matches IMEM)

    // Pipeline control
    input  logic                  stall,          // Freeze register
    input  logic                  flush,          // Insert NOP bubble

    // Inputs from IF stage
    input  logic [ADDR_WIDTH-1:0] pc,
    input  logic [DATA_WIDTH-1:0] instr,
    input  logic                  valid,          // From IMEM

    // Outputs to ID stage
    output logic [ADDR_WIDTH-1:0] if_id_pc,
    output logic [DATA_WIDTH-1:0] if_id_instr,
    output logic                  if_id_valid     // Propagated valid flag
);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    localparam logic [DATA_WIDTH-1:0] NOP_INSTR = 32'h0000_000F; // FENCE (no reg write)

    // -------------------------------------------------------------------------
    // Pipeline Register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc    <= '0;
            if_id_instr <= NOP_INSTR;
            if_id_valid <= 1'b0;
        end
        else if (flush) begin
            // Bubble: ID stage sees a NOP marked invalid
            if_id_instr <= NOP_INSTR;
            if_id_valid <= 1'b0;
            // PC retained for debug/trace (optional: clear to '0)
        end
        else if (!stall) begin
            // Normal propagation
            if_id_pc    <= pc;
            if_id_instr <= instr;
            if_id_valid <= valid;
        end
        // If stalled: all outputs hold implicitly
    end

    // -------------------------------------------------------------------------
    // Simulation Assertions
    // -------------------------------------------------------------------------
    // Ensure we never propagate an X-valued instruction when valid
    assert property (@(posedge clk) disable iff (!rst_n)
        (if_id_valid) |-> (!$isunknown(if_id_instr))
    ) else $error("[IF/ID] Valid instruction is X: 0x%08x", if_id_instr);

    // Flush and stall should never be asserted simultaneously (design rule)
    assert property (@(posedge clk) disable iff (!rst_n)
        not (flush && stall)
    ) else $warning("[IF/ID] Flush and stall both asserted");

endmodule



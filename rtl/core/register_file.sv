`timescale 1ns / 1ps


`include "riscv_defs.sv"

module register_file #(
    parameter int DATA_WIDTH = 32,
    parameter int NUM_REGS   = 32,
    parameter int ADDR_WIDTH = $clog2(NUM_REGS)
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // Read port 1 (asynchronous)
    input  logic [ADDR_WIDTH-1:0] rs1_addr,
    output logic [DATA_WIDTH-1:0] rs1_data,

    // Read port 2 (asynchronous)
    input  logic [ADDR_WIDTH-1:0] rs2_addr,
    output logic [DATA_WIDTH-1:0] rs2_data,

    // Write port (synchronous, on rising edge)
    input  logic                  reg_write,    // From WB stage
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    input  logic [DATA_WIDTH-1:0] rd_data
);

    // -------------------------------------------------------------------------
    // Register array
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] regs [0:NUM_REGS-1];

    // -------------------------------------------------------------------------
    // Asynchronous Read (combinational)
    // -------------------------------------------------------------------------
   // Asynchronous reads with write-back bypass.
// If WB writes a register being read in ID during the same cycle,
// return the new WB value instead of the old value in regs[].

always_comb begin
    // Read port 1
    if (rs1_addr == `REG_ZERO) begin
        rs1_data = '0;
    end
    else if (reg_write &&
             (rd_addr != `REG_ZERO) &&
             (rd_addr == rs1_addr)) begin
        rs1_data = rd_data;
    end
    else begin
        rs1_data = regs[rs1_addr];
    end

    // Read port 2
    if (rs2_addr == `REG_ZERO) begin
        rs2_data = '0;
    end
    else if (reg_write &&
             (rd_addr != `REG_ZERO) &&
             (rd_addr == rs2_addr)) begin
        rs2_data = rd_data;
    end
    else begin
        rs2_data = regs[rs2_addr];
    end
end


    // -------------------------------------------------------------------------
    // Synchronous Write
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers to zero (optional, but safe for simulation)
            for (int i = 0; i < NUM_REGS; i++) begin
                regs[i] <= '0;
            end
        end
        else if (reg_write && (rd_addr != `REG_ZERO)) begin
            // Write only if enabled and not targeting x0
            regs[rd_addr] <= rd_data;
        end
    end

   
    

endmodule


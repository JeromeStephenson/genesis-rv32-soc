`timescale 1ns / 1ps
`include "riscv_defs.sv"

module mem_wb_stage #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  stall,
    input  logic                  flush,

    input  logic [ADDR_WIDTH-1:0] mem_pc_plus4,
    input  logic [DATA_WIDTH-1:0] mem_alu_result,
    input  logic [DATA_WIDTH-1:0] mem_read_data,
    input  logic [4:0]            mem_rd,
    input  logic                  mem_reg_write,
    input  logic [1:0]            mem_mem_to_reg,
    input  logic                  mem_valid,

    // CSR
    input  logic [DATA_WIDTH-1:0] mem_csr_wdata,
    input  logic [11:0]           mem_csr_addr,
    input  logic                  mem_csr_we,
    input  logic [DATA_WIDTH-1:0] mem_csr_rdata,

    output logic [ADDR_WIDTH-1:0] wb_pc_plus4,
    output logic [DATA_WIDTH-1:0] wb_alu_result,
    output logic [DATA_WIDTH-1:0] wb_read_data,
    output logic [4:0]            wb_rd,
    output logic                  wb_reg_write,
    output logic [1:0]            wb_mem_to_reg,
    output logic                  wb_valid,

    // CSR
    output logic [DATA_WIDTH-1:0] wb_csr_wdata,
    output logic [11:0]           wb_csr_addr,
    output logic                  wb_csr_we,
    output logic [DATA_WIDTH-1:0] wb_csr_rdata,

    // Write-back data (combinational, to register file)
    output logic [DATA_WIDTH-1:0] wb_write_data
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_pc_plus4   <= '0;
            wb_alu_result <= '0;
            wb_read_data  <= '0;
            wb_rd         <= '0;
            wb_reg_write  <= 1'b0;
            wb_mem_to_reg <= `WB_ALU;
            wb_valid      <= 1'b0;
            wb_csr_wdata  <= '0;
            wb_csr_addr   <= '0;
            wb_csr_we     <= 1'b0;
            wb_csr_rdata  <= '0;
        end
        else if (flush) begin
            wb_reg_write  <= 1'b0;
            wb_mem_to_reg <= `WB_ALU;
            wb_valid      <= 1'b0;
            wb_csr_we     <= 1'b0;
        end
        else if (!stall) begin
            wb_pc_plus4   <= mem_pc_plus4;
            wb_alu_result <= mem_alu_result;
            wb_read_data  <= mem_read_data;
            wb_rd         <= mem_rd;
            wb_reg_write  <= mem_reg_write;
            wb_mem_to_reg <= mem_mem_to_reg;
            wb_valid      <= mem_valid;
            wb_csr_wdata  <= mem_csr_wdata;
            wb_csr_addr   <= mem_csr_addr;
            wb_csr_we     <= mem_csr_we;
            wb_csr_rdata  <= mem_csr_rdata;
        end
    end

    always_comb begin
        case (wb_mem_to_reg)
            `WB_ALU: wb_write_data = wb_alu_result;
            `WB_MEM: wb_write_data = wb_read_data;
            `WB_PC4: wb_write_data = wb_pc_plus4;
            `WB_CSR: wb_write_data = wb_csr_rdata;
            default: wb_write_data = wb_alu_result;
        endcase
    end

   // assert property (@(posedge clk) disable iff (!rst_n)
     //   (wb_reg_write && wb_valid) |-> (wb_rd != 0)
   // ) else $error("[MEM/WB] Writing to x0!");

endmodule

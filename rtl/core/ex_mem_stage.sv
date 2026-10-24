`timescale 1ns / 1ps
`include "riscv_defs.sv"

module ex_mem_stage #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  stall,
    input  logic                  flush,

    input  logic [ADDR_WIDTH-1:0] ex_pc_plus4,
    input  logic [DATA_WIDTH-1:0] ex_alu_result,
    input  logic [DATA_WIDTH-1:0] ex_store_data,
    input  logic [4:0]            ex_rd,
    input  logic [2:0]            ex_funct3,
    input  logic                  ex_mem_write,
    input  logic                  ex_mem_read,
    input  logic                  ex_reg_write,
    input  logic [1:0]            ex_mem_to_reg,
    input  logic                  ex_valid,

    // CSR
    input  logic [DATA_WIDTH-1:0] ex_csr_wdata,
    input  logic [11:0]           ex_csr_addr,
    input  logic                  ex_csr_we,
    input  logic [DATA_WIDTH-1:0] ex_csr_rdata,

    output logic [ADDR_WIDTH-1:0] mem_pc_plus4,
    output logic [DATA_WIDTH-1:0] mem_alu_result,
    output logic [DATA_WIDTH-1:0] mem_store_data,
    output logic [4:0]            mem_rd,
    output logic [2:0]            mem_funct3,
    output logic                  mem_mem_write,
    output logic                  mem_mem_read,
    output logic                  mem_reg_write,
    output logic [1:0]            mem_mem_to_reg,
    output logic                  mem_valid,

    // CSR
    output logic [DATA_WIDTH-1:0] mem_csr_wdata,
    output logic [11:0]           mem_csr_addr,
    output logic                  mem_csr_we,
    output logic [DATA_WIDTH-1:0] mem_csr_rdata
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_pc_plus4   <= '0;
            mem_alu_result <= '0;
            mem_store_data <= '0;
            mem_rd         <= '0;
            mem_funct3     <= '0;
            mem_mem_write  <= 1'b0;
            mem_mem_read   <= 1'b0;
            mem_reg_write  <= 1'b0;
            mem_mem_to_reg <= `WB_ALU;
            mem_valid      <= 1'b0;
            mem_csr_wdata  <= '0;
            mem_csr_addr   <= '0;
            mem_csr_we     <= 1'b0;
            mem_csr_rdata  <= '0;
        end
        else if (flush) begin
            mem_mem_write  <= 1'b0;
            mem_mem_read   <= 1'b0;
            mem_reg_write  <= 1'b0;
            mem_mem_to_reg <= `WB_ALU;
            mem_valid      <= 1'b0;
            mem_csr_we     <= 1'b0;
        end
        else if (!stall) begin
            mem_pc_plus4   <= ex_pc_plus4;
            mem_alu_result <= ex_alu_result;
            mem_store_data <= ex_store_data;
            mem_rd         <= ex_rd;
            mem_funct3     <= ex_funct3;
            mem_mem_write  <= ex_mem_write;
            mem_mem_read   <= ex_mem_read;
            mem_reg_write  <= ex_reg_write;
            mem_mem_to_reg <= ex_mem_to_reg;
            mem_valid      <= ex_valid;
            mem_csr_wdata  <= ex_csr_wdata;
            mem_csr_addr   <= ex_csr_addr;
            mem_csr_we     <= ex_csr_we;
            mem_csr_rdata  <= ex_csr_rdata;
        end
    end

    assert property (@(posedge clk) disable iff (!rst_n)
        not (stall && flush)
    ) else $warning("[EX/MEM] stall and flush asserted together");

    assert property (@(posedge clk) disable iff (!rst_n)
        (mem_mem_write && mem_valid) |-> (mem_funct3 inside {`FUNCT3_SB, `FUNCT3_SH, `FUNCT3_SW})
    ) else $error("[EX/MEM] Store with invalid funct3: %b", mem_funct3);

endmodule




`timescale 1ns / 1ps
`include "riscv_defs.sv"

module id_ex_stage #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  stall,
    input  logic                  flush,

    input  logic [ADDR_WIDTH-1:0] id_pc,
    input  logic [ADDR_WIDTH-1:0] id_pc_plus4,
    input  logic [DATA_WIDTH-1:0] id_rs1_data,
    input  logic [DATA_WIDTH-1:0] id_rs2_data,
    input  logic [DATA_WIDTH-1:0] id_imm,
    input  logic [DATA_WIDTH-1:0] id_instr,        // NEW
    input  logic [4:0]            id_rs1,
    input  logic [4:0]            id_rs2,
    input  logic [4:0]            id_rd,
    input  logic [6:0]            id_opcode,
    input  logic [2:0]            id_funct3,
    input  logic [6:0]            id_funct7,
    input  logic [3:0]            id_alu_op,
    input  logic                  id_alu_src,
    input  logic                  id_mem_write,
    input  logic                  id_mem_read,
    input  logic                  id_reg_write,
    input  logic [1:0]            id_mem_to_reg,
    input  logic                  id_branch,
    input  logic                  id_jump,
    input  logic                  id_jalr,
    input  logic                  id_valid,
    input  logic                  id_illegal_instr,

    // CSR / System
    input  logic [11:0]           id_csr_addr,
    input  logic [DATA_WIDTH-1:0] id_csr_rdata,
    input  logic [1:0]            id_csr_op,
    input  logic                  id_csr_imm,
    input  logic                  id_is_csr,
    input  logic                  id_is_ecall,
    input  logic                  id_is_ebreak,
    input  logic                  id_is_mret,

    output logic [ADDR_WIDTH-1:0] ex_pc,
    output logic [ADDR_WIDTH-1:0] ex_pc_plus4,
    output logic [DATA_WIDTH-1:0] ex_rs1_data,
    output logic [DATA_WIDTH-1:0] ex_rs2_data,
    output logic [DATA_WIDTH-1:0] ex_imm,
    output logic [DATA_WIDTH-1:0] ex_instr,        // NEW
    output logic [4:0]            ex_rs1,
    output logic [4:0]            ex_rs2,
    output logic [4:0]            ex_rd,
    output logic [6:0]            ex_opcode,
    output logic [2:0]            ex_funct3,
    output logic [6:0]            ex_funct7,
    output logic [3:0]            ex_alu_op,
    output logic                  ex_alu_src,
    output logic                  ex_mem_write,
    output logic                  ex_mem_read,
    output logic                  ex_reg_write,
    output logic [1:0]            ex_mem_to_reg,
    output logic                  ex_branch,
    output logic                  ex_jump,
    output logic                  ex_jalr,
    output logic                  ex_valid,
    output logic                  ex_illegal_instr,

    // CSR / System
    output logic [11:0]           ex_csr_addr,
    output logic [DATA_WIDTH-1:0] ex_csr_rdata,
    output logic [1:0]            ex_csr_op,
    output logic                  ex_csr_imm,
    output logic                  ex_is_csr,
    output logic                  ex_is_ecall,
    output logic                  ex_is_ebreak,
    output logic                  ex_is_mret
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_pc           <= '0;
            ex_pc_plus4     <= '0;
            ex_rs1_data     <= '0;
            ex_rs2_data     <= '0;
            ex_imm          <= '0;
            ex_instr        <= '0;           // NEW
            ex_rs1          <= '0;
            ex_rs2          <= '0;
            ex_rd           <= '0;
            ex_opcode       <= '0;
            ex_funct3       <= '0;
            ex_funct7       <= '0;
            ex_alu_op       <= `ALU_ADD;
            ex_alu_src      <= 1'b0;
            ex_mem_write    <= 1'b0;
            ex_mem_read     <= 1'b0;
            ex_reg_write    <= 1'b0;
            ex_mem_to_reg   <= `WB_ALU;
            ex_branch       <= 1'b0;
            ex_jump         <= 1'b0;
            ex_jalr         <= 1'b0;
            ex_valid        <= 1'b0;
            ex_illegal_instr<= 1'b0;
            ex_csr_addr     <= '0;
            ex_csr_rdata    <= '0;
            ex_csr_op       <= '0;
            ex_csr_imm      <= 1'b0;
            ex_is_csr       <= 1'b0;
            ex_is_ecall     <= 1'b0;
            ex_is_ebreak    <= 1'b0;
            ex_is_mret      <= 1'b0;
        end
        else if (flush) begin
            ex_alu_op       <= `ALU_ADD;
            ex_alu_src      <= 1'b0;
            ex_mem_write    <= 1'b0;
            ex_mem_read     <= 1'b0;
            ex_reg_write    <= 1'b0;
            ex_mem_to_reg   <= `WB_ALU;
            ex_branch       <= 1'b0;
            ex_jump         <= 1'b0;
            ex_jalr         <= 1'b0;
            ex_valid        <= 1'b0;
            ex_illegal_instr<= 1'b0;
            ex_instr        <= '0;           // NEW
            ex_is_csr       <= 1'b0;
            ex_is_ecall     <= 1'b0;
            ex_is_ebreak    <= 1'b0;
            ex_is_mret      <= 1'b0;
        end
        else if (!stall) begin
            ex_pc           <= id_pc;
            ex_pc_plus4     <= id_pc_plus4;
            ex_rs1_data     <= id_rs1_data;
            ex_rs2_data     <= id_rs2_data;
            ex_imm          <= id_imm;
            ex_instr        <= id_instr;     // NEW
            ex_rs1          <= id_rs1;
            ex_rs2          <= id_rs2;
            ex_rd           <= id_rd;
            ex_opcode       <= id_opcode;
            ex_funct3       <= id_funct3;
            ex_funct7       <= id_funct7;
            ex_alu_op       <= id_alu_op;
            ex_alu_src      <= id_alu_src;
            ex_mem_write    <= id_mem_write;
            ex_mem_read     <= id_mem_read;
            ex_reg_write    <= id_reg_write;
            ex_mem_to_reg   <= id_mem_to_reg;
            ex_branch       <= id_branch;
            ex_jump         <= id_jump;
            ex_jalr         <= id_jalr;
            ex_valid        <= id_valid;
            ex_illegal_instr<= id_illegal_instr;
            ex_csr_addr     <= id_csr_addr;
            ex_csr_rdata    <= id_csr_rdata;
            ex_csr_op       <= id_csr_op;
            ex_csr_imm      <= id_csr_imm;
            ex_is_csr       <= id_is_csr;
            ex_is_ecall     <= id_is_ecall;
            ex_is_ebreak    <= id_is_ebreak;
            ex_is_mret      <= id_is_mret;
        end
    end

    assert property (@(posedge clk) disable iff (!rst_n)
        not (stall && flush)
    ) else $warning("[ID/EX] stall and flush asserted together");

    assert property (@(posedge clk) disable iff (!rst_n)
        (ex_valid) |-> (!$isunknown({ex_opcode, ex_rd, ex_alu_op}))
    ) else $error("[ID/EX] Valid instruction has X fields in EX");

endmodule




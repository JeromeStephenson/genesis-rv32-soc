

`timescale 1ns / 1ps
`include "riscv_defs.sv"


module decoder #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32
)(
    input  logic [ADDR_WIDTH-1:0] if_id_pc,
    input  logic [ADDR_WIDTH-1:0] if_id_pc_plus4,
    input  logic [DATA_WIDTH-1:0] if_id_instr,
    input  logic                  if_id_valid,

    output logic [ADDR_WIDTH-1:0] pc_out,
    output logic [ADDR_WIDTH-1:0] pc_plus4_out,
    output logic [4:0]            rs1,
    output logic [4:0]            rs2,
    output logic [4:0]            rd,
    output logic [6:0]            opcode,
    output logic [2:0]            funct3,
    output logic [6:0]            funct7,
    output logic [11:0]           csr_addr,
    output logic [DATA_WIDTH-1:0] imm,
    output logic                  is_load,
    output logic                  valid
);

    assign opcode = if_id_instr[6:0];
    assign rd     = if_id_instr[11:7];
    assign funct3 = if_id_instr[14:12];
    assign rs1    = if_id_instr[19:15];
    assign rs2    = if_id_instr[24:20];
    assign funct7 = if_id_instr[31:25];
    assign csr_addr = if_id_instr[31:20];

    assign is_load = (opcode == `OPCODE_LOAD);
    assign valid   = if_id_valid;
    assign pc_out      = if_id_pc;
    assign pc_plus4_out = if_id_pc_plus4;

    always_comb begin
        imm = '0;
        case (opcode)
            `OPCODE_LOAD, `OPCODE_JALR:
                imm = {{20{if_id_instr[31]}}, if_id_instr[31:20]};

            `OPCODE_OP_IMM:
                if (funct3 == 3'b001 || funct3 == 3'b101)
                    imm = {27'b0, if_id_instr[24:20]};
                else
                    imm = {{20{if_id_instr[31]}}, if_id_instr[31:20]};

            `OPCODE_STORE:
                imm = {{20{if_id_instr[31]}}, if_id_instr[31:25], if_id_instr[11:7]};

            `OPCODE_BRANCH:
                imm = {{19{if_id_instr[31]}}, if_id_instr[31], if_id_instr[7],
                       if_id_instr[30:25], if_id_instr[11:8], 1'b0};

            `OPCODE_LUI, `OPCODE_AUIPC:
                imm = {if_id_instr[31:12], 12'b0};

            `OPCODE_JAL:
                imm = {{11{if_id_instr[31]}}, if_id_instr[31], if_id_instr[19:12],
                       if_id_instr[20], if_id_instr[30:21], 1'b0};

            default: imm = '0;
        endcase
    end

endmodule

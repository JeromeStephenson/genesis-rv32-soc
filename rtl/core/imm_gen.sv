`timescale 1ns / 1ps




`include "riscv_defs.sv"

module imm_gen (
    input  logic [31:7] instr,      // Upper 25 bits: instr[31:7] from decoder
    input  logic [2:0]  imm_type,   // FMT_* from control unit
    output logic [31:0] imm
);

    always_comb begin
        case (imm_type)
            // I-type: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
            //         + JALR + Loads (LB, LH, LW, LBU, LHU)
            `FMT_I_TYPE,
            `FMT_I_TYPE_LOAD: begin
                imm = {{20{instr[31]}}, instr[31:20]};
            end

            // S-type: SB, SH, SW
            `FMT_S_TYPE: begin
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            // B-type: BEQ, BNE, BLT, BGE, BLTU, BGEU
            `FMT_B_TYPE: begin
                imm = {{19{instr[31]}}, instr[31], instr[7],
                       instr[30:25], instr[11:8], 1'b0};
            end

            // J-type: JAL
            `FMT_J_TYPE: begin
                imm = {{11{instr[31]}}, instr[31], instr[19:12],
                       instr[20], instr[30:21], 1'b0};
            end

            // U-type: LUI, AUIPC
            `FMT_U_TYPE_LUI,
            `FMT_U_TYPE_AUIPC: begin
                imm = {instr[31:12], 12'b0};
            end

            default: begin
                imm = '0;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Assertions
    // -------------------------------------------------------------------------
    assert property (@(instr, imm_type)
        (imm_type inside {`FMT_I_TYPE, `FMT_I_TYPE_LOAD, `FMT_S_TYPE,
                          `FMT_B_TYPE, `FMT_J_TYPE, `FMT_U_TYPE_LUI,
                          `FMT_U_TYPE_AUIPC})
    ) else $error("[IMM_GEN] Invalid imm_type: %b", imm_type);

endmodule




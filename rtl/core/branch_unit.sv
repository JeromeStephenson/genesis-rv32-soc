`timescale 1ns / 1ps


`timescale 1ns / 1ps

`include "riscv_defs.sv"

module branch_unit (
    input  logic [6:0]  opcode,         // Full 7-bit opcode from ID/EX
    input  logic [2:0]  funct3,         // Branch condition from ID/EX
    input  logic [31:0] rs1_data,       // Forwarded rs1 value
    input  logic [31:0] rs2_data,       // Forwarded rs2 value
    input  logic        valid,          // ID/EX valid flag

    output logic        branch_taken,   // 1 = use branch/jump target
    output logic        is_branch,      // This is a conditional branch
    output logic        is_jump,        // This is JAL or JALR (unconditional)
    output logic        is_jalr         // This is JALR (PC target = rs1 + imm)
);

    // -------------------------------------------------------------------------
    // Instruction type detection
    // -------------------------------------------------------------------------
    assign is_branch = (opcode == `OPCODE_BRANCH) && valid;
    assign is_jump   = ((opcode == `OPCODE_JAL) || (opcode == `OPCODE_JALR)) && valid;
    assign is_jalr   = (opcode == `OPCODE_JALR) && valid;

    // -------------------------------------------------------------------------
    // Signed operands for SLT / BLT / BGE
    // -------------------------------------------------------------------------
    logic signed [31:0] rs1_signed;
    logic signed [31:0] rs2_signed;

    assign rs1_signed = signed'(rs1_data);
    assign rs2_signed = signed'(rs2_data);

    // -------------------------------------------------------------------------
    // Branch condition evaluation
    // -------------------------------------------------------------------------
    logic condition_met;

    always_comb begin
        condition_met = 1'b0;

        if (is_branch) begin
            case (funct3)
                `BRANCH_EQ:  condition_met = (rs1_data == rs2_data);
                `BRANCH_NE:  condition_met = (rs1_data != rs2_data);
                `BRANCH_LT:  condition_met = (rs1_signed < rs2_signed);
                `BRANCH_GE:  condition_met = (rs1_signed >= rs2_signed);
                `BRANCH_LTU: condition_met = (rs1_data < rs2_data);   // unsigned
                `BRANCH_GEU: condition_met = (rs1_data >= rs2_data);  // unsigned
                default:     condition_met = 1'b0;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Final branch taken signal
    // -------------------------------------------------------------------------
    // Asserted when:
    //   - Conditional branch and condition is met, OR
    //   - Unconditional jump (JAL / JALR)
    assign branch_taken = (is_branch && condition_met) || is_jump;

    // -------------------------------------------------------------------------
    // Assertions
    // -------------------------------------------------------------------------
    assert property (@(opcode, funct3, rs1_data, rs2_data)
        (is_branch) |-> (funct3 inside {`BRANCH_EQ, `BRANCH_NE, `BRANCH_LT,
                                        `BRANCH_GE, `BRANCH_LTU, `BRANCH_GEU})
    ) else $error("[BRANCH] Invalid funct3 for branch: %b", funct3);

endmodule

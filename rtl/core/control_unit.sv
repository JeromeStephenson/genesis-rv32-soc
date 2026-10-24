`timescale 1ns / 1ps
`include "riscv_defs.sv"

module control_unit (
    input  logic [6:0]  opcode,
    input  logic [2:0]  funct3,
    input  logic [6:0]  funct7,
    input  logic [4:0]  rs1,
    input  logic [4:0]  rs2,
    input  logic [4:0]  rd,
    input  logic        valid,

    output logic        reg_write,
    output logic        mem_read,
    output logic        mem_write,
    output logic        alu_src,
    output logic [1:0]  mem_to_reg,
    output logic        branch,
    output logic        jump,
    output logic        jalr,
    output logic [3:0]  alu_op,
    output logic [2:0]  imm_type,
    output logic        is_load,
    output logic        illegal_instr,        // NEW: flag unknown/reserved encodings

    // CSR / System
    output logic [1:0]  csr_op,
    output logic        csr_imm,
    output logic        is_csr,
    output logic        is_ecall,
    output logic        is_ebreak,
    output logic        is_mret
);


    initial $display(">>> NEW control_unit.sv LOADED at time %0t <<<", $time);
    // Immediate type encoding
    always_comb begin
        case (opcode)
            `OPCODE_OP_IMM:  imm_type = `FMT_I_TYPE;
            `OPCODE_LOAD,
            `OPCODE_JALR:    imm_type = `FMT_I_TYPE_LOAD;
            `OPCODE_STORE:   imm_type = `FMT_S_TYPE;
            `OPCODE_BRANCH:  imm_type = `FMT_B_TYPE;
            `OPCODE_JAL:     imm_type = `FMT_J_TYPE;
            `OPCODE_LUI:     imm_type = `FMT_U_TYPE_LUI;
            `OPCODE_AUIPC:   imm_type = `FMT_U_TYPE_AUIPC;
            default:         imm_type = `FMT_I_TYPE;
        endcase
    end

    assign is_load = (opcode == `OPCODE_LOAD);

    // System instruction decode
    assign is_csr    = (opcode == `OPCODE_SYSTEM) && valid && (funct3 != 3'b000) && (funct3 != 3'b100);
    assign is_ecall  = (opcode == `OPCODE_SYSTEM) && valid && (funct3 == 3'b000) && (funct7 == 7'b0000000) && (rs1 == 5'b00000) && (rd == 5'b00000) && (rs2 == 5'b00000);
    assign is_ebreak = (opcode == `OPCODE_SYSTEM) && valid && (funct3 == 3'b000) && (funct7 == 7'b0000000) && (rs1 == 5'b00000) && (rd == 5'b00000) && (rs2 == 5'b00001);
    assign is_mret   = (opcode == `OPCODE_SYSTEM) && valid && (funct3 == 3'b000) && (funct7 == 7'b0011000) && (rs1 == 5'b00000) && (rd == 5'b00000) && (rs2 == 5'b00010);

    assign csr_op  = funct3[1:0];
    assign csr_imm = funct3[2];

    // Main control signals
    always_comb begin
        reg_write     = 1'b0;
        mem_read      = 1'b0;
        mem_write     = 1'b0;
        alu_src       = 1'b0;
        mem_to_reg    = `WB_ALU;
        branch        = 1'b0;
        jump          = 1'b0;
        jalr          = 1'b0;
        alu_op        = `ALU_ADD;
        illegal_instr = 1'b0;          // default: legal

        if (valid) begin
            case (opcode)
                //-------------------------------------------------------------
                // R-type
                //-------------------------------------------------------------
               
                `OPCODE_OP: begin
                    reg_write = 1'b1;
                    alu_src   = 1'b0;
                    case (funct3)
                        `FUNCT3_ADD_SUB: begin
                            if (funct7 == `FUNCT7_ADD || funct7 == `FUNCT7_SUB)
                                alu_op = funct7[5] ? `ALU_SUB : `ALU_ADD;
                            else
                                illegal_instr = 1'b1;
                        end
                        `FUNCT3_SLL: begin
                            if (funct7 == `FUNCT7_ADD)   // must be 0000000
                                alu_op = `ALU_SLL;
                            else
                                illegal_instr = 1'b1;
                        end
                        `FUNCT3_SLT:     if (funct7 == `FUNCT7_ADD) alu_op = `ALU_SLT;  else illegal_instr = 1'b1;
                        `FUNCT3_SLTU:    if (funct7 == `FUNCT7_ADD) alu_op = `ALU_SLTU; else illegal_instr = 1'b1;
                        `FUNCT3_XOR:     if (funct7 == `FUNCT7_ADD) alu_op = `ALU_XOR;  else illegal_instr = 1'b1;
                        `FUNCT3_SRL_SRA: begin
                            if (funct7 == `FUNCT7_SRL || funct7 == `FUNCT7_SRA)
                                alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;
                            else
                                illegal_instr = 1'b1;
                        end
                       `FUNCT3_OR:      if (funct7 == `FUNCT7_ADD) alu_op = `ALU_OR;   else illegal_instr = 1'b1;
                         `FUNCT3_AND:     if (funct7 == `FUNCT7_ADD) alu_op = `ALU_AND;  else illegal_instr = 1'b1;
                        default:         illegal_instr = 1'b1;
                    endcase
                end

                //-------------------------------------------------------------
                // I-type ALU
                //-------------------------------------------------------------
                `OPCODE_OP_IMM: begin
                    reg_write = 1'b1;
                    alu_src   = 1'b1;
                    case (funct3)
                        `FUNCT3_ADD_SUB: alu_op = `ALU_ADD;
                        `FUNCT3_SLL: begin
                            // SLLI: upper 7 bits of imm must be 0000000
                            if (funct7 == `FUNCT7_ADD)
                                alu_op = `ALU_SLL;
                            else
                                illegal_instr = 1'b1;
                        end
                        `FUNCT3_SLT:     alu_op = `ALU_SLT;
                        `FUNCT3_SLTU:    alu_op = `ALU_SLTU;
                        `FUNCT3_XOR:     alu_op = `ALU_XOR;
                        `FUNCT3_SRL_SRA: begin
                            // SRLI / SRAI: upper 7 bits must be 0000000 or 0100000
                            if (funct7 == `FUNCT7_SRL || funct7 == `FUNCT7_SRA)
                                alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;
                            else
                                illegal_instr = 1'b1;
                        end
                        `FUNCT3_OR:      alu_op = `ALU_OR;
                        `FUNCT3_AND:     alu_op = `ALU_AND;
                        default:         illegal_instr = 1'b1;
                    endcase
                end

                //-------------------------------------------------------------
                // Loads
                //-------------------------------------------------------------
                `OPCODE_LOAD: begin
                    reg_write  = 1'b1;
                    mem_read   = 1'b1;
                    alu_src    = 1'b1;
                    mem_to_reg = `WB_MEM;
                    case (funct3)
                        `FUNCT3_LB, `FUNCT3_LH, `FUNCT3_LW,
                        `FUNCT3_LBU, `FUNCT3_LHU: ;
                        default: illegal_instr = 1'b1;
                    endcase
                end

                //-------------------------------------------------------------
                // Stores
                //-------------------------------------------------------------
                `OPCODE_STORE: begin
                    mem_write = 1'b1;
                    alu_src   = 1'b1;
                    case (funct3)
                        `FUNCT3_SB, `FUNCT3_SH, `FUNCT3_SW: ;
                        default: illegal_instr = 1'b1;
                    endcase
                end

                //-------------------------------------------------------------
                // Branches
                //-------------------------------------------------------------
                `OPCODE_BRANCH: begin
                    branch = 1'b1;
                    alu_op = `ALU_SUB;
                    case (funct3)
                        `FUNCT3_BEQ, `FUNCT3_BNE, `FUNCT3_BLT,
                        `FUNCT3_BGE, `FUNCT3_BLTU, `FUNCT3_BGEU: ;
                        default: illegal_instr = 1'b1;
                    endcase
                end

                //-------------------------------------------------------------
                // JAL
                //-------------------------------------------------------------
                `OPCODE_JAL: begin
                    reg_write  = 1'b1;
                    jump       = 1'b1;
                    mem_to_reg = `WB_PC4;
                end

                //-------------------------------------------------------------
                // JALR
                //-------------------------------------------------------------
                `OPCODE_JALR: begin
                    if (funct3 == 3'b000) begin
                        reg_write  = 1'b1;
                        jump       = 1'b1;
                        jalr       = 1'b1;
                        alu_src    = 1'b1;
                        mem_to_reg = `WB_PC4;
                    end else begin
                        illegal_instr = 1'b1;
                    end
                end

                //-------------------------------------------------------------
                // U-type
                //-------------------------------------------------------------
                `OPCODE_LUI: begin
                    reg_write = 1'b1;
                    alu_src   = 1'b1;
                    // ALU_ADD with op1='0 produces imm; kept for consistency
                end

                `OPCODE_AUIPC: begin
                    reg_write = 1'b1;
                    alu_src   = 1'b1;
                    // ALU_ADD with op1=PC produces PC+imm; kept for consistency
                end

                //-------------------------------------------------------------
                // FENCE / FENCE.I
                //-------------------------------------------------------------
               //-------------------------------------------------------------
// FENCE / FENCE.I
//-------------------------------------------------------------
`OPCODE_MISC_MEM: begin
    // FENCE (funct3=000) and FENCE.I (funct3=001) are both treated as NOPs 
    // for this simple in-order core without a cache.
    // Do NOT set illegal_instr here!
end

                //-------------------------------------------------------------
                // SYSTEM (CSR / ecall / ebreak / mret)
                //-------------------------------------------------------------
                `OPCODE_SYSTEM: begin
                    if (is_csr) begin
                        reg_write  = 1'b1;
                        mem_to_reg = `WB_CSR;
                        // CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI are funct3[1:0] = 01/10/11
                        if (funct3[1:0] == 2'b00)
                            illegal_instr = 1'b1;
                    end
                    else if (is_ecall || is_ebreak || is_mret) begin
                        // ecall/ebreak/mret are decoded above; no reg write
                    end
                    
                                       
                    else if (funct3 == 3'b000 && funct7 == 7'b0001000 && rd == 0 && rs1 == 0 && rs2 == 5'b00101) begin
                        // WFI - treated as NOP for this core
                    end
                    
                    
                    else begin
                        // Unknown SYSTEM instruction (e.g. WFI, SFENCE.VMA)
                        illegal_instr = 1'b1;
                    end
                end


                //-------------------------------------------------------------
                // Everything else
                //-------------------------------------------------------------
                default: illegal_instr = 1'b1;
            endcase
        end
    end

endmodule



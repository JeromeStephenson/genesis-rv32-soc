`timescale 1ns / 1ps


//=============================================================================
// riscv_defs.svh
// SystemVerilog header for RV32I 5-Stage Pipeline
//=============================================================================

`ifndef RISCV_DEFS_SVH
`define RISCV_DEFS_SVH

//-----------------------------------------------------------------------------
// Instruction Opcodes (7-bit)
//-----------------------------------------------------------------------------
`define OPCODE_LOAD      7'b000_0011
`define OPCODE_LOAD_FP   7'b000_0111
`define OPCODE_CUSTOM_0  7'b000_1011
`define OPCODE_MISC_MEM  7'b000_1111
`define OPCODE_OP_IMM    7'b001_0011
`define OPCODE_AUIPC     7'b001_0111
`define OPCODE_OP_IMM_32 7'b001_1011
`define OPCODE_STORE     7'b010_0011
`define OPCODE_STORE_FP  7'b010_0111
`define OPCODE_CUSTOM_1  7'b010_1011
`define OPCODE_AMO       7'b010_1111
`define OPCODE_OP        7'b011_0011
`define OPCODE_LUI       7'b011_0111
`define OPCODE_OP_32     7'b011_1011
`define OPCODE_MADD      7'b100_0011
`define OPCODE_MSUB      7'b100_0111
`define OPCODE_NMSUB     7'b100_1011
`define OPCODE_NMADD     7'b100_1111
`define OPCODE_OP_FP     7'b101_0011
`define OPCODE_RSVD_0    7'b101_0111
`define OPCODE_CUSTOM_2  7'b101_1011
`define OPCODE_BRANCH    7'b110_0011
`define OPCODE_JALR      7'b110_0111
`define OPCODE_RSVD_1    7'b110_1011
`define OPCODE_JAL       7'b110_1111
`define OPCODE_SYSTEM    7'b111_0011
`define OPCODE_RSVD_2    7'b111_0111
`define OPCODE_CUSTOM_3  7'b111_1011

//-----------------------------------------------------------------------------
// Instruction Format Types (3-bit, for imm_gen / control documentation)
//-----------------------------------------------------------------------------
`define FMT_R_TYPE        3'b000
`define FMT_I_TYPE        3'b001
`define FMT_I_TYPE_LOAD   3'b010
`define FMT_S_TYPE        3'b011
`define FMT_B_TYPE        3'b100
`define FMT_J_TYPE        3'b101
`define FMT_U_TYPE_LUI    3'b110
`define FMT_U_TYPE_AUIPC  3'b111

//-----------------------------------------------------------------------------
// ALU Operations (4-bit)
//-----------------------------------------------------------------------------
`define ALU_ADD           4'b0000
`define ALU_SUB           4'b0001
`define ALU_SLL           4'b0010
`define ALU_SLT           4'b0011
`define ALU_SLTU          4'b0100
`define ALU_XOR           4'b0101
`define ALU_SRL           4'b0110
`define ALU_SRA           4'b0111
`define ALU_OR            4'b1000
`define ALU_AND           4'b1001
`define ALU_PASS_B        4'b1010   // For LUI: pass immediate through
`define ALU_PASS_A        4'b1011   // For AUIPC: pass PC through
`define ALU_ERR           4'b1111

//-----------------------------------------------------------------------------
// Branch Condition Types (3-bit, funct3 for branches)
//-----------------------------------------------------------------------------
`define BRANCH_EQ         3'b000    // BEQ
`define BRANCH_NE         3'b001    // BNE
`define BRANCH_LT         3'b100    // BLT
`define BRANCH_GE         3'b101    // BGE
`define BRANCH_LTU        3'b110    // BLTU
`define BRANCH_GEU        3'b111    // BGEU

//-----------------------------------------------------------------------------
// Load/Store Width (funct3[1:0])
//-----------------------------------------------------------------------------
`define WIDTH_BYTE        2'b00
`define WIDTH_HALF        2'b01
`define WIDTH_WORD        2'b10

//-----------------------------------------------------------------------------
// Write-Back Mux Select (redefine WB_IMM -> WB_CSR)
//-----------------------------------------------------------------------------
`define WB_ALU            2'b00
`define WB_MEM            2'b01
`define WB_PC4            2'b10
`define WB_CSR            2'b11     // CSR read data

//-----------------------------------------------------------------------------
// CSR Operations (funct3[1:0])
//-----------------------------------------------------------------------------
`define CSR_RW            2'b01
`define CSR_RS            2'b10
`define CSR_RC            2'b11

//-----------------------------------------------------------------------------
// Trap Causes (mcause)
//-----------------------------------------------------------------------------
`define MCAUSE_ILLEGAL    32'h0000_0002
`define MCAUSE_EBREAK     32'h0000_0003
`define MCAUSE_ECALL_M    32'h0000_000B
//-----------------------------------------------------------------------------
// Forwarding Mux Select (2-bit)
//-----------------------------------------------------------------------------
`define FWD_RS            2'b00     // From register file
`define FWD_EX_MEM        2'b01     // From EX/MEM pipeline reg
`define FWD_MEM_WB        2'b10     // From MEM/WB pipeline reg

//-----------------------------------------------------------------------------
// Control Signal Constants
//-----------------------------------------------------------------------------
`define MEM_READ_EN       1'b1
`define MEM_WRITE_EN      1'b1
`define REG_WRITE_EN      1'b1

//-----------------------------------------------------------------------------
// Funct3 Constants (for clarity in case statements)
//-----------------------------------------------------------------------------
`define FUNCT3_ADD_SUB    3'b000
`define FUNCT3_SLL        3'b001
`define FUNCT3_SLT        3'b010
`define FUNCT3_SLTU       3'b011
`define FUNCT3_XOR        3'b100
`define FUNCT3_SRL_SRA    3'b101
`define FUNCT3_OR         3'b110
`define FUNCT3_AND        3'b111

`define FUNCT3_BEQ        3'b000
`define FUNCT3_BNE        3'b001
`define FUNCT3_BLT        3'b100
`define FUNCT3_BGE        3'b101
`define FUNCT3_BLTU       3'b110
`define FUNCT3_BGEU       3'b111

`define FUNCT3_LB         3'b000
`define FUNCT3_LH         3'b001
`define FUNCT3_LW         3'b010
`define FUNCT3_LBU        3'b100
`define FUNCT3_LHU        3'b101

`define FUNCT3_SB         3'b000
`define FUNCT3_SH         3'b001
`define FUNCT3_SW         3'b010

//-----------------------------------------------------------------------------
// Funct7 Constants
//-----------------------------------------------------------------------------
`define FUNCT7_ADD        7'b000_0000
`define FUNCT7_SUB        7'b010_0000
`define FUNCT7_SRL        7'b000_0000
`define FUNCT7_SRA        7'b010_0000

//-----------------------------------------------------------------------------
// NOP Instruction
//-----------------------------------------------------------------------------
`define INSTR_NOP         32'h0000_0013   // addi x0, x0, 0

//-----------------------------------------------------------------------------
// Register Addresses
//-----------------------------------------------------------------------------
`define REG_ZERO          5'd0
`define REG_RA            5'd1
`define REG_SP            5'd2
`define FWD_MEM_LOAD      2'b11     // From MEM stage load_unit output



`endif // RISCV_DEFS_SV



`timescale 1ns / 1ps
`include "riscv_defs.sv"
module  hazard_unit  (
  input  logic        clk,
  input  logic         rst_n ,
  input  logic [6:0]   if_id_opcode ,
  input  logic [4:0]  if_id_rs1,
  input  logic [4:0]  if_id_rs2,
  input  logic [4:0]  id_ex_rs1,
  input  logic [4:0]  id_ex_rs2,
  input  logic [4:0]   id_ex_rd ,
  input  logic         id_ex_mem_read ,
  input  logic         id_ex_reg_write ,
  input  logic [4:0]   ex_mem_rd ,
  input  logic         ex_mem_reg_write ,
  input  logic         ex_mem_mem_read ,
  input  logic         ex_mem_mem_write , // NEW: Needed for store-load hazard
  input  logic [4:0]   mem_wb_rd ,
  input  logic         mem_wb_reg_write ,
  input  logic         branch_taken ,
  input  logic        jump,
  input  logic         trap_take ,
  input  logic         trap_return ,
  input  logic         if_id_is_mret ,
  input  logic         id_ex_is_csr ,
  input  logic         ex_mem_csr_we ,
  output logic         pc_stall ,
  output logic         if_stall ,
  output logic         if_flush ,
  output logic         id_flush ,
  output logic [1:0]   forward_a ,
  output logic [1:0]   forward_b
);

  logic if_id_uses_rs1;
  logic if_id_uses_rs2;
  logic  load_use_hazard ;
  logic  control_hazard ;
  logic  csr_hazard ;
  logic  store_load_hazard ; // NEW: Store-to-Load hazard

  logic unused;
  assign unused =  if_id_is_mret ;

  always_comb  begin
    case ( if_id_opcode )
      `OPCODE_LUI, `OPCODE_AUIPC, `OPCODE_JAL:   if_id_uses_rs1 = 1'b0;
      default:       if_id_uses_rs1 = 1'b1;
    endcase
  end

  always_comb  begin
    case ( if_id_opcode )
      `OPCODE_OP, `OPCODE_BRANCH, `OPCODE_STORE: if_id_uses_rs2 = 1'b1;
      default:       if_id_uses_rs2 = 1'b0;
    endcase
  end

  // Standard Load-Use Hazard (Load in EX, dependent instruction in ID)
  assign  load_use_hazard  =
    id_ex_mem_read  && ( id_ex_rd  != 5'd0) &&
    ((( id_ex_rd  == if_id_rs1) && if_id_uses_rs1) ||
     (( id_ex_rd  == if_id_rs2) && if_id_uses_rs2));

  assign  control_hazard  = branch_taken  || jump ||  trap_take  ||  trap_return ;
  assign  csr_hazard      =  id_ex_is_csr  ||  ex_mem_csr_we ;

  // NEW: Conservative Store-to-Load Hazard
  // If a Store is in MEM stage and a Load is in EX stage, stall for 1 cycle.
  // This guarantees the Load reads the updated value from memory.
  assign  store_load_hazard = ex_mem_mem_write && id_ex_mem_read;

  always_comb  begin
    pc_stall  = 1'b0;
    if_stall  = 1'b0;
    if_flush  = 1'b0;
    id_flush  = 1'b0;

    if ( control_hazard ) begin
      if_flush  = 1'b1;
      id_flush  = 1'b1;
    end
    else if ( load_use_hazard ) begin
      pc_stall  = 1'b1;
      if_stall  = 1'b1;
      id_flush  = 1'b1;
    end
    else if ( store_load_hazard ) begin // NEW: Stall for Store-to-Load
      pc_stall  = 1'b1;
      if_stall  = 1'b1;
      id_flush  = 1'b1;
    end
    else if ( csr_hazard ) begin
      pc_stall  = 1'b1;
      if_stall  = 1'b1;
      id_flush  = 1'b1;
    end
  end

  // Forward A
  always_comb  begin
    if ( ex_mem_reg_write  && ( ex_mem_rd  != 5'd0) && ( ex_mem_rd  == id_ex_rs1))
      forward_a  =  ex_mem_mem_read  ? `FWD_MEM_LOAD : `FWD_EX_MEM;
    else if ( mem_wb_reg_write  && ( mem_wb_rd  != 5'd0) && ( mem_wb_rd  == id_ex_rs1))
      forward_a  = `FWD_MEM_WB;
    else
      forward_a  = `FWD_RS;
  end

  // Forward B
  always_comb  begin
    if ( ex_mem_reg_write  && ( ex_mem_rd  != 5'd0) && ( ex_mem_rd  == id_ex_rs2))
      forward_b  =  ex_mem_mem_read  ? `FWD_MEM_LOAD : `FWD_EX_MEM;
    else if ( mem_wb_reg_write  && ( mem_wb_rd  != 5'd0) && ( mem_wb_rd  == id_ex_rs2))
      forward_b  = `FWD_MEM_WB;
    else
      forward_b  = `FWD_RS;
  end
endmodule

`timescale 1ns / 1ps
`include "riscv_defs.sv"

module trap_controller (
    input  logic        ex_valid,
    input  logic        ex_is_ecall,
    input  logic        ex_is_ebreak,
    input  logic        ex_is_mret,
    input  logic        ex_illegal_instr,
    input  logic [31:0] ex_instr,
    input  logic [31:0] ex_pc,
    input  logic        mstatus_mie,
    input  logic        interrupt_pending,
    input  logic [4:0]  interrupt_cause,

    output logic        trap_take,
    output logic        trap_return,
    output logic [31:0] trap_cause,
    output logic [31:0] trap_pc,
    output logic [31:0] trap_val
);

    assign trap_return = ex_valid && ex_is_mret;

    always_comb begin
        trap_take  = 1'b0;
        trap_cause = 32'h0;
        trap_val   = 32'h0;
        trap_pc    = ex_pc;

        if (ex_valid) begin
            if (ex_illegal_instr) begin
                trap_take  = 1'b1;
                trap_cause = `MCAUSE_ILLEGAL;
                trap_val   = ex_instr;
            end
            else if (ex_is_ecall) begin
                trap_take  = 1'b1;
                trap_cause = `MCAUSE_ECALL_M;
            end
            else if (ex_is_ebreak) begin
                trap_take  = 1'b1;
                trap_cause = `MCAUSE_EBREAK;
                trap_val   = ex_pc;
            end
            // FIX: do NOT preempt MRET with an interrupt
            else if (!ex_is_mret && mstatus_mie && interrupt_pending) begin
                trap_take  = 1'b1;
                trap_cause = {1'b1, 26'b0, interrupt_cause};
            end
        end
    end

endmodule




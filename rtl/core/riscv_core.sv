`timescale 1ns / 1ps
`include "riscv_defs.sv"

module riscv_core #(
    parameter int IMEM_DEPTH = 32768,
    parameter string IMEM_HEX   = "" 
)(
    input  logic        clk,
    input  logic        rst_n,
    
    input  logic        irq_timer,
    input  logic        irq_software,
    input  logic [63:0] real_time_clock,
    input  logic        irq_external,

    // Data memory interface
    output logic [31:0] data_addr,
    output logic [31:0] data_wdata,
    output logic [3:0]  data_wstrb,
    output logic        data_wr_en,
    output logic        data_rd_en,
    input  logic [31:0] data_rdata
);

    // =====================================================================
    // Declarations
    // =====================================================================
    logic [31:0] pc_current, pc_plus4, branch_target, pc_next, trap_vec_base;
    logic [31:0] imem_instr;

    // IF/ID
    logic [31:0] if_id_pc, if_id_instr, if_id_pc_plus4;
    logic        if_id_valid;

    // ID
    logic [31:0] dec_pc, dec_pc_plus4, dec_imm, csr_rdata_id;
    logic [4:0]  dec_rs1, dec_rs2, dec_rd;
    logic [6:0]  dec_opcode, dec_funct7;
    logic [2:0]  dec_funct3;
    logic [11:0] dec_csr_addr;
    logic        dec_load, dec_valid;

    logic        cu_reg_write, cu_mem_read, cu_mem_write, cu_alu_src;
    logic [1:0]  cu_mem_to_reg, cu_csr_op;
    logic        cu_branch, cu_jump, cu_jalr, cu_is_load, cu_csr_imm;
    logic        cu_is_csr, cu_is_ecall, cu_is_ebreak, cu_is_mret, cu_illegal_instr;
    logic [3:0]  cu_alu_op;
    logic [2:0]  cu_imm_type;

    logic [31:0] rf_rs1_data, rf_rs2_data, csr_rdata_raw;

    // ID/EX
    logic [31:0] id_ex_pc, id_ex_pc_plus4, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm, id_ex_instr;
    logic [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    logic [6:0]  id_ex_opcode, id_ex_funct7;
    logic [2:0]  id_ex_funct3;
    logic [11:0] id_ex_csr_addr;
    logic [31:0] id_ex_csr_rdata;
    logic [3:0]  id_ex_alu_op;
    logic [1:0]  id_ex_mem_to_reg, id_ex_csr_op;
    logic        id_ex_alu_src, id_ex_mem_write, id_ex_mem_read, id_ex_reg_write;
    logic        id_ex_branch, id_ex_jump, id_ex_jalr, id_ex_valid, id_ex_illegal_instr;
    logic        id_ex_csr_imm, id_ex_is_csr, id_ex_is_ecall, id_ex_is_ebreak, id_ex_is_mret;

    // Hazard
    logic        haz_pc_stall, haz_if_stall, haz_if_flush, haz_id_flush;
    logic [1:0]  haz_forward_a, haz_forward_b;

    // EX
    logic [31:0] fwd_rs1_raw, fwd_rs2_raw, alu_op1, alu_op2, ex_store_data, ex_alu_result;
    logic [31:0] ex_csr_wdata, csr_mask_raw;
    logic        ex_alu_zero, ex_branch_taken, ex_is_branch, ex_is_jump, ex_is_jalr, ex_mem_flush;

    // Trap
    logic        ex_trap_take, ex_trap_return;
    logic [31:0] ex_trap_cause, ex_trap_pc, ex_trap_val;

    // CSR status & Bypass
    logic [31:0] mtvec_out, mepc_out, mstatus_out;
    logic [4:0]  interrupt_cause;
    logic        interrupt_pending;
    logic [31:0] mepc_bypass, mstatus_bypass, mtvec_bypass;

    // Trap pipeline delay
    logic        trap_take_d1, trap_take_wb, trap_ret_d1, trap_ret_wb;
    logic [31:0] trap_cause_d1, trap_cause_wb, trap_pc_d1, trap_pc_wb, trap_val_d1, trap_val_wb;

    // EX/MEM
    logic [31:0] ex_mem_pc_plus4, ex_mem_alu_result, ex_mem_store_data, ex_mem_csr_wdata, ex_mem_csr_rdata;
    logic [4:0]  ex_mem_rd;
    logic [2:0]  ex_mem_funct3;
    logic [11:0] ex_mem_csr_addr;
    logic [1:0]  ex_mem_mem_to_reg;
    logic        ex_mem_mem_write, ex_mem_mem_read, ex_mem_reg_write, ex_mem_valid, ex_mem_csr_we;

    // MEM
    logic [31:0] mem_store_aligned, mem_final_read;
    logic [3:0]  mem_store_mask;

    // MEM/WB
    logic [31:0] mem_wb_pc_plus4, mem_wb_alu_result, mem_wb_read_data, mem_wb_csr_wdata, mem_wb_csr_rdata, wb_write_data;
    logic [4:0]  mem_wb_rd;
    logic [11:0] mem_wb_csr_addr;
    logic [1:0]  mem_wb_mem_to_reg;
    logic        mem_wb_reg_write, mem_wb_valid, mem_wb_csr_we;

    // =====================================================================
    // Interrupt Masking & Trap Progress
    // =====================================================================
    logic csr_in_flight;
    assign csr_in_flight = id_ex_is_csr || ex_mem_csr_we || mem_wb_csr_we;

    logic trap_in_progress;
    // =====================================================================
    // CRITICAL FIX: 'ex_trap_take' MUST NOT appear in this expression.
    //
    // Including it creates a zero-width combinational feedback loop:
    //   ex_trap_take = 1
    //     -> trap_in_progress = 1
    //     -> mstatus_mie_effective = 0
    //     -> trap_controller deasserts ex_trap_take
    //     -> trap_in_progress = 0 -> mie_effective = 1 -> take = 1 ...
    // The signal glitches for zero time, so trap_take_d1 latches 0, the
    // CSR file never sees the trap (mcause/mepc/MIE never update), and the
    // core re-traps forever (the pulse train you saw on the waveform).
    //
    // Only REGISTERED versions of the trap/return signals (plus mret in
    // EX and in-flight CSR writes, which are loop-free) may mask MIE.
    // =====================================================================
    assign trap_in_progress =
      trap_take_d1    ||
      trap_take_wb    ||
      ex_trap_return  ||
      trap_ret_d1     ||
      trap_ret_wb     ||
      csr_in_flight;

    logic mstatus_mie_effective;
    assign mstatus_mie_effective = mstatus_bypass[3] && !trap_in_progress;

    // =====================================================================
    // PC Stage
    // =====================================================================
    assign pc_plus4      = pc_current + 32'd4;
    assign branch_target = id_ex_pc + id_ex_imm;
    assign trap_vec_base = {mtvec_bypass[31:2], 2'b00};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trap_take_d1 <= 1'b0;  trap_take_wb  <= 1'b0;
            trap_ret_d1  <= 1'b0;  trap_ret_wb   <= 1'b0;
            trap_cause_d1 <= '0;   trap_cause_wb <= '0;
            trap_pc_d1    <= '0;   trap_pc_wb    <= '0;
            trap_val_d1   <= '0;   trap_val_wb   <= '0;
        end else begin
            trap_take_d1  <= ex_trap_take;
            trap_ret_d1   <= ex_trap_return;
            trap_cause_d1 <= ex_trap_cause;
            trap_pc_d1    <= ex_trap_pc;
            trap_val_d1   <= ex_trap_val;

            trap_take_wb  <= trap_take_d1;
            trap_ret_wb   <= trap_ret_d1;
            trap_cause_wb <= trap_cause_d1;
            trap_pc_wb    <= trap_pc_d1;
            trap_val_wb   <= trap_val_d1;
        end
    end

    always_comb begin
        if (ex_trap_take) begin
            if (mtvec_bypass[1:0] == 2'b01 && ex_trap_cause[31])
                pc_next = trap_vec_base + {25'b0, ex_trap_cause[4:0], 2'b00};
            else
                pc_next = trap_vec_base;
        end
        else if (ex_trap_return)
            pc_next = mepc_bypass;
        else if (ex_branch_taken)
            pc_next = ex_is_jalr ? (ex_alu_result & ~32'd1) : branch_target;
        else
            pc_next = pc_plus4;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_current <= '0;
        else if (!haz_pc_stall) pc_current <= pc_next;
    end

    // =====================================================================
    // IF Stage
    // =====================================================================
    instruction_memory #(
        .MEM_DEPTH (IMEM_DEPTH),
        .HEX_FILE  (IMEM_HEX)
    ) u_imem (
        .pc    (pc_current),
        .instr (imem_instr)
    );

    assign if_id_pc_plus4 = if_id_pc + 32'd4;

    if_id_stage u_if_id (
        .clk(clk), .rst_n(rst_n), .stall(haz_if_stall), .flush(haz_if_flush),
        .pc(pc_current), .instr(imem_instr), .valid(1'b1),
        .if_id_pc(if_id_pc), .if_id_instr(if_id_instr), .if_id_valid(if_id_valid)
    );

    // =====================================================================
    // ID Stage
    // =====================================================================
    decoder u_decoder (
        .if_id_pc(if_id_pc), .if_id_pc_plus4(if_id_pc_plus4), .if_id_instr(if_id_instr), .if_id_valid(if_id_valid),
        .pc_out(dec_pc), .pc_plus4_out(dec_pc_plus4), .rs1(dec_rs1), .rs2(dec_rs2), .rd(dec_rd),
        .opcode(dec_opcode), .funct3(dec_funct3), .funct7(dec_funct7), .csr_addr(dec_csr_addr),
        .imm(dec_imm), .is_load(dec_load), .valid(dec_valid)
    );

    control_unit u_control (
        .opcode(dec_opcode), .funct3(dec_funct3), .funct7(dec_funct7),
        .rs1(dec_rs1), .rs2(dec_rs2), .rd(dec_rd), .valid(dec_valid),
        .reg_write(cu_reg_write), .mem_read(cu_mem_read), .mem_write(cu_mem_write),
        .alu_src(cu_alu_src), .mem_to_reg(cu_mem_to_reg), .branch(cu_branch),
        .jump(cu_jump), .jalr(cu_jalr), .alu_op(cu_alu_op), .imm_type(cu_imm_type),
        .is_load(cu_is_load), .illegal_instr(cu_illegal_instr),
        .csr_op(cu_csr_op), .csr_imm(cu_csr_imm), .is_csr(cu_is_csr),
        .is_ecall(cu_is_ecall), .is_ebreak(cu_is_ebreak), .is_mret(cu_is_mret)
    );

    register_file u_regfile (
        .clk(clk), .rst_n(rst_n),
        .rs1_addr(dec_rs1), .rs1_data(rf_rs1_data),
        .rs2_addr(dec_rs2), .rs2_data(rf_rs2_data),
        .reg_write(mem_wb_reg_write), .rd_addr(mem_wb_rd), .rd_data(wb_write_data)
    );

    // Trap side-effects applied at trap_take_d1 so the first handler
    // instruction already sees updated mcause/mepc/mstatus in ID.
    csr_file u_csr (
        .clk(clk), .rst_n(rst_n),
        .csr_addr(dec_csr_addr), .csr_rdata(csr_rdata_raw),
        .csr_we(mem_wb_csr_we), .csr_waddr(mem_wb_csr_addr), .csr_wdata(mem_wb_csr_wdata),
        .irq_external(irq_external), .irq_timer(irq_timer), .irq_software(irq_software), .irq_fast(16'b0),
        .trap_take(trap_take_d1),
        .trap_pc(trap_pc_d1),
        .trap_cause(trap_cause_d1),
        .trap_val(trap_val_d1),
        .trap_return(trap_ret_d1),
        .instr_retired(mem_wb_valid),
        .mepc_out(mepc_out), .mtvec_out(mtvec_out), .mstatus_out(mstatus_out),
        .interrupt_cause(interrupt_cause), .interrupt_pending(interrupt_pending),
        .real_time_clock(real_time_clock)
    );

    // CSR RAW hazard bypass
    always_comb begin
        csr_rdata_id = csr_rdata_raw;
        if (cu_is_csr) begin
            if (id_ex_is_csr && id_ex_csr_addr == dec_csr_addr && id_ex_valid)
                csr_rdata_id = ex_csr_wdata;
            else if (ex_mem_csr_we && ex_mem_csr_addr == dec_csr_addr)
                csr_rdata_id = ex_mem_csr_wdata;
            else if (mem_wb_csr_we && mem_wb_csr_addr == dec_csr_addr)
                csr_rdata_id = mem_wb_csr_wdata;
        end
    end

    // CSR bypass for mret / trap
    always_comb begin
        mepc_bypass = mepc_out;
        if (ex_mem_csr_we && (ex_mem_csr_addr == 12'h341)) mepc_bypass = ex_mem_csr_wdata;
        else if (mem_wb_csr_we && (mem_wb_csr_addr == 12'h341)) mepc_bypass = mem_wb_csr_wdata;
    end
    always_comb begin
        mstatus_bypass = mstatus_out;
        if (ex_mem_csr_we && (ex_mem_csr_addr == 12'h300)) mstatus_bypass = ex_mem_csr_wdata;
        else if (mem_wb_csr_we && (mem_wb_csr_addr == 12'h300)) mstatus_bypass = mem_wb_csr_wdata;
    end
    always_comb begin
        mtvec_bypass = mtvec_out;
        if (ex_mem_csr_we && (ex_mem_csr_addr == 12'h305)) mtvec_bypass = ex_mem_csr_wdata;
        else if (mem_wb_csr_we && (mem_wb_csr_addr == 12'h305)) mtvec_bypass = mem_wb_csr_wdata;
    end

    // =====================================================================
    // ID/EX Pipeline Register
    // =====================================================================
    id_ex_stage u_id_ex (
        .clk(clk), .rst_n(rst_n), .stall(1'b0), .flush(haz_id_flush),
        .id_pc(dec_pc), .id_pc_plus4(dec_pc_plus4), .id_rs1_data(rf_rs1_data), .id_rs2_data(rf_rs2_data),
        .id_imm(dec_imm), .id_rs1(dec_rs1), .id_rs2(dec_rs2), .id_rd(dec_rd),
        .id_opcode(dec_opcode), .id_funct3(dec_funct3), .id_funct7(dec_funct7),
        .id_alu_op(cu_alu_op), .id_alu_src(cu_alu_src), .id_mem_write(cu_mem_write),
        .id_mem_read(cu_mem_read), .id_reg_write(cu_reg_write), .id_mem_to_reg(cu_mem_to_reg),
        .id_branch(cu_branch), .id_jump(cu_jump), .id_jalr(cu_jalr), .id_valid(dec_valid),
        .id_illegal_instr(cu_illegal_instr), .id_csr_addr(dec_csr_addr), .id_csr_rdata(csr_rdata_id),
        .id_csr_op(cu_csr_op), .id_csr_imm(cu_csr_imm), .id_is_csr(cu_is_csr),
        .id_is_ecall(cu_is_ecall), .id_is_ebreak(cu_is_ebreak), .id_is_mret(cu_is_mret),
        .ex_pc(id_ex_pc), .ex_pc_plus4(id_ex_pc_plus4), .ex_rs1_data(id_ex_rs1_data), .ex_rs2_data(id_ex_rs2_data),
        .ex_imm(id_ex_imm), .ex_rs1(id_ex_rs1), .ex_rs2(id_ex_rs2), .ex_rd(id_ex_rd),
        .ex_opcode(id_ex_opcode), .ex_funct3(id_ex_funct3), .ex_funct7(id_ex_funct7),
        .ex_alu_op(id_ex_alu_op), .ex_alu_src(id_ex_alu_src), .ex_mem_write(id_ex_mem_write),
        .ex_mem_read(id_ex_mem_read), .ex_reg_write(id_ex_reg_write), .ex_mem_to_reg(id_ex_mem_to_reg),
        .ex_branch(id_ex_branch), .ex_jump(id_ex_jump), .ex_jalr(id_ex_jalr), .ex_valid(id_ex_valid),
        .ex_illegal_instr(id_ex_illegal_instr), .ex_csr_addr(id_ex_csr_addr), .ex_csr_rdata(id_ex_csr_rdata),
        .ex_csr_op(id_ex_csr_op), .ex_csr_imm(id_ex_csr_imm), .ex_is_csr(id_ex_is_csr),
        .ex_is_ecall(id_ex_is_ecall), .ex_is_ebreak(id_ex_is_ebreak), .ex_is_mret(id_ex_is_mret),
        .id_instr(if_id_instr), .ex_instr(id_ex_instr)
    );

    // =====================================================================
    // Hazard Unit
    // =====================================================================
    hazard_unit u_hazard (
        .clk(clk), .rst_n(rst_n),
        .if_id_opcode(dec_opcode), .if_id_rs1(dec_rs1), .if_id_rs2(dec_rs2),
        .id_ex_rs1(id_ex_rs1), .id_ex_rs2(id_ex_rs2), .id_ex_rd(id_ex_rd),
        .id_ex_mem_read(id_ex_mem_read), .id_ex_reg_write(id_ex_reg_write),
        .ex_mem_rd(ex_mem_rd), .ex_mem_reg_write(ex_mem_reg_write), .ex_mem_mem_read(ex_mem_mem_read),
        .mem_wb_rd(mem_wb_rd), .mem_wb_reg_write(mem_wb_reg_write),
        .branch_taken(ex_branch_taken), .jump(ex_is_jump),
        .trap_take(ex_trap_take), .trap_return(ex_trap_return),
        .if_id_is_mret(cu_is_mret),
        .id_ex_is_csr(id_ex_is_csr),
        .ex_mem_csr_we(ex_mem_csr_we),
        .pc_stall(haz_pc_stall), .if_stall(haz_if_stall),
        .if_flush(haz_if_flush), .id_flush(haz_id_flush),
        .forward_a(haz_forward_a), .forward_b(haz_forward_b)
    );

    // =====================================================================
    // EX Stage & EX/MEM Forwarding Data
    // =====================================================================
    logic [31:0] ex_mem_forward_data;
    always_comb begin
        case (ex_mem_mem_to_reg)
            `WB_ALU:  ex_mem_forward_data = ex_mem_alu_result;
            `WB_MEM:  ex_mem_forward_data = ex_mem_alu_result; // Load-use stalls anyway
            `WB_PC4:  ex_mem_forward_data = ex_mem_pc_plus4;
            `WB_CSR:  ex_mem_forward_data = ex_mem_csr_rdata;
            default:  ex_mem_forward_data = ex_mem_alu_result;
        endcase
    end

    always_comb begin
        case (haz_forward_a)
            `FWD_EX_MEM:   fwd_rs1_raw = ex_mem_forward_data;
            `FWD_MEM_WB:   fwd_rs1_raw = wb_write_data;
            `FWD_MEM_LOAD: fwd_rs1_raw = mem_final_read;
            default:       fwd_rs1_raw = id_ex_rs1_data;
        endcase
    end

    always_comb begin
        case (id_ex_opcode)
            `OPCODE_LUI:   alu_op1 = '0;
            `OPCODE_AUIPC: alu_op1 = id_ex_pc;
            default:       alu_op1 = fwd_rs1_raw;
        endcase
    end

    always_comb begin
        case (haz_forward_b)
            `FWD_EX_MEM:   fwd_rs2_raw = ex_mem_forward_data;
            `FWD_MEM_WB:   fwd_rs2_raw = wb_write_data;
            `FWD_MEM_LOAD: fwd_rs2_raw = mem_final_read;
            default:       fwd_rs2_raw = id_ex_rs2_data;
        endcase
    end

    assign alu_op2       = id_ex_alu_src ? id_ex_imm : fwd_rs2_raw;
    assign ex_store_data = fwd_rs2_raw;

    alu u_alu (
        .operand_1(alu_op1), .operand_2(alu_op2), .alu_op(id_ex_alu_op),
        .result(ex_alu_result), .zero(ex_alu_zero)
    );

    branch_unit u_branch (
        .opcode(id_ex_opcode), .funct3(id_ex_funct3), .rs1_data(alu_op1), .rs2_data(fwd_rs2_raw),
        .valid(id_ex_valid), .branch_taken(ex_branch_taken), .is_branch(ex_is_branch),
        .is_jump(ex_is_jump), .is_jalr(ex_is_jalr)
    );

    assign csr_mask_raw = id_ex_csr_imm ? {27'b0, id_ex_rs1} : fwd_rs1_raw;

    always_comb begin
        case (id_ex_csr_op)
            `CSR_RW: ex_csr_wdata = csr_mask_raw;
            `CSR_RS: ex_csr_wdata = id_ex_csr_rdata | csr_mask_raw;
            `CSR_RC: ex_csr_wdata = id_ex_csr_rdata & ~csr_mask_raw;
            default: ex_csr_wdata = csr_mask_raw;
        endcase
    end

    trap_controller u_trap (
        .ex_valid           (id_ex_valid),
        .ex_is_ecall        (id_ex_is_ecall),
        .ex_is_ebreak       (id_ex_is_ebreak),
        .ex_is_mret         (id_ex_is_mret),
        .ex_illegal_instr   (id_ex_illegal_instr),
        .ex_pc              (id_ex_pc),
        .mstatus_mie        (mstatus_mie_effective),
        .interrupt_pending  (interrupt_pending),
        .interrupt_cause    (interrupt_cause),
        .trap_take          (ex_trap_take),
        .trap_return        (ex_trap_return),
        .trap_cause         (ex_trap_cause),
        .trap_pc            (ex_trap_pc),
        .ex_instr           (id_ex_instr),
        .trap_val           (ex_trap_val)
    );

    // EX/MEM flush on trap/mret
    assign ex_mem_flush = ex_trap_take || ex_trap_return; 

    // =====================================================================
    // EX/MEM Pipeline Register & CSR Read-Only Write Enable
    // =====================================================================
    logic ex_csr_we_final;
    always_comb begin
        ex_csr_we_final = id_ex_is_csr;
        // CSRRS / CSRRC with rs1=x0 or uimm=0 are read-only
        if (id_ex_is_csr && 
            ((id_ex_csr_op == `CSR_RS) || (id_ex_csr_op == `CSR_RC)) && 
            (id_ex_rs1 == 5'd0)) begin
            ex_csr_we_final = 1'b0;
        end
    end

    ex_mem_stage u_ex_mem (
        .clk(clk), .rst_n(rst_n), .stall(1'b0), .flush(ex_mem_flush),
        .ex_pc_plus4(id_ex_pc_plus4), .ex_alu_result(ex_alu_result), .ex_store_data(ex_store_data),
        .ex_rd(id_ex_rd), .ex_funct3(id_ex_funct3), .ex_mem_write(id_ex_mem_write),
        .ex_mem_read(id_ex_mem_read), .ex_reg_write(id_ex_reg_write), .ex_mem_to_reg(id_ex_mem_to_reg),
        .ex_valid(id_ex_valid), .ex_csr_wdata(ex_csr_wdata), .ex_csr_addr(id_ex_csr_addr),
        .ex_csr_we(ex_csr_we_final),
        .ex_csr_rdata(id_ex_csr_rdata),
        .mem_pc_plus4(ex_mem_pc_plus4), .mem_alu_result(ex_mem_alu_result), .mem_store_data(ex_mem_store_data),
        .mem_rd(ex_mem_rd), .mem_funct3(ex_mem_funct3), .mem_mem_write(ex_mem_mem_write),
        .mem_mem_read(ex_mem_mem_read), .mem_reg_write(ex_mem_reg_write), .mem_mem_to_reg(ex_mem_mem_to_reg),
        .mem_valid(ex_mem_valid), .mem_csr_wdata(ex_mem_csr_wdata), .mem_csr_addr(ex_mem_csr_addr),
        .mem_csr_we(ex_mem_csr_we), .mem_csr_rdata(ex_mem_csr_rdata)
    );

    // =====================================================================
    // MEM Stage -> External Data Interface ONLY
    // =====================================================================
    store_unit u_store (
        .rs2_data(ex_mem_store_data), .addr_offset(ex_mem_alu_result[1:0]),
        .funct3(ex_mem_funct3), .mem_write(ex_mem_mem_write),
        .store_data(mem_store_aligned), .byte_mask(mem_store_mask)
    );

    assign data_addr  = ex_mem_alu_result;
    assign data_wdata = mem_store_aligned;
    assign data_wstrb = mem_store_mask;
    assign data_wr_en = ex_mem_mem_write;
    assign data_rd_en = ex_mem_mem_read;

    load_unit u_load (
        .mem_data(data_rdata), .addr_offset(ex_mem_alu_result[1:0]),
        .funct3(ex_mem_funct3), .mem_read(ex_mem_mem_read), .load_data(mem_final_read)
    );

    // =====================================================================
    // MEM/WB Pipeline Register
    // =====================================================================
    mem_wb_stage u_mem_wb (
        .clk(clk), .rst_n(rst_n), .stall(1'b0), .flush(1'b0),
        .mem_pc_plus4(ex_mem_pc_plus4), .mem_alu_result(ex_mem_alu_result), .mem_read_data(mem_final_read),
        .mem_rd(ex_mem_rd), .mem_reg_write(ex_mem_reg_write), .mem_mem_to_reg(ex_mem_mem_to_reg),
        .mem_valid(ex_mem_valid), .mem_csr_wdata(ex_mem_csr_wdata), .mem_csr_addr(ex_mem_csr_addr),
        .mem_csr_we(ex_mem_csr_we), .mem_csr_rdata(ex_mem_csr_rdata),
        .wb_pc_plus4(mem_wb_pc_plus4), .wb_alu_result(mem_wb_alu_result), .wb_read_data(mem_wb_read_data),
        .wb_rd(mem_wb_rd), .wb_reg_write(mem_wb_reg_write), .wb_mem_to_reg(mem_wb_mem_to_reg),
        .wb_valid(mem_wb_valid), .wb_csr_wdata(mem_wb_csr_wdata), .wb_csr_addr(mem_wb_csr_addr),
        .wb_csr_we(mem_wb_csr_we), .wb_csr_rdata(mem_wb_csr_rdata), .wb_write_data(wb_write_data)
    );
    
    
    
    
    
    
    
    
    // FreeRTOS scheduler / trap diagnostics




endmodule

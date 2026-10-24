`timescale 1ns / 1ps
`include "riscv_defs.sv"

module csr_file #(
    parameter logic [31:0] BOOT_ADDRESS = 32'h0000_0000,
    parameter logic [31:0] MARCHID_VAL  = 32'h0000_0018,
    parameter logic [31:0] MIMPID_VAL   = 32'h0000_0006,
    parameter logic [31:0] MISA_VAL     = 32'h4000_0100   // RV32I
)(
    input  logic         clk,
    input  logic         rst_n,
    
    // Asynchronous read (ID stage)
    input  logic [11:0]  csr_addr,
    output logic [31:0]  csr_rdata,
    
    // Synchronous write (WB stage)
    input  logic         csr_we,
    input  logic [11:0]  csr_waddr,
    input  logic [31:0]  csr_wdata,
    
    // Interrupt inputs
    input  logic         irq_external,
    input  logic         irq_timer,
    input  logic         irq_software,
    input  logic [15:0]  irq_fast,
    
    // Trap interface
    input  logic         trap_take,
    input  logic [31:0]  trap_pc,
    input  logic [31:0]  trap_cause,
    input  logic [31:0]  trap_val,
    input  logic         trap_return,
    
    // Instruction retire (for minstret counting)
    input  logic         instr_retired,
    
    // Status outputs
    output logic [31:0]  mepc_out,
    output logic [31:0]  mtvec_out,
    output logic [31:0]  mstatus_out,
    output logic [4:0]   interrupt_cause,
    output logic         interrupt_pending,
    
    // Real-time clock
    input  logic [63:0]  real_time_clock
);

    localparam MVENDORID = 12'hF11;
    localparam MARCHID   = 12'hF12;
    localparam MIMPID    = 12'hF13;
    localparam MHARTID   = 12'hF14;
    
    localparam CYCLE     = 12'hC00;
    localparam TIME      = 12'hC01;
    localparam INSTRET   = 12'hC02;
    localparam CYCLEH    = 12'hC80;
    localparam TIMEH     = 12'hC81;
    localparam INSTRETH  = 12'hC82;
    
    localparam MSTATUS   = 12'h300;
    localparam MSTATUSH  = 12'h310;
    localparam MISA      = 12'h301;
    localparam MIE       = 12'h304;
    localparam MTVEC     = 12'h305;
    localparam MSCRATCH  = 12'h340;
    localparam MEPC      = 12'h341;
    localparam MCAUSE    = 12'h342;
    localparam MTVAL     = 12'h343;
    localparam MIP       = 12'h344;
    
    localparam MCYCLE    = 12'hB00;
    localparam MINSTRET  = 12'hB02;
    localparam MCYCLEH   = 12'hB80;
    localparam MINSTRETH = 12'hB82;

    reg [31:0] csr_mepc;
    reg [31:0] csr_mtvec;
    reg [31:0] csr_mscratch;
    reg [31:0] csr_mcause;
    reg [31:0] csr_mtval;
    reg [63:0] csr_mcycle;
    reg [63:0] csr_minstret;
    
    reg        csr_mstatus_mie;
    reg        csr_mstatus_mpie;
    
    reg [15:0] csr_mie_mfie;
    reg        csr_mie_meie;
    reg        csr_mie_mtie;
    reg        csr_mie_msie;
    
    reg [15:0] csr_mip_mfip;
    reg        csr_mip_meip;
    reg        csr_mip_mtip;
    reg        csr_mip_msip;
    
    reg [63:0] csr_utime;

    wire [31:0] csr_mstatus = {19'b0, 2'b11, 3'b0, csr_mstatus_mpie,
                               3'b0, csr_mstatus_mie, 3'b0};
                               
    wire [31:0] csr_mie = {csr_mie_mfie, 4'b0, csr_mie_meie, 3'b0,
                           csr_mie_mtie, 3'b0, csr_mie_msie, 3'b0};
                           
    wire [31:0] csr_mip = {csr_mip_mfip, 4'b0, csr_mip_meip, 3'b0,
                           csr_mip_mtip, 3'b0, csr_mip_msip, 3'b0};

    // Async read
    always_comb begin
        case (csr_addr)
            MVENDORID: csr_rdata = 32'h0;
            MARCHID:   csr_rdata = MARCHID_VAL;
            MIMPID:    csr_rdata = MIMPID_VAL;
            MHARTID:   csr_rdata = 32'h0;
            CYCLE:     csr_rdata = csr_mcycle[31:0];
            CYCLEH:    csr_rdata = csr_mcycle[63:32];
            TIME:      csr_rdata = csr_utime[31:0];
            TIMEH:     csr_rdata = csr_utime[63:32];
            INSTRET:   csr_rdata = csr_minstret[31:0];
            INSTRETH:  csr_rdata = csr_minstret[63:32];
            MSTATUS:   csr_rdata = csr_mstatus;
            MSTATUSH:  csr_rdata = 32'h0;
            MISA:      csr_rdata = MISA_VAL;
            MIE:       csr_rdata = csr_mie;
            MTVEC:     csr_rdata = csr_mtvec;
            MSCRATCH:  csr_rdata = csr_mscratch;
            MEPC:      csr_rdata = csr_mepc;
            MCAUSE:    csr_rdata = csr_mcause;
            MTVAL:     csr_rdata = csr_mtval;
            MIP:       csr_rdata = csr_mip;
            MCYCLE:    csr_rdata = csr_mcycle[31:0];
            MCYCLEH:   csr_rdata = csr_mcycle[63:32];
            MINSTRET:  csr_rdata = csr_minstret[31:0];
            MINSTRETH: csr_rdata = csr_minstret[63:32];
            default:   csr_rdata = 32'h0;
        endcase
    end

    // Interrupt priority encoder
    // IMPORTANT FIX: Do NOT gate with csr_mstatus_mie here.
    // Let interrupt_pending mean "an enabled source is pending".
    // The trap_controller handles the global MIE check.
    always_comb begin
        interrupt_cause = 5'd0;
        
        if      (csr_mie_mfie[0]  & csr_mip_mfip[0])  interrupt_cause = 5'd16;
        else if (csr_mie_mfie[1]  & csr_mip_mfip[1])  interrupt_cause = 5'd17;
        else if (csr_mie_mfie[2]  & csr_mip_mfip[2])  interrupt_cause = 5'd18;
        else if (csr_mie_mfie[3]  & csr_mip_mfip[3])  interrupt_cause = 5'd19;
        else if (csr_mie_mfie[4]  & csr_mip_mfip[4])  interrupt_cause = 5'd20;
        else if (csr_mie_mfie[5]  & csr_mip_mfip[5])  interrupt_cause = 5'd21;
        else if (csr_mie_mfie[6]  & csr_mip_mfip[6])  interrupt_cause = 5'd22;
        else if (csr_mie_mfie[7]  & csr_mip_mfip[7])  interrupt_cause = 5'd23;
        else if (csr_mie_mfie[8]  & csr_mip_mfip[8])  interrupt_cause = 5'd24;
        else if (csr_mie_mfie[9]  & csr_mip_mfip[9])  interrupt_cause = 5'd25;
        else if (csr_mie_mfie[10] & csr_mip_mfip[10]) interrupt_cause = 5'd26;
        else if (csr_mie_mfie[11] & csr_mip_mfip[11]) interrupt_cause = 5'd27;
        else if (csr_mie_mfie[12] & csr_mip_mfip[12]) interrupt_cause = 5'd28;
        else if (csr_mie_mfie[13] & csr_mip_mfip[13]) interrupt_cause = 5'd29;
        else if (csr_mie_mfie[14] & csr_mip_mfip[14]) interrupt_cause = 5'd30;
        else if (csr_mie_mfie[15] & csr_mip_mfip[15]) interrupt_cause = 5'd31;
        else if (csr_mie_meie & csr_mip_meip)         interrupt_cause = 5'd11;
        else if (csr_mie_msie & csr_mip_msip)         interrupt_cause = 5'd3;
        else if (csr_mie_mtie & csr_mip_mtip)         interrupt_cause = 5'd7;
    end
    
    assign interrupt_pending = (interrupt_cause != 5'd0);
    assign mepc_out    = csr_mepc;
    assign mtvec_out   = csr_mtvec;
    assign mstatus_out = csr_mstatus;

    // =========================================================================
    // Next-state variables for correct retirement ordering
    // =========================================================================
    logic         n_mie, n_mpie, n_meie, n_mtie, n_msie;
    logic         n_meip, n_mtip, n_msip;
    logic [31:0]  n_mepc, n_mcause, n_mtval, n_mtvec, n_mscratch;
    logic [15:0]  n_mfie, n_mfip;
    logic [63:0]  n_mcycle, n_minstret;

    always_comb begin
        // 0) Defaults: hold current state or track inputs
        n_mie      = csr_mstatus_mie;
        n_mpie     = csr_mstatus_mpie;
        n_mepc     = csr_mepc;
        n_mcause   = csr_mcause;
        n_mtval    = csr_mtval;
        n_mtvec    = csr_mtvec;
        n_mscratch = csr_mscratch;
        n_mfie     = csr_mie_mfie;
        n_meie     = csr_mie_meie;
        n_mtie     = csr_mie_mtie;
        n_msie     = csr_mie_msie;
        n_mfip     = irq_fast;
        n_meip     = irq_external;
        n_mtip     = irq_timer;
        n_msip     = irq_software;
        n_mcycle   = csr_mcycle + 64'd1;
        n_minstret = csr_minstret;

        if (instr_retired && !(csr_we && ((csr_waddr == MINSTRET) || (csr_waddr == MINSTRETH))))
            n_minstret = csr_minstret + 64'd1;

        // 1) OLDER instruction's CSR write retires FIRST
        if (csr_we) begin
            case (csr_waddr)
                MSTATUS: begin
                    n_mie  = csr_wdata[3];
                    n_mpie = csr_wdata[7];
                end
                MIE: begin
                    n_mfie = csr_wdata[31:16];
                    n_meie = csr_wdata[11];
                    n_mtie = csr_wdata[7];
                    n_msie = csr_wdata[3];
                end
                MTVEC:     n_mtvec    = {csr_wdata[31:2], 1'b0, csr_wdata[0]};
                MSCRATCH:  n_mscratch = csr_wdata;
                MEPC:      n_mepc     = {csr_wdata[31:2], 2'b00};
                MCAUSE:    n_mcause   = csr_wdata;
                MTVAL:     n_mtval    = csr_wdata;
                MCYCLE:    n_mcycle   = {csr_mcycle[63:32], csr_wdata};
                MCYCLEH:   n_mcycle   = {csr_wdata, csr_mcycle[31:0]};
                MINSTRET:  n_minstret = {csr_minstret[63:32], csr_wdata};
                MINSTRETH: n_minstret = {csr_wdata, csr_minstret[31:0]};
                MIP: begin
                    n_msip = csr_wdata[3];
                    n_mfip = csr_wdata[31:16];
                end
                default: ;
            endcase
        end

        // 2) THEN trap / mret side-effects, on top of the written value
        if (trap_take) begin
            n_mepc   = {trap_pc[31:2], 2'b00};
            n_mcause = trap_cause;
            n_mtval  = trap_val;
            n_mpie   = n_mie;       // MPIE = MIE *after* the older write
            n_mie    = 1'b0;
        end
        else if (trap_return) begin
            n_mie  = n_mpie;        // MIE = MPIE *after* the older write
            n_mpie = 1'b1;
        end
    end

    // =========================================================================
    // Synchronous CSR update
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_mepc         <= BOOT_ADDRESS;
            csr_mtvec        <= 32'h0;
            csr_mscratch     <= 32'h0;
            csr_mcause       <= 32'h0;
            csr_mtval        <= 32'h0;
            csr_mcycle       <= 64'h0;
            csr_minstret     <= 64'h0;
            csr_mstatus_mie  <= 1'b0;
            csr_mstatus_mpie <= 1'b1;
            csr_mie_mfie     <= 16'h0;
            csr_mie_meie     <= 1'b0;
            csr_mie_mtie     <= 1'b0;
            csr_mie_msie     <= 1'b0;
            csr_mip_mfip     <= 16'h0;
            csr_mip_meip     <= 1'b0;
            csr_mip_mtip     <= 1'b0;
            csr_mip_msip     <= 1'b0;
            csr_utime        <= 64'h0;
        end 
        else begin
            csr_mepc         <= n_mepc;
            csr_mcause       <= n_mcause;
            csr_mtval        <= n_mtval;
            csr_mtvec        <= n_mtvec;
            csr_mscratch     <= n_mscratch;
            csr_mstatus_mie  <= n_mie;
            csr_mstatus_mpie <= n_mpie;
            csr_mie_mfie     <= n_mfie;
            csr_mie_meie     <= n_meie;
            csr_mie_mtie     <= n_mtie;
            csr_mie_msie     <= n_msie;
            csr_mip_mfip     <= n_mfip;
            csr_mip_meip     <= n_meip;
            csr_mip_mtip     <= n_mtip;
            csr_mip_msip     <= n_msip;
            csr_mcycle       <= n_mcycle;
            csr_minstret     <= n_minstret;
            csr_utime        <= real_time_clock;
        end
    end

endmodule

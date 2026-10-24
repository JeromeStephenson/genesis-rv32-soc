`timescale 1ns / 1ps
module clint  #(
    parameter int ADDR_WIDTH = 32
)(
  input  logic                   clk,
  input  logic                   rst_n,
    // Bus interface
  input  logic  [ADDR_WIDTH-1:0] addr,
  input  logic  [31:0]           wdata,
  input  logic  [3:0]            wstrb,
  input  logic                   wr_en,
  input  logic                   rd_en,
    output logic [31:0]           rdata,
    output logic                  rvalid,
    // Interrupt outputs
    output logic                  irq_timer,
    output logic                  irq_software,
    // Current timer value
    output logic [63:0]           mtime_out
);

    // ============================================================
    // CLINT REGISTER MAP
    // ============================================================
    localparam logic [15:0] REG_MSIP        = 16'h0000;
    localparam logic [15:0] REG_MTIMECMP_LO = 16'h4000;
    localparam logic [15:0] REG_MTIMECMP_HI = 16'h4004;
    localparam logic [15:0] REG_MTIME_LO    = 16'hBFF8;
    localparam logic [15:0] REG_MTIME_HI    = 16'hBFFC;

    // ============================================================
    // INTERNAL REGISTERS
    // ============================================================
    logic [31:0] msip_reg;
    logic [63:0] mtime;
    logic [63:0] mtimecmp;

    // ============================================================
    // OUTPUT: MTIME
    // ============================================================
    assign mtime_out = mtime;

    // ============================================================
    // ADDRESS / WRITE CONTROL
    // ============================================================
    logic addr_aligned;
    logic write_word;
    assign addr_aligned = (addr[1:0] == 2'b00);
    
    // Only accept a complete 32-bit write
    assign write_word = (&wstrb);

    // ============================================================
    // WRITE ENABLE SIGNALS
    // ============================================================
    logic msip_wr;
    logic mtime_lo_wr;
    logic mtime_hi_wr;
    logic mtimecmp_lo_wr;
    logic mtimecmp_hi_wr;

    assign msip_wr = addr_aligned && write_word && wr_en && (addr[15:0] == REG_MSIP);
    
    assign mtimecmp_lo_wr = addr_aligned && write_word && wr_en && (addr[15:0] == REG_MTIMECMP_LO);
    assign mtimecmp_hi_wr = addr_aligned && write_word && wr_en && (addr[15:0] == REG_MTIMECMP_HI);
    
    assign mtime_lo_wr = addr_aligned && write_word && wr_en && (addr[15:0] == REG_MTIME_LO);
    assign mtime_hi_wr = addr_aligned && write_word && wr_en && (addr[15:0] == REG_MTIME_HI);

    // ============================================================
    // MSIP REGISTER (Software Interrupt)
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msip_reg <= 32'h0000_0000;
        end else if (msip_wr) begin
            msip_reg <= wdata;
        end
    end
    assign irq_software = msip_reg[0];

    // ============================================================
    // MTIME COUNTER (Real-time clock)
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime <= 64'h0000_0000_0000_0000;
        end else begin
            if (mtime_lo_wr) begin
                mtime[31:0] <= wdata;
            end
            if (mtime_hi_wr) begin
                mtime[63:32] <= wdata;
            end
            // Increment only when MTIME itself is not being written.
            if (!mtime_lo_wr && !mtime_hi_wr) begin
                mtime <= mtime + 64'd1;
            end
        end
    end

    // ============================================================
    // MTIMECMP REGISTER (Timer Compare)
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialized to all 1's so timer interrupt is initially disabled
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF;
        end else begin
            if (mtimecmp_lo_wr) begin
                mtimecmp[31:0] <= wdata;
            end
            if (mtimecmp_hi_wr) begin
                mtimecmp[63:32] <= wdata;
            end
        end
    end

    // ============================================================
    // TIMER INTERRUPT GENERATION
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_timer <= 1'b0;
        end else begin
            // Temporarily deassert if software is actively modifying the registers
            if (mtime_lo_wr || mtime_hi_wr || mtimecmp_lo_wr || mtimecmp_hi_wr) begin
                irq_timer <= 1'b0;
            end else begin
                irq_timer <= (mtime >= mtimecmp);
            end
        end
    end

    // ============================================================
    // COMBINATIONAL READ (FIXED FOR FREERTOS COMPATIBILITY)
    // ============================================================
    // The core expects same-cycle read responses. 
    // rdata is driven combinationally based on the current address.
    always_comb begin
        rdata = 32'h0000_0000;
        if (rd_en && addr_aligned) begin
            case (addr[15:0])
                REG_MSIP:        rdata = msip_reg;
                REG_MTIMECMP_LO: rdata = mtimecmp[31:0];
                REG_MTIMECMP_HI: rdata = mtimecmp[63:32];
                REG_MTIME_LO:    rdata = mtime[31:0];
                REG_MTIME_HI:    rdata = mtime[63:32];
                default:         rdata = 32'h0000_0000;
            endcase
        end
    end

    // rvalid is asserted immediately when a read is requested
    assign rvalid = rd_en && addr_aligned;

endmodule

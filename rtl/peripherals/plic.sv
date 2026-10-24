`timescale 1ns / 1ps

module plic (
  input  logic         clk,
  input  logic         rst_n,
  input  logic  [31:0] addr,
  input  logic  [31:0] wdata,
  input  logic         we,
  input  logic         rd_en,      // Gates read side-effects safely
  output logic [31:0]  rdata,
  input  logic  [31:0] irq_sources,
  output logic         plic_irq,
  output logic [4:0]   plic_irq_id
);
    localparam int SRCS = 32;
    
    // SiFive Standard Address Map
    localparam logic [31:0] PLIC_PRIO_BASE  = 32'h0C00_0000;
    localparam logic [31:0] PLIC_PENDING    = 32'h0C00_1000;
    localparam logic [31:0] PLIC_ENABLE     = 32'h0C00_2000;
    localparam logic [31:0] PLIC_THRESHOLD  = 32'h0C20_0000;
    localparam logic [31:0] PLIC_CLAIM      = 32'h0C20_0004;

    logic [SRCS-1:0] pending;
    logic [SRCS-1:0] enable;
    logic [7:0]      src_prio [0:SRCS-1];
    logic [7:0]      threshold;
    logic [SRCS-1:0] effective_prio;

    // Priority Encoder
    generate
        for (genvar i = 0; i < SRCS; i++) begin : gen_eff
            assign effective_prio[i] = (src_prio[i] > threshold) && pending[i] && enable[i];
        end
    endgenerate

    always_comb begin
        plic_irq_id = 5'd0;
        // Higher index wins (standard PLIC behavior)
        for (int j = 0; j < SRCS; j++) begin
            if (effective_prio[j]) plic_irq_id = j[4:0];
        end
    end
    
    assign plic_irq = |effective_prio;

    // Combinational Read Logic
    always_comb begin
        rdata = 32'h0;
        if (addr == PLIC_PENDING)
            rdata = {1'b0, pending};
        else if (addr == PLIC_ENABLE)
            rdata = {1'b0, enable};
        else if (addr == PLIC_THRESHOLD) 
            rdata = {24'h0, threshold};
        else if (addr == PLIC_CLAIM) 
            rdata = {27'h0, plic_irq_id};
        else if (addr >= PLIC_PRIO_BASE + 4 && addr <= PLIC_PRIO_BASE + (SRCS*4))
            rdata = {24'h0, src_prio[(addr - PLIC_PRIO_BASE) >> 2]};
    end

    // ------------------------------------------------------------------------
    // CRITICAL FIX: Latch the claimed ID to avoid combinational race conditions
    // ------------------------------------------------------------------------
    logic [4:0] claim_id_latched;
    logic       claim_read_active;

    // Sequential Write & Claim Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable            <= 32'h0; 
            threshold         <= 8'h0; 
            pending           <= 32'h0;
            claim_id_latched  <= 5'd0;
            claim_read_active <= 1'b0;
            for (int k = 0; k < SRCS; k++) src_prio[k] <= 8'h0;
        end else begin
            // 1. Always latch incoming interrupt sources
            pending <= pending | irq_sources; 
            
            // 2. Default deassert claim latch
            claim_read_active <= 1'b0;

            // 3. Handle Writes
            if (we) begin
                if (addr == PLIC_ENABLE) 
                    enable <= wdata;
                else if (addr == PLIC_THRESHOLD) 
                    threshold <= wdata[7:0];
                else if (addr == PLIC_CLAIM) begin 
                    // Software writes back the claimed ID to complete the interrupt
                    if (wdata[4:0] < SRCS) pending[wdata[4:0]] <= 1'b0;
                end
                else if (addr >= PLIC_PRIO_BASE + 4 && addr <= PLIC_PRIO_BASE + (SRCS*4))
                    src_prio[(addr - PLIC_PRIO_BASE) >> 2] <= wdata[7:0];
            end 
          
          
            
            // 4. Handle Reads (Specifically CLAIM)
            else if (rd_en) begin
                if (addr == PLIC_CLAIM) begin
                    // Latch the ID being read *this exact cycle*
                    claim_id_latched  <= plic_irq_id;
                    claim_read_active <= 1'b1;
                end
            end

            // 5. Clear the pending bit safely on the NEXT cycle using the latched ID.
            // This prevents a race condition where plic_irq_id changes combinationally 
            // before the clock edge, which would clear the wrong interrupt.
            if (claim_read_active && (claim_id_latched != 5'd0)) begin
                pending[claim_id_latched] <= 1'b0;
            end
        end
    end
endmodule

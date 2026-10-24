`timescale 1ns / 1ps

module gpio (
    input  logic        clk,
    input  logic        rst_n,

    // Bus interface - 32-bit address, peripherals decode internally
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    output logic [31:0] rdata,

    // GPIO pins
    output logic [31:0] gpio_out,
    input  logic [31:0] gpio_in,

    // Interrupt
    output logic        gpio_irq
);

    localparam logic [4:0] REG_DIR      = 5'h00;
    localparam logic [4:0] REG_OUT      = 5'h04;
    localparam logic [4:0] REG_IN       = 5'h08;
    localparam logic [4:0] REG_IRQ_MASK = 5'h0C;
    localparam logic [4:0] REG_IRQ_STAT = 5'h10;

    logic [31:0] dir_reg;
    logic [31:0] out_reg;
    logic [31:0] in_reg;
    logic [31:0] in_reg_prev;
    logic [31:0] irq_mask;
    logic [31:0] irq_status;

    // Read
    always_comb begin
        case (addr[4:0])
            REG_DIR:      rdata = dir_reg;
            REG_OUT:      rdata = out_reg;
            REG_IN:       rdata = in_reg;
            REG_IRQ_MASK: rdata = irq_mask;
            REG_IRQ_STAT: rdata = irq_status;
            default:      rdata = 32'h0;
        endcase
    end

    // Single always_ff for all state - irq_status merged here
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dir_reg      <= 32'h0;
            out_reg      <= 32'h0;
            irq_mask     <= 32'h0;
            in_reg       <= 32'h0;
            in_reg_prev  <= 32'h0;
            irq_status   <= 32'h0;
        end else begin
            // Input sync
            in_reg      <= gpio_in;
            in_reg_prev <= in_reg;

            // Default: accumulate edge-detected interrupts
           if (we && (addr[4:0] == REG_IRQ_STAT)) begin
                irq_status <= (irq_status | (irq_mask & (in_reg ^ in_reg_prev))) & ~wdata;
            end else begin
                irq_status <= irq_status | (irq_mask & (in_reg ^ in_reg_prev));
            end

            // Write decode - W1C on IRQ_STAT takes priority
            if (we) begin
                case (addr[4:0])
                    REG_DIR:      dir_reg  <= wdata;
                    REG_OUT:      out_reg  <= wdata;
                    REG_IRQ_MASK: irq_mask <= wdata;
                    REG_IRQ_STAT:; // W1C
                    default: ;
                endcase
            end
        end
    end

    assign gpio_out = out_reg;
    assign gpio_irq = |irq_status;

endmodule



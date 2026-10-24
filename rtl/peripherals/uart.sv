`timescale 1ns / 1ps

module uart (
    input  logic        clk,
    input  logic        rst_n,

    // Bus interface
    input  logic        rd_en,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    output logic [31:0] rdata,

    // UART pins
    output logic        tx,
    input  logic        rx,

    // Interrupt (TX empty or RX ready)
    output logic        uart_irq
);

    // -------------------------------------------------------------------------
    // Register map
    // -------------------------------------------------------------------------
    localparam logic [3:0] REG_DATA = 4'h0;  // W: TX data, R: RX data
    localparam logic [3:0] REG_STAT = 4'h4;  // [0]=tx_empty, [1]=rx_ready, [2]=tx_busy, [3]=rx_busy
    localparam logic [3:0] REG_BAUD = 4'h8;  // Baud divisor
    localparam logic [3:0] REG_CTRL = 4'hC;  // [0]=tx_en, [1]=rx_en, [2]=irq_en

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    logic [7:0]  tx_data_reg;
    logic [7:0]  rx_data_reg;
    logic [15:0] baud_div;
    logic        tx_enable;
    logic        rx_enable;
    logic        irq_enable;

    logic        tx_empty;      // now combinational
    logic        rx_ready;
    logic        tx_busy;
    logic        rx_busy;

    // -------------------------------------------------------------------------
    // RX synchronizer (3-stage)
    // -------------------------------------------------------------------------
    logic [2:0] rx_sync;
    logic       rx_clean;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rx_sync <= 3'b111;
        else        rx_sync <= {rx_sync[1:0], rx};
    end
    assign rx_clean = rx_sync[2];

    // -------------------------------------------------------------------------
    // Combinatorial read
    // -------------------------------------------------------------------------
    always_comb begin
        case (addr[3:0])
            REG_DATA: rdata = {24'b0, rx_data_reg};
            REG_STAT: rdata = {28'b0, rx_busy, tx_busy, rx_ready, tx_empty};
            REG_BAUD: rdata = {16'b0, baud_div};
            REG_CTRL: rdata = {29'b0, irq_enable, rx_enable, tx_enable};
            default:  rdata = 32'h0;
        endcase
    end

    assign uart_irq = irq_enable & (tx_empty | rx_ready);

    // -------------------------------------------------------------------------
    // TX State Machine (8-N-1)  -- FIXED
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP, TX_DONE} tx_state_t;
    tx_state_t tx_state;
    logic [2:0]  tx_bit_cnt;
    logic [15:0] tx_baud_cnt;
    logic [7:0]  tx_shift;
    logic        tx_pending;    // 1 = CPU has written a byte waiting to go

    assign tx_empty = !tx_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state    <= TX_IDLE;
            tx_pending  <= 1'b0;
            tx_busy     <= 1'b0;
            tx          <= 1'b1;
            tx_baud_cnt <= '0;
            tx_bit_cnt  <= '0;
            tx_shift    <= '0;
            tx_data_reg <= '0;
        end else begin
            // Capture write to TX buffer (only if buffer is empty)
            if (we && (addr[3:0] == REG_DATA) && !tx_pending) begin
                tx_shift    <= wdata[7:0];
                tx_data_reg <= wdata[7:0];
                tx_pending  <= 1'b1;
            end

            case (tx_state)
                TX_IDLE: begin
                    tx_busy <= 1'b0;
                    tx      <= 1'b1;
                    if (tx_pending && tx_enable) begin
                        tx_busy     <= 1'b1;
                        tx_state    <= TX_START;
                        tx_baud_cnt <= baud_div - 1'b1;
                    end
                end

                TX_START: begin
                    tx <= 1'b0; // start bit
                    if (tx_baud_cnt == 0) begin
                        tx_state    <= TX_DATA;
                        tx_baud_cnt <= baud_div - 1'b1;
                        tx_bit_cnt  <= 3'd7;
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt - 1'b1;
                    end
                end

                TX_DATA: begin
                    tx <= tx_shift[0];
                    if (tx_baud_cnt == 0) begin
                        tx_shift    <= tx_shift >> 1;
                        tx_baud_cnt <= baud_div - 1'b1;
                        if (tx_bit_cnt == 0)
                            tx_state <= TX_STOP;
                        else
                            tx_bit_cnt <= tx_bit_cnt - 1'b1;
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt - 1'b1;
                    end
                end

                TX_STOP: begin
                    tx <= 1'b1;
                    if (tx_baud_cnt == 0) begin
                        tx_state <= TX_DONE;
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt - 1'b1;
                    end
                end

                TX_DONE: begin
                    tx_pending <= 1'b0;   // buffer now empty
                    tx_busy    <= 1'b0;
                    tx_state   <= TX_IDLE;
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // RX State Machine (8-N-1), samples at bit-center
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP, RX_DONE} rx_state_t;
    rx_state_t rx_state;
    logic [2:0]  rx_bit_cnt;
    logic [15:0] rx_baud_cnt;
    logic [7:0]  rx_shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state    <= RX_IDLE;
            rx_ready    <= 1'b0;
            rx_busy     <= 1'b0;
            rx_baud_cnt <= '0;
            rx_bit_cnt  <= '0;
            rx_shift    <= '0;
            rx_data_reg <= '0;
        end else begin
            // Reading DATA register clears rx_ready
            if (rd_en && (addr[3:0] == REG_DATA)) begin
                rx_ready <= 1'b0;
            end

            case (rx_state)
                RX_IDLE: begin
                    rx_busy <= 1'b0;
                    if (!rx_clean && rx_enable && !rx_ready) begin
                        rx_busy     <= 1'b1;
                        rx_state    <= RX_START;
                        rx_baud_cnt <= (baud_div >> 1) - 1'b1; // center of start bit
                    end
                end

                RX_START: begin
                    if (rx_baud_cnt == 0) begin
                        if (!rx_clean) begin
                            rx_state    <= RX_DATA;
                            rx_baud_cnt <= baud_div - 1'b1;
                            rx_bit_cnt  <= 3'd7;
                        end else begin
                            // False start bit
                            rx_state <= RX_IDLE;
                            rx_busy  <= 1'b0;
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1'b1;
                    end
                end

                RX_DATA: begin
                    if (rx_baud_cnt == 0) begin
                        rx_shift    <= {rx_clean, rx_shift[7:1]};
                        rx_baud_cnt <= baud_div - 1'b1;
                        if (rx_bit_cnt == 0)
                            rx_state <= RX_STOP;
                        else
                            rx_bit_cnt <= rx_bit_cnt - 1'b1;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1'b1;
                    end
                end

                RX_STOP: begin
                    if (rx_baud_cnt == 0) begin
                        if (rx_clean) begin
                            rx_data_reg <= rx_shift;
                            rx_ready    <= 1'b1;
                        end
                        // else: framing error, discard
                        rx_state <= RX_DONE;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1'b1;
                    end
                end

                RX_DONE: begin
                    rx_busy  <= 1'b0;
                    rx_state <= RX_IDLE;
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Control register writes
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_div  <= 16'd434; // default: 50 MHz / 115200
            tx_enable <= 1'b1;
            rx_enable <= 1'b1;
            irq_enable<= 1'b0;
        end else if (we) begin
            case (addr[3:0])
                REG_BAUD: baud_div  <= wdata[15:0];
                REG_CTRL: {irq_enable, rx_enable, tx_enable} <= {wdata[2], wdata[1], wdata[0]};
                default: ;
            endcase
        end
    end

endmodule

`timescale 1ns / 1ps

module riscv_soc #(
    parameter int IMEM_DEPTH  = 32768,
    parameter int DMEM_DEPTH  = 32768,
    parameter string IMEM_HEX = "",
    parameter string DMEM_HEX = ""
)(
    input  logic        clk,
    input  logic        rst_n,


    // UART pins
    output logic        uart_tx,
    input  logic        uart_rx,

    // GPIO pins
    output logic [31:0] gpio_out,
    input  logic [31:0] gpio_in
);

    // -------------------------------------------------------------------------
    // Core -> Fabric signals (DECLARED FIRST)
    // -------------------------------------------------------------------------
    logic [31:0] core_addr, core_wdata;
    logic [3:0]  core_wstrb;
    logic        core_wr_en, core_rd_en;
    logic [31:0] core_rdata;

    // -------------------------------------------------------------------------
    // Address decode regions (NOW uses already-declared core_addr)
    // -------------------------------------------------------------------------
    logic is_dmem, is_clint, is_plic, is_uart, is_gpio;

   // Update is_plic to cover the full SiFive PLIC context range
localparam logic [31:0] DMEM_BASE  = 32'h8000_0000;
localparam int          DMEM_BYTES = DMEM_DEPTH * 4;   // 131072 for DMEM_DEPTH=32768

always_comb begin
    is_dmem  = (core_addr >= DMEM_BASE) && (core_addr < (DMEM_BASE + DMEM_BYTES));
    is_clint = (core_addr[31:16] == 16'h0200);
    is_plic  = (core_addr >= 32'h0C00_0000) && (core_addr <= 32'h0C20_000F);
    is_uart  = (core_addr[31:12] == 20'h10000);
    is_gpio  = (core_addr[31:12] == 20'h10001);
end

    // -------------------------------------------------------------------------
    // Peripheral readback signals
    // -------------------------------------------------------------------------
    logic [63:0] clint_mtime;
    logic        clint_timer_irq;
    logic        clint_soft_irq;

    logic [31:0] clint_rdata;
    logic        clint_rvalid;

    logic [31:0] plic_rdata;
    logic        plic_irq;
    logic [4:0]  plic_irq_id;

    logic [31:0] uart_rdata;
    logic        uart_irq;

    logic [31:0] gpio_rdata;
    logic        gpio_irq;

   
    // -------------------------------------------------------------------------
    // Core
    // -------------------------------------------------------------------------
    riscv_core #(
        .IMEM_DEPTH (IMEM_DEPTH),
        .IMEM_HEX   (IMEM_HEX)
    ) u_core (
        .clk             (clk),
        .rst_n           (rst_n),
        .irq_timer       (clint_timer_irq),
        .irq_software    (clint_soft_irq),
        .irq_external    (plic_irq),
        .real_time_clock (clint_mtime),
        .data_addr       (core_addr),
        .data_wdata      (core_wdata),
        .data_wstrb      (core_wstrb),
        .data_wr_en      (core_wr_en),
        .data_rd_en      (core_rd_en),
        .data_rdata      (core_rdata)
    );






    // -------------------------------------------------------------------------
    // XIP (Execute-In-Place) shadow read port for .rodata / .srodata
    // The linker placed read-only data in IMEM (0x0000_xxxx). We need a way
    // for the data bus to read it.
    // -------------------------------------------------------------------------
    logic [31:0] imem_rdata;
    instruction_memory #(
        .MEM_DEPTH (IMEM_DEPTH),
        .HEX_FILE  (IMEM_HEX)
    ) u_imem_ro (
        // Mask address to 128KB and force word-alignment to prevent 
        // the IMEM module's internal out-of-bounds assertions from 
        // firing when the core accesses DMEM (0x8000_xxxx).
        .pc    (core_addr & 32'h0001_FFFC), 
        .instr (imem_rdata)
    );

    // -------------------------------------------------------------------------
    // Data memory (SRAM at 0x8000_0000)
    // -------------------------------------------------------------------------
    // ... (keep your existing simple_data_mem here) ...















    // -------------------------------------------------------------------------
    // Data memory (SRAM at 0x0000_0000)
    // -------------------------------------------------------------------------
    logic [31:0] dmem_rdata;
    logic        dmem_wr_en;

    assign dmem_wr_en = core_wr_en & is_dmem;

    simple_data_mem #(
        .MEM_SIZE_BYTES (DMEM_DEPTH * 4),
        .HEX_FILE       (DMEM_HEX)
    ) u_dmem (
        .clk        (clk),
        .rst_n      (rst_n),
        .addr       (core_addr),
        .write_data (core_wdata),
        .byte_mask  (core_wstrb),
        .mem_write  (dmem_wr_en),
        .read_data  (dmem_rdata)
    );

    // -------------------------------------------------------------------------
    // CLINT (0x0200_0000)
    // -------------------------------------------------------------------------
    clint u_clint (
        .clk          (clk),
        .rst_n        (rst_n),
        .addr         (core_addr),
        .wdata        (core_wdata),
        .wstrb        (core_wstrb),
        .wr_en        (core_wr_en & is_clint),
        .rd_en        (core_rd_en & is_clint),
        .rdata        (clint_rdata),
        .rvalid       (clint_rvalid),
        .irq_timer    (clint_timer_irq),
        .irq_software (clint_soft_irq),
        .mtime_out    (clint_mtime)
    );

    // -------------------------------------------------------------------------
    // PLIC (0x0C00_0000)
    // -------------------------------------------------------------------------
       plic u_plic (
        .clk        (clk),
        .rst_n      (rst_n),
        .addr       (core_addr),
        .wdata      (core_wdata),
        .we         (core_wr_en & is_plic),
        .rd_en      (core_rd_en & is_plic), // ADDED
        .rdata      (plic_rdata),
        .irq_sources({24'b0, gpio_irq, uart_irq, 6'b0}),
        .plic_irq   (plic_irq),
        .plic_irq_id(plic_irq_id)
    );


    // -------------------------------------------------------------------------
    // UART (0x1000_0000)
    // -------------------------------------------------------------------------
    uart u_uart (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr     (core_addr),
        .wdata    (core_wdata),
        .we       (core_wr_en & is_uart),
         .rd_en    (core_rd_en & is_uart),   // FIX
        .rdata    (uart_rdata),
        .tx       (uart_tx),
        .rx       (uart_rx),
        .uart_irq (uart_irq)
    );

    // -------------------------------------------------------------------------
    // GPIO (0x1000_1000)
    // -------------------------------------------------------------------------
    gpio u_gpio (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr     (core_addr),
        .wdata    (core_wdata),
        .we       (core_wr_en & is_gpio),
        .rdata    (gpio_rdata),
        .gpio_out (gpio_out),
        .gpio_in  (gpio_in),
        .gpio_irq (gpio_irq)
    );



    // -------------------------------------------------------------------------
    // Read data mux back to core
    // -------------------------------------------------------------------------
       // -------------------------------------------------------------------------
    // Read data mux back to core
    // -------------------------------------------------------------------------
    always_comb begin
        if (is_clint)      core_rdata = clint_rdata;
        else if (is_plic)  core_rdata = plic_rdata;
        else if (is_uart)  core_rdata = uart_rdata;
        else if (is_gpio)  core_rdata = gpio_rdata;
        else if (core_addr < 32'h0002_0000) core_rdata = imem_rdata; // XIP rodata/srodata
        else               core_rdata = dmem_rdata;
    end
    
    
    
    
    
    
    
    
    
        initial begin
        #100; // Wait for memory to initialize
        $display("[DEBUG] DMEM Word 0 (0x80000000) = 0x%08x", u_dmem.mem[0]);
        $display("[DEBUG] DMEM Word 1 (0x80000004) = 0x%08x", u_dmem.mem[1]);
    end

endmodule



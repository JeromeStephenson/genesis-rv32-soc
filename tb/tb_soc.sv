`timescale 1ns / 1ps
module tb_soc;
    logic clk;
    logic rst_n;
    logic uart_tx;
    logic uart_rx;
    logic [31:0] gpio_out;
    logic [31:0] gpio_in;
    logic [7:0] rx_byte;

    // 50MHz Clock (20ns period)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // GP corruption monitor - FIXED PATH
    always @(posedge clk) begin
        if (rst_n && u_dut.u_core.u_mem_wb.wb_reg_write &&
            u_dut.u_core.u_mem_wb.wb_valid &&
            u_dut.u_core.u_mem_wb.wb_rd == 5'd3) begin
            $display("ALERT: Writing to gp (x3)! Value=0x%08h PC=0x%08h",
                     u_dut.u_core.u_mem_wb.wb_write_data,
                     u_dut.u_core.u_mem_wb.wb_pc_plus4 - 4);
        end
    end

    // Reset
    initial begin
        rst_n = 0;
        #100;
        rst_n = 1;
    end

    assign gpio_in = 32'h0;
    assign uart_rx = 1'b1;

    riscv_soc #(
        .IMEM_DEPTH ( 32768 ),
        .DMEM_DEPTH ( 32768 ),
        .IMEM_HEX   ( "imem.hex" ),
        .DMEM_HEX   ( "dmem.hex" )
    ) u_dut (
        .clk       ( clk ),
        .rst_n     ( rst_n ),
        .uart_tx   ( uart_tx ),
        .uart_rx   ( uart_rx ),
        .gpio_out  ( gpio_out ),
        .gpio_in   ( gpio_in )
    );

  
  
 // always @(posedge clk) begin
   // if (rst_n &&
     //   u_dut.u_core.id_ex_pc == 32'h00000F84) begin

       // $display(
         //   "[PXTCB-CHECK] pointer=%08h TCB=%08h",
           // u_dut.u_dmem.mem[0],
            //u_dut.u_dmem.mem[32'h0000085C >> 2]
      //  );
    //end
//end
  
  
  // Trace writes to RAM, especially pxCurrentTCB at 0x80000000.
//always @(posedge clk) begin
  //  if (rst_n &&
    //    u_dut.core_wr_en &&
      //  u_dut.is_dmem) begin

        //$display(
          //  "[DMEM-STORE] PC=%08h ADDR=%08h DATA=%08h STRB=%b",
            //u_dut.u_core.ex_mem_pc_plus4 - 32'd4,
            //u_dut.core_addr,
            //u_dut.core_wdata,
            //u_dut.core_wstrb
        //);

        //if (u_dut.core_addr == 32'h80000000) begin
          //  $display(
            //    "[PXTCB-WRITE] DATA=%08h STRB=%b",
              //  u_dut.core_wdata,
                //u_dut.core_wstrb
            //);
        //end
    //end
//end


  
  
  
  
  
  
    // UART Terminal
    localparam int BIT_PERIOD = 8680;
    integer uart_fd;
    initial begin
        uart_fd = $fopen("uart_output.log", "w");
        $display("UART Terminal Ready - Waiting for FreeRTOS");
    end

    initial begin
        forever begin
            @(negedge uart_tx);
            #(BIT_PERIOD / 2);
            if (uart_tx == 1'b0) begin
                rx_byte = 0;
                for (int i = 0; i < 8; i++) begin
                    #(BIT_PERIOD);
                    rx_byte[i] = uart_tx;
                end
                #(BIT_PERIOD);
                $fwrite(uart_fd, "%c", rx_byte);
                $fflush(uart_fd);
                $write("%c", rx_byte);
            end
        end
    end

















    
    // PC log - FIXED PATH
    integer pc_log;
    initial pc_log = $fopen("pc_trace.log", "w");
    always @(posedge clk) begin
        if (rst_n && u_dut.u_core.mem_wb_valid)
            $fwrite(pc_log, "%08x\n", u_dut.u_core.mem_wb_pc_plus4 - 32'd4);
    end
    final $fclose(pc_log);

    // Store log
    integer f;
    initial f = $fopen("stores.log","w");
    always @(posedge clk)
        if (rst_n && u_dut.core_wr_en)
            $fwrite(f, "ST %08x %08x %h\n", u_dut.core_addr, u_dut.core_wdata, u_dut.core_wstrb);

integer dbg_tcb_index;
integer dbg_stack_index;

logic [31:0] dbg_tcb_ptr;
logic [31:0] dbg_stack_ptr;
logic [31:0] dbg_saved_pc;
logic [31:0] dbg_saved_mstatus;

//always @(posedge clk) begin
  //  if (rst_n &&
    //    u_dut.u_core.id_ex_pc == 32'h00000F84) begin

        // pxCurrentTCB is located at 0x80000978.
      //  dbg_tcb_ptr =
        //    u_dut.u_dmem.mem[32'h00000978 >> 2];

        //if ((dbg_tcb_ptr >= 32'h80000000) &&
          //  (dbg_tcb_ptr <  32'h80020000)) begin

            //dbg_tcb_index =
              //  (dbg_tcb_ptr - 32'h80000000) >> 2;

            // First word in TCB = pxTopOfStack.
            //dbg_stack_ptr =
              //  u_dut.u_dmem.mem[dbg_tcb_index];

            //if ((dbg_stack_ptr >= 32'h80000000) &&
              //  (dbg_stack_ptr <  32'h80020000)) begin

                //dbg_stack_index =
                  //  (dbg_stack_ptr - 32'h80000000) >> 2;

                //dbg_saved_pc =
                  //  u_dut.u_dmem.mem[dbg_stack_index];

                //dbg_saved_mstatus =
                  //  u_dut.u_dmem.mem[dbg_stack_index + 1];

                //$display(
                  //  "[TASK-FRAME] TCB=%08h SP=%08h PC=%08h MSTATUS=%08h",
                    //dbg_tcb_ptr,
                    //dbg_stack_ptr,
                    //dbg_saved_pc,
                    //dbg_saved_mstatus
                //);
          //  end
       // end
   // end
//end


//always @(posedge clk) begin
  //  if (rst_n && u_dut.u_core.ex_mem_mem_read &&
    //    u_dut.u_core.ex_mem_alu_result >= 32'h80000000 &&
      //  u_dut.u_core.ex_mem_alu_result <  32'h80020000) begin

        //$display(
          //  "[DMEM-LOAD] PC=%08h ADDR=%08h RAW=%08h CORE=%08h FINAL=%08h RD=x%0d",
            //u_dut.u_core.ex_mem_pc_plus4 - 32'd4,
            //u_dut.u_core.ex_mem_alu_result,
           // u_dut.dmem_rdata,
            //u_dut.core_rdata,
            //u_dut.u_core.mem_final_read,
            //u_dut.u_core.ex_mem_rd
        //);
    //end
//end






    // Timeout
    initial begin
        #500000000;
      $display("Simulation Timeout Reached (500ms).");
        $fclose(uart_fd);
        $finish;
    end
endmodule

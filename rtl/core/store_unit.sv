
`timescale 1ns / 1ps

`include "riscv_defs.sv"

module store_unit (
    input  logic [31:0] rs2_data,      // Value from register file (forwarded)
    input  logic [1:0]  addr_offset,   // addr[1:0] from EX/MEM
    input  logic [2:0]  funct3,        // SB/SH/SW
    input  logic        mem_write,     // Enable

    output logic [31:0] store_data,    // Shifted to correct byte lanes
    output logic [3:0]  byte_mask      // One-hot per byte lane
);

    always_comb begin
        store_data = '0;
        byte_mask  = '0;

        if (mem_write) begin
            case (funct3[1:0])
                2'b00: begin // SB
                    case (addr_offset)
                        2'b00: begin store_data = {24'b0, rs2_data[7:0]};     byte_mask = 4'b0001; end
                        2'b01: begin store_data = {16'b0, rs2_data[7:0], 8'b0}; byte_mask = 4'b0010; end
                        2'b10: begin store_data = {8'b0, rs2_data[7:0], 16'b0}; byte_mask = 4'b0100; end
                        2'b11: begin store_data = {rs2_data[7:0], 24'b0};     byte_mask = 4'b1000; end
                    endcase
                end

                2'b01: begin // SH
                    case (addr_offset[1])
                        1'b0: begin store_data = {16'b0, rs2_data[15:0]};     byte_mask = 4'b0011; end
                        1'b1: begin store_data = {rs2_data[15:0], 16'b0};     byte_mask = 4'b1100; end
                    endcase
                end

                2'b10: begin // SW
                    store_data = rs2_data;
                    byte_mask  = 4'b1111;
                end

                default: begin
                    store_data = '0;
                    byte_mask  = '0;
                end
            endcase
        end
    end

endmodule



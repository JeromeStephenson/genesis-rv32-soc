`timescale 1ns / 1ps

`include "riscv_defs.sv"

module load_unit (
    input  logic [31:0] mem_data,      // Raw 32-bit word from memory
    input  logic [1:0]  addr_offset,   // addr[1:0] from EX/MEM
    input  logic [2:0]  funct3,        // LB/LH/LW/LBU/LHU
    input  logic        mem_read,      // Enable

    output logic [31:0] load_data
);

    logic [7:0]  byte_val;
    logic [15:0] half_val;

    always_comb begin
        load_data = '0;

        if (mem_read) begin
            case (funct3[1:0])
                2'b00: begin // LB / LBU
                    case (addr_offset)
                        2'b00: byte_val = mem_data[7:0];
                        2'b01: byte_val = mem_data[15:8];
                        2'b10: byte_val = mem_data[23:16];
                        2'b11: byte_val = mem_data[31:24];
                    endcase
                    // funct3[2] = 1 ? unsigned (LBU), 0 ? signed (LB)
                    load_data = funct3[2] ? {24'b0, byte_val}
                                          : {{24{byte_val[7]}}, byte_val};
                end

                2'b01: begin // LH / LHU
                    case (addr_offset[1])
                        1'b0: half_val = mem_data[15:0];
                        1'b1: half_val = mem_data[31:16];
                    endcase
                    load_data = funct3[2] ? {16'b0, half_val}
                                          : {{16{half_val[15]}}, half_val};
                end

                2'b10: begin // LW
                    load_data = mem_data;
                end

                default: load_data = '0;
            endcase
        end
    end

endmodule



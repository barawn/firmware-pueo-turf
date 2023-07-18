`timescale 1ns / 1ps
// Bit aligner. The UltraScale series guys don't have a bitslip module,
// so we do it this way.
//
// This is a x4 version just to get working.
module bit_align(   input  [3:0] din,
                    output [3:0] dout,
                    input        slip,
                    input        rst,
                    input        clk
    );
    
    reg [1:0] cur_ptr = {2{1'b0}};
    reg [3:0] out_data = {4{1'b0}};
    reg [3:0] last_din_reg = {4{1'b0}};
    
    always @(posedge clk) begin
        last_din_reg <= din;
        case (cur_ptr)
            // 00: no bitslip, output is just input
            2'b00: out_data <= din;
            // 01: single bitslip, output [3] from previous and [2:0] from current
            2'b01: out_data <= { din[0 +: (4-1)], last_din_reg[(4-1) +: 1] };
            // 10: two bitslips, output [3:2] from previous and [1:0] from current
            2'b10: out_data <= { din[0 +: (4-2)], last_din_reg[(4-2) +: 2] };
            // 11: three bitslips, output [3:1] from previous and [0] from current
            2'b11: out_data <= { din[0 +: (4-3)], last_din_reg[(4-3) +: 3] };
        endcase
        if (rst) cur_ptr <= {2{1'b0}};
        else if (slip) cur_ptr <= cur_ptr + 1;
    end
     
    assign dout = out_data;    
endmodule

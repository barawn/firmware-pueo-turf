`timescale 1ns / 1ps
// Xilinx's UARTlite runs with a fixed baud rate, but it idiotically just uses
// a straight counter, which means you can get a very big error with fractional divides.
// (e.g. for a 100M clock with 500k baud rate, using "12" as the divisor gives a 4%
// error).
//
// We use an accumulator approach, and since they're all the same, we actually end
// up being cheaper.
module hsk_uart_brg(
        input clk,
        input resetn,
        output en_16x_baud
    );
    
    // 9 bits accumulator + rollover
    reg [9:0] accumulator = {10{1'b0}};
    // adding 41 gives us a 12.4878 ratio, or within 0.1%
    localparam [8:0] ACC_ADD = 41;
    
    always @(posedge clk) begin
        if (!resetn) accumulator <= {10{1'b0}};
        else accumulator <= accumulator[8:0] + ACC_ADD;
    end
    
    assign en_16x_baud = accumulator[9];
endmodule

`timescale 1ns / 1ps
// eth->wb interface clock cross
`include "interfaces.vh"
module wb_if_cc(
        input wb_clk_i,
        `HOST_NAMED_PORTS_WB_IF(wb_ , 28, 32),
        input en_i,
        input we_i,
        input [27:0] adr_i,
        input [31:0] dat_i,
        output [31:0] dat_o,
        output ack_o
    );

    parameter CLKTYPE = "GBE";
    parameter WBCLKTYPE = "NONE";
    
    
    

endmodule

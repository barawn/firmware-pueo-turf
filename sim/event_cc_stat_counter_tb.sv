`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/24/2025 03:17:53 PM
// Design Name: 
// Module Name: event_cc_stat_counter_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module event_cc_stat_counter_tb;
    wire aclk, wbclk;
    tb_rclk #(.PERIOD(6.4)) u_aclk(.clk(aclk));
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wbclk));
    
    reg [3:0] tvalid = 0;
    wire [31:0] count[3:0];
    reg rst = 0;
    event_cc_stat_counter uut(.aclk(aclk),
                              .tx_valid_i(tvalid),
                              .wb_clk_i(wbclk),
                              .rst_i(rst),
                              .tx0_count_o(count[0]),
                              .tx1_count_o(count[1]),
                              .tx2_count_o(count[2]),
                              .tx3_count_o(count[3]));

    initial begin
        #100;
        @(posedge wbclk); #1 rst = 1;
        @(posedge wbclk); #1 rst = 0;
        #100;
        @(posedge aclk); #1 tvalid = 4'b0001;
        #100;
        @(posedge aclk); #1 tvalid = 4'b0000;
        #20;
        @(posedge aclk); #1 tvalid = 4'b0001;
        #50;
        @(posedge aclk); #1 tvalid = 4'b0000;
    end
    
endmodule

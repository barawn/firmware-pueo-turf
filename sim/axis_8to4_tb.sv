`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/13/2025 07:26:08 PM
// Design Name: 
// Module Name: axis_8to4_tb
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


module axis_8to4_tb;

    tb_rclk #(.PERIOD(10.0)) u_clk(.clk(clk));
    
    reg [7:0] ind_tdata = {8{1'b0}};
    reg       ind_tvalid = 0;
    reg       ind_tlast = 0;
    wire      ind_tready = 0;
    
    wire [63:0] outd_tdata;
    wire [7:0]  outd_tkeep;
    wire        outd_tlast;
    wire        outd_tvalid;

    reg aresetn = 0;    
    axis_8to64 u_conv(.aclk(clk),.aresetn(aresetn),
                      .s_axis_tdata(ind_tdata),
                      .s_axis_tvalid(ind_tvalid),
                      .s_axis_tready(ind_tready),
                      .s_axis_tlast(ind_tlast),
                      .m_axis_tdata(outd_tdata),
                      .m_axis_tkeep(outd_tkeep),
                      .m_axis_tlast(outd_tlast),
                      .m_axis_tvalid(outd_tvalid),
                      .m_axis_tready(1'b1));

    initial begin
        #100;
        @(posedge clk);
        #1 aresetn = 1;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1 ind_tvalid = 1'b1;
           ind_tlast = 1'b0;
           ind_tdata = 8'h01;
        @(posedge clk);
        while (!ind_tready) #1 @(posedge clk);
        #1 ind_tvalid = 1'b0;
        @(posedge clk);
        
        #1 ind_tvalid = 1'b1;
           ind_tlast = 1'b0;
           ind_tdata = 8'h02;
        @(posedge clk);
        while (!ind_tready) #1 @(posedge clk);
        #1 ind_tvalid = 1'b0;
        @(posedge clk);

        #1 ind_tvalid = 1'b1;
           ind_tlast = 1'b0;
           ind_tdata = 8'h03;
        @(posedge clk);
        while (!ind_tready) #1 @(posedge clk);
        #1 ind_tvalid = 1'b0;
        @(posedge clk);

        #1 ind_tvalid = 1'b1;
           ind_tlast = 1'b1;
           ind_tdata = 8'h04;
        @(posedge clk);
        while (!ind_tready) #1 @(posedge clk);
        #1 ind_tvalid = 1'b0;
        @(posedge clk);


        @(posedge clk);
        #1 ind_tvalid = 1'b1;
           ind_tlast = 1'b0;
           ind_tdata = 8'h05;
        @(posedge clk);
        while (!ind_tready) #1 @(posedge clk);
        #1 ind_tvalid = 1'b0;
        @(posedge clk);

        #1 ind_tvalid = 1'b1;
           ind_tlast = 1'b0;
           ind_tdata = 8'h06;
        @(posedge clk);
        while (!ind_tready) #1 @(posedge clk);
        #1 ind_tvalid = 1'b0;
        @(posedge clk);

        #1 ind_tvalid = 1'b1;
           ind_tlast = 1'b0;
           ind_tdata = 8'h07;
        @(posedge clk);
        while (!ind_tready) #1 @(posedge clk);
        #1 ind_tvalid = 1'b0;
        @(posedge clk);

        #1 ind_tvalid = 1'b1;
           ind_tlast = 1'b1;
           ind_tdata = 8'h08;
        @(posedge clk);
        while (!ind_tready) #1 @(posedge clk);
        #1 ind_tvalid = 1'b0;
        @(posedge clk);

    end                      
endmodule

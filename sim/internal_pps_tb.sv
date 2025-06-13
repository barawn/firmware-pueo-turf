`timescale 1ns / 1ps

module internal_pps_tb;

    wire sysclk;
    tb_rclk #(.PERIOD(8.0)) u_sysclk(.clk(sysclk));
    wire wbclk;
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wbclk));
    
    reg en = 0; // wbclk
    reg [15:0] trim = {16{1'b0}};   // wbclk
    reg update_trim = 0; // sysclk
    wire [15:0] trim_out;
    wire pps;
    internal_pps uut(.sysclk_i(sysclk),
                     .wbclk_i(wbclk),
                     .en_i(en),
                     .trim_i(trim),
                     .update_trim_i(update_trim),
                     .trim_o(trim_out),
                     .pps_o(pps));

    initial begin
        #500;
        trim = 100;
        #5;
        @(posedge sysclk);
        #1 update_trim = 1;
        @(posedge sysclk);
        #1 update_trim = 0;
        #100;
        @(posedge wbclk);
        #1 en = 1;                
    end

endmodule

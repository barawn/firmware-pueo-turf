`timescale 1ns / 1ps
// dumb testbed for hooking up sync testing stuff
module turf_cout_tb;

    reg if_clk_x2 = 0;
    always #2 if_clk_x2 <= ~if_clk_x2;
    reg if_clk = 0;
    always @(posedge if_clk_x2) if_clk <= ~if_clk;
    
    reg [4:0] if_clk_x2_phase = {5{1'b0}};
    always @(posedge if_clk_x2) if_clk_x2_phase <= if_clk_x2_phase[3:0] + 1;
    
    wire [31:0] command = { 4'b0000, 12'b000000000001, {16{1'b0}} };
    reg train = 1;
    
    wire COUT_P;
    wire TXCLK_P;
    
    turfio_cout uut(.if_clk_i(if_clk),.if_clk_x2_i(if_clk_x2),.if_clk_x2_phase_i(if_clk_x2_phase[4]),
                    .cout_command_i(command),
                    .cout_train_i(train),
                    .COUT_P(COUT_P),
                    .TXCLK_P(TXCLK_P));

    initial begin
        #100;
        while (!if_clk_x2_phase[4]) @(posedge if_clk_x2);
        #10;
        train = 0;
    end 
    
endmodule

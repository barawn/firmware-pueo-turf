`timescale 1ns / 1ps

module turfio_cout #(parameter INV_COUT=1'b0,
                     parameter INV_TXCLK=1'b0, 
                     parameter TRAIN_VALUE = 32'hA55A6996)(
        input if_clk_i,
        input if_clk_x2_i,
        input if_clk_x2_phase_i,
        // cout_command is captured on the clock phase *before* if_clk_x2_phase_i
        input [31:0] cout_command_i,
        input cout_train_i,
        
        output COUT_P,
        output COUT_N,
        output TXCLK_P,
        output TXCLK_N
    );    
    wire cout_to_obuf;
    wire cout_ninv;
    wire cout_inv;
    assign COUT_P = (INV_COUT == 1'b0) ? cout_ninv : cout_inv;
    assign COUT_N = (INV_COUT == 1'b0) ? cout_inv : cout_ninv;
        
    wire txclk_to_obuf;
    wire txclk_ninv;
    wire txclk_inv;
    assign TXCLK_P = (INV_TXCLK == 1'b0) ? txclk_ninv : txclk_inv;
    assign TXCLK_N = (INV_TXCLK == 1'b0) ? txclk_inv : txclk_ninv;

    // output rate is 500 Mbit/s, so 32-bits every 15.625 MHz or every 8 125 MHz clocks or every
    // 16 250 MHz clocks.
    reg [3:0] which_clock_phase = {4{1'b0}};
    reg clock_phase_buf = 1'b0;
    reg [31:0] command_recap = {32{1'b0}};
    reg do_capture = 1'b0;
    always @(posedge if_clk_x2_i) begin
        clock_phase_buf <= if_clk_x2_phase_i;
        
        // phase_i means we're in clk 0.
        // clock_phase_buf means we're in clk 1
        // so when it's true, reset to 2 and we sync up.
        if (clock_phase_buf) which_clock_phase <= 4'd2;
        else which_clock_phase <= which_clock_phase + 1;
        // do_capture goes high in clock phase 14
        do_capture <= which_clock_phase == 4'd13;
        // we want to output
        // phase 0 : bit[1:0]
        // phase 1 : bit[3:2]
        // But we need to take into account the ODDR here:
        // It has a latency of 1 clock, so we need to present
        // bit[1:0] on phase 15.
        // This means we need to *capture* on 14.        
        if (do_capture) begin
            if (cout_train_i) command_recap <= TRAIN_VALUE;
            else command_recap <= cout_command_i;
        end else begin
            command_recap <= { 2'b00, command_recap[31:2] };
        end
    end
    ODDRE1 #(.SRVAL(INV_COUT)) u_cout_oddr(.C(if_clk_x2_i),.D1(command_recap[0] ^ INV_COUT),.D2(command_recap[1] ^ INV_COUT),.SR(1'b0),.Q(cout_to_obuf));
    ODDRE1 #(.SRVAL(INV_TXCLK)) u_txclk_oddr(.C(if_clk_i),.D1(1'b1 ^ INV_TXCLK),.D2(1'b0 ^ INV_TXCLK),.SR(1'b0),.Q(txclk_to_obuf));
    OBUFDS u_obuf(.I(cout_to_obuf),.O(cout_ninv),.OB(cout_inv));
    OBUFDS u_txclk_obuf(.I(txclk_to_obuf),.O(txclk_ninv),.OB(txclk_inv));
endmodule

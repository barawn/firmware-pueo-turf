`timescale 1ns / 1ps
// this is used to test sync: we're forcing both it and the clock to the
// output via ologic resources
// hopefully the 125 MHz clock will be easy enough to see
module sync_debug(
        input sysclk_i,
        input sysclk_sync_i,
        output [1:0] LGPIO        
    );
    // The sync input itself looks like a 7.8125 MHz clock
    // it has a full period of 16 clocks
    // if we want our output to mimic it, we need to do:
    //
    // clk  in  srlout  srlff   iobff
    // 15   0   0       x       x
    // 0    1   0       x       x
    // 1    1   A=0     x       x
    // 2    1   A=1
    // 3    1   A=2
    // 4    1   A=3
    // 5    1   A=4
    // 6    1   A=5
    // 7    1   A=6
    // 8    0   A=7
    // 9    0   A=8
    // 10   0   A=9
    // 11   0   A=10    x       x
    // 12   0   A=11    x       x
    // 13   0   A=12    x       x
    // 14   0   A=13    x       x
    // 15   0   1       1       x
    // 0    1   1       1       1
    // so if we stick an SRL delay of A=13 (14 clock delay), plus a FF
    // registering that SRL (15 clock delay) adding the IOBFF register
    // gets a 16-clock delay
    localparam [3:0] SRL_DELAY = 13;
    wire srl_delay;
    (* KEEP = "TRUE" *)
    reg srl_ff = 0;
    (* IOB = "TRUE" *)
    reg sync_ff = 0;
    SRL16E u_srldelay(.D(sysclk_sync_i),
                      .CE(1'b1),
                      .CLK(sysclk_i),
                      .A0(SRL_DELAY[0]),
                      .A1(SRL_DELAY[1]),
                      .A2(SRL_DELAY[2]),
                      .A3(SRL_DELAY[3]),
                      .Q(srl_delay));
    always @(posedge sysclk_i) begin
        srl_ff <= srl_delay;
        sync_ff <= srl_ff;
    end
    
    ODDRE1 u_sysclk_oddr(.C(sysclk_i),.D1(1'b1),.D2(1'b0),.SR(1'b0),.Q(LGPIO[1]));
    assign LGPIO[0] = sync_ff;
    
endmodule

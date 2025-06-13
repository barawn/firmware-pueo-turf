`timescale 1ns / 1ps
`include "dsp_macros.vh"
// Programmable length internal PPS generation using a DSP.
// This is ___massively__ sleazed! Normally, you can't readback
// a DSP's internal registers. But because we aren't going to
// have full range, we actually use the top 16 bits to
// store the value. Ultra-sleaze.
// The 16 bits here are a trim: they get added the cycle after
// reset, and can be positive or negative. So positive
// trims reduce the internal PPS, negative trims increase it.
// But wait, you say, how do we handle negative numbers
// while preserving the top 16 bits?
//
// if our target is 125,000,000:
// desired target = 0x0773_5940
//  actual target = 0x8773_5940
//  trim of 32767 = 0x8000_7FFF
//      trim of 1 = 0x8000_0001
//      trim of 0 = 0x8000_0000
//      trim of -1= 0x7FFF_FFFF
// trim of -32768 = 0x7FFF_8000
//
// note target is really target because we continually
// add the carry. so the clock after, with a trim of 0,
// we're at 0x8000_0001.
module internal_pps #(parameter SYSCLKTYPE="NONE",
                      parameter WBCLKTYPE="NONE",
                      parameter [30:0] TARGET = 30'd125000000)(
        input sysclk_i,
        input wbclk_i,
        input en_i,             // wbclk -> sysclk
        input [15:0] trim_i,    // wbclk -> sysclk
        input update_trim_i,    // in sysclk already
        output [15:0] trim_o,   // sysclk -> wbclk
        output pps_o
    );
    
    // sooo many silly pet tricks
    wire [47:0] dsp_C = { trim_i, !trim_i[15], {15{trim_i[15]}}, trim_i };
    wire [47:0] dsp_P;
    localparam [47:0] dsp_MASK = { {16{1'b1}}, {32{1'b0}} };
    localparam [47:0] dsp_PATTERN = { {16{1'b0}}, 1'b1, TARGET };
    // we do NOT use automatic pattern detect reset,
    // because it would kill our output. Instead
    // we flop the INMODE so that P' = C.
    // Because we ALSO want to do this when we're first enabled
    // (to start out), we use the W opmode for that 

    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [1:0] en_sysclk = {2{1'b0}};
    reg       en_sysclk_flg = 1'b0;
    // en_sysclk[1] is used as the not reset
    // en_sysclk_flag is en_sysclk && !en_sysclk[1] so they both go high
    // same cycle.
    wire      target_reached;
    
    always @(posedge sysclk_i) begin
        en_sysclk <= { en_sysclk[0], en_i };
        en_sysclk_flg <= en_sysclk[0] && !en_sysclk[1];
    end
    
    // opmode is then just
    // en_sysclk_flg, en_sysclk_flg, 0, 1, target_reached, 4'b0000.
    wire [8:0] dsp_OPMODE = { {2{en_sysclk_flg}},
                              2'b01, target_reached,
                              {4{1'b0}} };
    (* CUSTOM_CC_DST = SYSCLKTYPE, CUSTOM_CC_SRC = SYSCLKTYPE *)
    DSP48E2 #(`A_UNUSED_ATTRS,
              `B_UNUSED_ATTRS,
              `DE2_UNUSED_ATTRS,
              `NO_MULT_ATTRS,
              .USE_PATTERN_DETECT("PATDET"),
              .SEL_PATTERN("PATTERN"),
              .PATTERN(dsp_PATTERN),
              .MASK(dsp_MASK),
              .PREG(1'b1),
              .CREG(1'b1),
              .INMODEREG(1'b0),
              .ALUMODEREG(1'b0),
              .OPMODEREG(1'b0),
              .CARRYINREG(1'b0),
              .CARRYINSELREG(1'b0))
              u_counter(.CLK(sysclk_i),
                        `A_UNUSED_PORTS,
                        `B_UNUSED_PORTS,
                        `D_UNUSED_PORTS,
                        .OPMODE(dsp_OPMODE),
                        .ALUMODE(`ALUMODE_SUM_ZXYCIN),
                        .INMODE({5{1'b0}}),
                        .CARRYINSEL({3{1'b0}}),
                        .CEC(update_trim_i),
                        .C(dsp_C),
                        .RSTC(1'b0),
                        .CEP(en_sysclk[1]),
                        .RSTP(!en_sysclk[1]),
                        .CARRYIN(1'b1),
                        .PATTERNDETECT(target_reached),
                        .P(dsp_P));
              
              
    assign pps_o = target_reached;
    assign trim_o = dsp_P[32 +: 16];              
    
    
endmodule

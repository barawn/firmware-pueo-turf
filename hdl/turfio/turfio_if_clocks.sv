`timescale 1ns / 1ps
// MMCMs for handling the TURFIO interfaces. They need to be separate because of the whole
// "reset the PLL" thing.
//
// The input taken here is the output of the IBUFDS.
module turfio_if_clocks #(parameter INVERT_MMCM = "TRUE")(
        // output of the IBUFDS
        input sysclk_ibuf_i,
        // first phase of the 8-clock cycle in sysclk domain
        input sysclk_phase_i,
        input rst67_i,
        input rst68_i,

        output ifclk67_o,
        output ifclk67_phase_o,
        output ifclk67_x2_o,
        output ifclk67_x2_phase_o,

        output ifclk68_o,
        output ifclk68_phase_o,
        output ifclk68_x2_o,
        output ifclk68_x2_phase_o,

        output [1:0] locked_o
    );
    
    // Dumb macro to automate the inversion process for both
    // ifclks.
    
    `define DEFINE_CLK( clkname )       \
        wire clkname``_p;               \
        wire clkname``_n;               \
        wire clkname = (INVERT_MMCM == "TRUE") ? clkname``_n : clkname``_p
        
    `DEFINE_CLK( if_clk67_out );
    `DEFINE_CLK( if_clk68_out );
    // 2x clock timing diagram. Here we define normal clocks as rising at 0.
    // orig clk : ----____----____ (rise 0 fall 4 rise 8 fall 12)
    // inv  clk : ____----____---- (fall 0 rise 4 fall 8 rise 12)
    // orig 2x  : --__--__--__--__ (rise 0 fall 2 rise 4 fall 6 rise 8 fall 10 rise 12)
    // inv  2x  : __--__--__--__-- (fall 0 rise 2 fall 4 rise 6 fall 8 rise 10 fall 12)

    // Note that we DO NOT WANT the 2x clock to be inverted.
    // The 2x clock has the same diagram (__--) in both the positive half and negative half of the clocks.
    // If you just start the above diagram 4 ticks in, it's the same on the 2x clock.
    // 2x has both a 4 ns gap from the original AND the inverted (rise 0 -> rise 4 in inverted 
    // or rise 4 -> rise 8 in original)
    // But 2x *inverted* has a 2 ns gap (rise 2->rise 4 for inverted and rise 6->rise 8 for original).
    //
    // The key here is that what you're really trying to do is generate a 4 ns shift in the
    // waveform: which translates into (4 ns/clk_period)*360 mod 360.
    // So for a 1x clock (8 ns) it's (4/8)*360=180, which we can just use the B output.
    // For a 2x clock (4 ns) it's (4/4)*360=360, or zero, so no phase shift.
    // For a 3x clock (2.667 ns) it's (4/(8/3))=1.5*360 mod 360 = 180, so just use B output.
    // For a 4x clock (2 ns) it's (4/2)*360=720, or zero, so no phase shift.
    // For a 5x clock (1.6 ns) it's (4/(8/5))=2.5*360 mod 360 = 180, so just use B output.
    // etc. This works even for fractional clocks.
    //
    // I don't feel like messing around with the phase shift settings, so we'll just
    // hardcode this behavior in.
            
    // x2 clock in bank 67
    wire if_clk67_x2_out;
    // x2 clock in bank 68
    wire if_clk68_x2_out;
    
    // feedback
    wire [1:0] clkfb_out;
    // buffered feedback
    wire [1:0] clkfb_out_buf;
    
    // MMCM for bank67
    (* PHASESHIFT_MODE = "LATENCY", LOC = "MMCM_X0Y3" *)
    MMCME4_ADV #(.BANDWIDTH("HIGH"),
                 .CLKOUT4_CASCADE("FALSE"),
                 .COMPENSATION("AUTO"),
                 .STARTUP_WAIT("FALSE"),
                 .DIVCLK_DIVIDE(1),
                 .CLKFBOUT_MULT_F(12.000),
                 .CLKFBOUT_PHASE(0.000),
                 .CLKFBOUT_USE_FINE_PS("FALSE"),
                 .CLKOUT0_DIVIDE_F(12.000),
                 .CLKOUT0_PHASE(0.000),
                 .CLKOUT0_DUTY_CYCLE(0.5000),
                 .CLKOUT0_USE_FINE_PS("FALSE"),
                 .CLKOUT1_DIVIDE(6),
                 .CLKOUT1_PHASE(0.000),
                 .CLKOUT1_DUTY_CYCLE(0.5000),
                 .CLKOUT1_USE_FINE_PS("FALSE"),
                 .CLKIN1_PERIOD(8.000))
            u_mmcm67( .CLKFBOUT( clkfb_out[0] ),
                      .CLKFBIN( clkfb_out_buf[0] ),
                      .CLKOUT0( if_clk67_out_p ),
                      .CLKOUT0B(if_clk67_out_n ),
                      .CLKOUT1( if_clk67_x2_out ),
                      .CLKOUT1B( ),
                      .CLKIN1(  sysclk_ibuf_i ),
                      .CLKIN2(  1'b0 ),
                      .CLKINSEL(1'b1 ),
                      .DADDR(7'h0),
                      .DCLK(1'b0),
                      .DEN(1'b0),
                      .DI(16'h0),
                      .DO(),
                      .DRDY(),
                      .DWE(1'b0),
                      .CDDCDONE(),
                      .CDDCREQ(1'b0),
                      .PSCLK(1'b0),
                      .PSEN(1'b0),
                      .PSINCDEC(1'b0),
                      .PSDONE(),
                      .LOCKED(locked_o[0]),
                      .CLKINSTOPPED(),
                      .CLKFBSTOPPED(),
                      .PWRDWN(1'b0),
                      .RST(rst67_i));
    // Buffer the feedback
    BUFG u_clkfb0_buf(.I(clkfb_out[0]),.O(clkfb_out_buf[0]));
    // Buffer ifclk
    BUFG u_ifclk67_buf(.I(if_clk67_out),.O(ifclk67_o));
    // Buffer ifclk_x2
    BUFG u_ifclk67_x2_buf(.I(if_clk67_x2_out),.O(ifclk67_x2_o));               
        
    // and bank 68
    (* PHASESHIFT_MODE = "LATENCY" *)
    (* LOC = "MMCM_X0Y4" *)
    MMCME4_ADV #(.BANDWIDTH("HIGH"),
                 .CLKOUT4_CASCADE("FALSE"),
                 .COMPENSATION("AUTO"),
                 .STARTUP_WAIT("FALSE"),
                 .DIVCLK_DIVIDE(1),
                 .CLKFBOUT_MULT_F(12.000),
                 .CLKFBOUT_PHASE(0.000),
                 .CLKFBOUT_USE_FINE_PS("FALSE"),
                 .CLKOUT0_DIVIDE_F(12.000),
                 .CLKOUT0_PHASE(0.000),
                 .CLKOUT0_DUTY_CYCLE(0.5000),
                 .CLKOUT0_USE_FINE_PS("FALSE"),
                 .CLKOUT1_DIVIDE(6),
                 .CLKOUT1_PHASE(0.000),
                 .CLKOUT1_DUTY_CYCLE(0.5000),
                 .CLKOUT1_USE_FINE_PS("FALSE"),
                 .CLKIN1_PERIOD(8.000))
            u_mmcm68( .CLKFBOUT( clkfb_out[1] ),
                      .CLKFBIN( clkfb_out_buf[1] ),
                      .CLKOUT0( if_clk68_out_p ),
                      .CLKOUT0B(if_clk68_out_n ),
                      .CLKOUT1( if_clk68_x2_out ),
                      .CLKOUT1B( ),
                      .CLKIN1(  sysclk_ibuf_i ),
                      .CLKIN2(  1'b0 ),
                      .CLKINSEL(1'b1 ),
                      .DADDR(7'h0),
                      .DCLK(1'b0),
                      .DEN(1'b0),
                      .DI(16'h0),
                      .DO(),
                      .DRDY(),
                      .DWE(1'b0),
                      .CDDCDONE(),
                      .CDDCREQ(1'b0),
                      .PSCLK(1'b0),
                      .PSEN(1'b0),
                      .PSINCDEC(1'b0),
                      .PSDONE(),
                      .LOCKED(locked_o[1]),
                      .CLKINSTOPPED(),
                      .CLKFBSTOPPED(),
                      .PWRDWN(1'b0),
                      .RST(rst68_i));
    // Buffer the feedback
    BUFG u_clkfb1_buf(.I(clkfb_out[1]),.O(clkfb_out_buf[1]));
    // Buffer ifclk
    BUFG u_ifclk68_buf(.I(if_clk68_out),.O(ifclk68_o));
    // Buffer ifclk_x2
    BUFG u_ifclk68_x2_buf(.I(if_clk68_x2_out),.O(ifclk68_x2_o));               
    
    // Phase track registers. We're slow enough that we can run as a counter
    // especially since it's a relatively short cycle.
    reg [3:0] if_clk67_phase = {4{1'b0}};
    reg       if_clk67_phase_rst = 0;
    
    // when sysclk_phase comes in, it's phase 0
    // when if_clk67_phase_rst goes, it's phase 1
    // so we want the next clock to be phase 2
    // we want to go in phase 0 so phase_reg trips
    // at the rollover

    always @(posedge ifclk67_o) begin
        if_clk67_phase_rst <= sysclk_phase_i;
        // Reset to 2, because the reset signal is in phase 1
        // Then only capture the low 3 bits so that if_clk67_phase[3]
        // becomes a flag.
        if (if_clk67_phase_rst) if_clk67_phase <= 4'd2;
        else if_clk67_phase <= if_clk67_phase[2:0] + 1;
    end
    assign ifclk67_phase_o = if_clk67_phase[3];
    
    reg [3:0] if_clk68_phase = {4{1'b0}};
    reg       if_clk68_phase_rst = 0;
    always @(posedge ifclk68_o) begin
        if_clk68_phase_rst <= sysclk_phase_i;
        // Reset to 2, because the reset signal is in phase 1
        // Then only capture the low 3 bits so that if_clk67_phase[3]
        // becomes a flag.
        if (if_clk68_phase_rst) if_clk68_phase <= 4'd2;
        else if_clk68_phase <= if_clk68_phase[2:0] + 1;
    end
    assign ifclk68_phase_o = if_clk68_phase[3];
    
    reg [4:0] if_clk67_x2_phase = {5{1'b0}};
    reg [1:0] if_clk67_x2_phase_rst = 0;
    // if_clk67_x2_phase_rst[0] goes high in phase 1 because of the timer
    // so we reset to phase 2.
    always @(posedge ifclk67_x2_o) begin
        if_clk67_x2_phase_rst <= { if_clk67_x2_phase_rst[0], sysclk_phase_i};
        if (if_clk67_x2_phase_rst == 2'b01) if_clk67_x2_phase <= 4'd2;
        else if_clk67_x2_phase <= if_clk67_x2_phase[3:0] + 1;
    end
    assign ifclk67_x2_phase_o = if_clk67_x2_phase[4];

    reg [4:0] if_clk68_x2_phase = {5{1'b0}};
    reg [1:0] if_clk68_x2_phase_rst = 0;
    // if_clk67_x2_phase_rst[0] goes high in phase 1 because of the timer
    // so we reset to phase 2.
    always @(posedge ifclk68_x2_o) begin
        if_clk68_x2_phase_rst <= { if_clk68_x2_phase_rst[0], sysclk_phase_i};
        if (if_clk68_x2_phase_rst == 2'b01) if_clk68_x2_phase <= 4'd2;
        else if_clk68_x2_phase <= if_clk68_x2_phase[3:0] + 1;
    end
    assign ifclk68_x2_phase_o = if_clk68_x2_phase[4];
    
endmodule

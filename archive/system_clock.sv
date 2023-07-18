`timescale 1ns / 1ps
// Based on clock generator wizard, but redone by me.
// NOTE: we need multiple ifclk/ifclk_x2 outputs
// because half of them are in bank 68, and half of them
// are in bank 67.
module system_clock( input SYS_CLK_P,
                     input SYS_CLK_N,
                     input reset,
                     output sysclk_o,
                     output ifclk67_o,
                     output ifclk68_o,
                     output ifclk67_x2_o,
                     output ifclk67_x2_phase_o,
                     output ifclk68_x2_o,
                     output ifclk68_x2_phase_o,               
                     output [1:0] locked
    );

    parameter INVERT_MMCM = "TRUE";
    
    (* CLOCK_DEDICATED_ROUTE = "SAME_CMT_COLUMN" *)
    wire sys_clk_ibuf;
    IBUFDS u_inbuf(.I(SYS_CLK_N),
                   .IB(SYS_CLK_P),
                   .O(sys_clk_ibuf));
    
    wire [1:0] clkfb_out;
    wire [1:0] clkfb_out_buf;
    // Bank 67's MMCM has sysclk.
    wire sys_clk_out_p;
    wire sys_clk_out_n;
    wire sys_clk_out = (INVERT_MMCM == "TRUE") ? sys_clk_out_n : sys_clk_out_p;
    wire if_clk67_out_p;
    wire if_clk67_out_n;
    wire if_clk67_out = (INVERT_MMCM == "TRUE") ? if_clk67_out_n : if_clk67_out_p;
    wire if_clk67_x2_out_p;
    wire if_clk67_x2_out_n;
    wire if_clk67_x2_out = (INVERT_MMCM == "TRUE") ? if_clk67_x2_out_n : if_clk67_x2_out_p;
    // Bank 68's mmcm does not.
    wire if_clk68_out_p;
    wire if_clk68_out_n;
    wire if_clk68_out = (INVERT_MMCM == "TRUE") ? if_clk68_out_n : if_clk68_out_p;
    wire if_clk68_x2_out_p;
    wire if_clk68_x2_out_n;
    wire if_clk68_x2_out = (INVERT_MMCM == "TRUE") ? if_clk68_x2_out_n : if_clk68_x2_out_p;

    // Bank 67's MMCM.
    (* PHASESHIFT_MODE = "LATENCY" *)
    (* LOC = "MMCM_X0Y3" *)
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
                 .CLKOUT1_DIVIDE(12),
                 .CLKOUT1_PHASE(0.000),
                 .CLKOUT1_DUTY_CYCLE(0.5000),
                 .CLKOUT1_USE_FINE_PS("FALSE"),
                 .CLKOUT2_DIVIDE(6),
                 .CLKOUT2_PHASE(0.000),
                 .CLKOUT2_DUTY_CYCLE(0.5000),
                 .CLKOUT2_USE_FINE_PS("FALSE"),
                 .CLKIN1_PERIOD(8.000))
            u_mmcm67( .CLKFBOUT( clkfb_out[0] ),
                      .CLKFBIN( clkfb_out_buf[0] ),
                      .CLKOUT0( sys_clk_out_p ),
                      .CLKOUT0B(sys_clk_out_n ),
                      .CLKOUT1( if_clk67_out_p ),
                      .CLKOUT1B(if_clk67_out_n ),
                      .CLKOUT2( if_clk67_x2_out_p ),
                      .CLKOUT2B(if_clk67_x2_out_n ),
                      .CLKIN1(  sys_clk_ibuf ),
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
                      .LOCKED(locked[0]),
                      .CLKINSTOPPED(),
                      .CLKFBSTOPPED(),
                      .PWRDWN(1'b0),
                      .RST(reset));
    // Buffer the feedback
    BUFG u_clkfb0_buf(.I(clkfb_out[0]),.O(clkfb_out_buf[0]));
    // Buffer sysclk
    BUFG u_sysclk_buf(.I(sys_clk_out),.O(sysclk_o));
    // Buffer ifclk
    BUFG u_ifclk67_buf(.I(if_clk67_out),.O(ifclk67_o));
    // Buffer ifclk_x2
    BUFG u_ifclk67_x2_buf(.I(if_clk67_x2_out),.O(ifclk67_x2_o));               

    // Bank 68's MMCM. No SYSCLK on this one.
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
                      .CLKOUT1( if_clk68_x2_out_p ),
                      .CLKOUT1B(if_clk68_x2_out_n ),
                      .CLKIN1(  sys_clk_ibuf ),
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
                      .LOCKED(locked[1]),
                      .CLKINSTOPPED(),
                      .CLKFBSTOPPED(),
                      .PWRDWN(1'b0),
                      .RST(reset));
    // Buffer the feedback
    BUFG u_clkfb1_buf(.I(clkfb_out[1]),.O(clkfb_out_buf[1]));
    // Buffer ifclk
    BUFG u_ifclk68_buf(.I(if_clk68_out),.O(ifclk68_o));
    // Buffer ifclk_x2
    BUFG u_ifclk68_x2_buf(.I(if_clk68_x2_out),.O(ifclk68_x2_o));               
    
    // Phase track registers.
    // *Apparently* using OSERDESes in UltraScales is so friggin
    // difficult it's not even worth it if you can avoid it.
    // So we're just going to try to capture/output using DDR
    // registers, which means *we* need to do the phase track.
    param_clk_phase #(.NUM_CLK_PHASE(1),
                      .CLK0_MULT(2))
        u_clk67_phase(.sync_clk_i(sysclk_o),
                      .clk_i(ifclk67_x2_o),
                      .phase_o(ifclk67_x2_phase_o));
    param_clk_phase #(.NUM_CLK_PHASE(1),
                      .CLK0_MULT(2))
        u_clk68_phase(.sync_clk_i(sysclk_o),
                      .clk_i(ifclk68_x2_o),
                      .phase_o(ifclk68_x2_phase_o));    
    
endmodule

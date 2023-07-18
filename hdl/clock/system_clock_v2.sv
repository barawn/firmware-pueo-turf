`timescale 1ns / 1ps
module system_clock_v2( input SYS_CLK_P,
                        input SYS_CLK_N,
                        input reset,
                        output sysclk_ibuf_o,
                        output sysclk_o,
                        output sysclk_phase_o );

    parameter INVERT_MMCM = "TRUE";
    
    (* CLOCK_DEDICATED_ROUTE = "SAME_CMT_COLUMN" *)
    IBUFDS u_inbuf(.I(SYS_CLK_N),
                   .IB(SYS_CLK_P),
                   .O(sysclk_ibuf_o));
    wire clkfb_out;
    wire clkfb_out_buf;
    
    wire sys_clk_out_p;
    wire sys_clk_out_n;
    wire sys_clk_out = (INVERT_MMCM == "TRUE") ? sys_clk_out_n : sys_clk_out_p;

    wire locked;

    // SYSCLK MMCM. No LOC constraint.
    (* PHASESHIFT_MODE = "LATENCY" *)
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
                 .CLKIN1_PERIOD(8.000))
            u_mmcm67( .CLKFBOUT( clkfb_out ),
                      .CLKFBIN( clkfb_out_buf ),
                      .CLKOUT0( sys_clk_out_p ),
                      .CLKOUT0B(sys_clk_out_n ),
                      .CLKIN1(  sysclk_ibuf_o ),
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
                      .LOCKED(locked),
                      .CLKINSTOPPED(),
                      .CLKFBSTOPPED(),
                      .PWRDWN(1'b0),
                      .RST(reset));
    // Buffer the feedback
    BUFG u_clkfb0_buf(.I(clkfb_out),.O(clkfb_out_buf));
    // Buffer sysclk
    BUFG u_sysclk_buf(.I(sys_clk_out),.O(sysclk_o));
    
    // This is the global SYSCLK phase. Its exact value's basically irrelevant.
    reg [3:0] sysclk_phase = {4{1'b0}};
    always @(posedge sysclk_o) begin
        sysclk_phase <= sysclk_phase[2:0] + 1;
    end
    
    assign sysclk_phase_o = sysclk_phase[3];
endmodule

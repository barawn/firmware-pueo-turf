`timescale 1ns / 1ps
module system_clock_v2( input SYS_CLK_P,
                        input SYS_CLK_N,
                        input reset,
                        output sysclk_ibuf_o,
                        output sysclk_o,
                        output sysclk_phase_o,
                        output sysclk_sync_o,
                        output SYNC );

    parameter INVERT_MMCM = "TRUE";
    parameter GPIO = "TRUE";
    
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

    // sysclk = 125 MHz
    // sync = 7.8125 MHz
    // this is a divide by 16. But our *commanding* is 500 Mbit/s or
    // 32 bits every 15.625 MHz, or a divide by *8*.
    // sysclk_phase_o = 1 if this is the first phase of the 8 clock period
    // sysclk_sync_o = sync toggle, should match the SURF clock, 7.8125 MHz
    // SYNC = gpio which should also match the 7.8125 MHz SURF clock
    // This we generate by just putting an IOB on it and duplicating the logic.
    
    // This is the global SYSCLK phase. Its exact value's basically irrelevant.
    reg [3:0] sysclk_phase = {4{1'b0}};
    // ditto for sysclk sync, it doesn't matter that it's random.
    // sysclk = 125 MHz
    // sync = 7.8125 MHz
    // 
    (* KEEP = "TRUE" *)
    reg sysclk_sync = 0;
    (* IOB = "TRUE", KEEP = "TRUE" *)
    reg sysclk_sync_obuf = 0;
    always @(posedge sysclk_o) begin
        sysclk_phase <= sysclk_phase[2:0] + 1;
        // swap at max so we're in phase 
        if (sysclk_phase[2:0] == 3'b111) sysclk_sync <= ~sysclk_sync;
        if (sysclk_phase[2:0] == 3'b111) sysclk_sync_obuf <= ~sysclk_sync;
    end
    
    assign sysclk_phase_o = sysclk_phase[3];
    assign sysclk_sync_o = sysclk_sync;
    assign SYNC = sysclk_sync_obuf;
endmodule

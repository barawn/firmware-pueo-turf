`timescale 1ns / 1ps
module system_clock_v2( input SYS_CLK_P,
                        input SYS_CLK_N,
                        input reset,
                        output sysclk_ibuf_o,
                        // 125 MHz
                        output sysclk_o,
                        // 250 MHz, for the master trigger process.
                        output sysclk_x2_o,
                        // flag indicating start of the cycle
                        output sysclk_phase_o,
                        // clock enable indicator for sysclk_x2 to capture sysclk
                        output sysclk_x2_ce_o,
                        output sysclk_sync_o,
                        output SYNC );
    // the phase indicators mean we go
    // sysclk   sysclkx2    sysclk_phase    sysclk_x2_phase_reg     sysclk_x2_phase_rereg sysclk_x2_ce_0
    // 0        1           0               0                       0                     DLYFF 1
    // 0        0           0               0                       0                     1
    // 1        1           DLYFF 1         0                       0                     DLYFF 0
    // 1        0           1               0                       0                     0
    // 0        1           1               DLYFF 1                 0                     DLYFF 1
    // 0        0           1               1                       0                     1
    // 1        1           DLYFF 0         1                       DLYFF 1               DLYFF 0
    // 1        0           0               1                       1                     0
    // 0        1           0               DLYFF 0                 1                     DLYFF 1
    // 0        0           0               0                       1                     1
    // so register sysclk_phase
    // reregister it
    // if (sysclk_x2_phase_reg && !sysclk_x2_phase_rereg) sysclk_x2_ce <= 0
    // otherwise sysclk_x2_ce = ~sysclk_x2_ce.
    // With that we can condition any captures from sysclk to sysclkx2
    // freely.

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
    // Inversion doesn't matter for the x2 clock, it's the same regardless.
    wire sys_clk_x2_out;
    
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
                 .CLKOUT1_DIVIDE(6),
                 .CLKOUT1_PHASE(0.000),
                 .CLKOUT1_DUTY_CYCLE(0.5000),
                 .CLKOUT1_USE_FINE_PS("FALSE"),
                 .CLKIN1_PERIOD(8.000))
            u_mmcm67( .CLKFBOUT( clkfb_out ),
                      .CLKFBIN( clkfb_out_buf ),
                      .CLKOUT0( sys_clk_out_p ),
                      .CLKOUT0B(sys_clk_out_n ),
                      .CLKOUT1( sys_clk_x2_out),
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
    // Buffer x2
    BUFG u_sysclk_x2_buf(.I(sys_clk_x2_out),.O(sysclk_x2_o));

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
    
    reg [1:0] sysclk_phase_rereg_x2 = 2'b00;
    // clock enable for sysclk_x2 to know it can capture data from sysclk
    // with max delay.
    // IOW if sysclk_x2_ce is high the NEXT RISING EDGE
    // of sysclk_x2 is also a rising edge of sysclk.
    reg sysclk_x2_ce = 0;
    
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
    always @(posedge sysclk_x2_o) begin
        sysclk_phase_rereg_x2 <= { sysclk_phase_rereg_x2[0], sysclk_phase[3] };
        if (sysclk_phase_rereg_x2[0] && !sysclk_phase_rereg_x2[1]) sysclk_x2_ce <= 0;
        else sysclk_x2_ce <= ~sysclk_x2_ce;
    end
    assign sysclk_phase_o = sysclk_phase[3];
    assign sysclk_sync_o = sysclk_sync;
    assign sysclk_x2_ce_o = sysclk_x2_ce;
    assign SYNC = sysclk_sync_obuf;
endmodule

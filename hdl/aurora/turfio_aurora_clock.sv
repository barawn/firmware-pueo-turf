`timescale 1ns / 1ps
// TURF clock module for the TURFIO aurora.
// Yes, this is confusing naming convention!!
//
// The only thing this module does is just implement
// the BUFG_GT and handle a bit of resety-type stuff.
//
// This module really exists for situations that use
// the per-quad-PLL rather than the per-channel-PLL, I think.
module turfio_aurora_clock(
         
        input gt_clk_i,
        input gt_clk_locked_i,
        input bufg_gt_clr_i,
        
        output user_clk_o,
        output sync_clk_o,
        output pll_not_locked_o        
    );
    
    reg pll_not_locked = 0;
    
    BUFG_GT user_clk_buf_i(.I(gt_clk_i),
                            .CE(1'b1),
                            .DIV(3'b000),
                            .CEMASK(1'b0),
                            .CLR(bufg_gt_clr_i),
                            .CLRMASK(1'b0),
                            .O(user_clk_o));
    assign sync_clk_o = user_clk_o;
    always @(posedge user_clk_o, posedge bufg_gt_clr_i) begin
        if (bufg_gt_clr_i) pll_not_locked <= 1'b1;
        else pll_not_locked <= 1'b0;
    end
      
    assign pll_not_locked_o = pll_not_locked;    
endmodule
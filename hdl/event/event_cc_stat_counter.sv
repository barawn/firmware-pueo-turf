`timescale 1ns / 1ps
`include "dsp_macros.vh"
// Include all 4 in one block, it's just easier.
// When transferring scaler counters across clock domains, it's usually easier
// to have a small counter in the source domain and the larger counter
// in the target domain - that way you don't have to transfer the full
// count, you can just add it up in chunks.
// If we tried to do a full 32 bits for instance we'd need to have
// active 32 bit counter in source
// holding 32 bit counter in source
// target 32 bit counter in destination
// + flag transfer when done
// here we just have 
// active 3 bit counter in source
// holding 3 bit counter in source
// target 32 bit counter in destination
// + same flag transfer.
// It's just a straight win. The only downside is that your count is delayed
// a bit, but that doesn't matter since none of this is time synced anyway.
module event_cc_stat_counter #(parameter NUM_COUNTS=4,
                               parameter WBCLKTYPE = "NONE",
                               parameter ACLKTYPE = "NONE")(
        input aclk,
        input [NUM_COUNTS-1:0] tx_valid_i,
        input wb_clk_i,
        input rst_i,
        output [NUM_COUNTS*32-1:0] tx_count_o
    );
    // the way flag crossings work is that you level change, sync the change, and generate
    // a flag on the other. so it's
    // 1 clock on source side
    // 0-1 clock on target side to sync
    // 1 clock sync again
    // 1 source + 1-2 destination
    // not really 1 clock source bc we use the flag to capture too
    // it still leaves us a full dest clock propagation.
    // This should comfortably work with a 100M/156.25M ratio.
    wire count_done;
    wire count_done_wbclk;
    wire [31:0] tx_count[NUM_COUNTS-1:0];
    clk_div_ce #(.CLK_DIVIDE(7)) u_timer(.clk(aclk),.ce(count_done));
    flag_sync u_sync(.in_clkA(count_done),.out_clkB(count_done_wbclk),
                     .clkA(aclk),.clkB(wb_clk_i));
    generate
        genvar i;
        for (i=0;i<NUM_COUNTS;i=i+1) begin : TIO
            reg [3:0] active_count = {4{1'b0}};
            (* CUSTOM_CC_SRC = ACLKTYPE *)
            reg [3:0] hold_count = {4{1'b0}};
            // YOU BASTARD WE NEED TO INSTANTIATE THE DAMN DSP OURSELVES
            // OTHERWISE THE ATTRIBUTES GET LOST WHEN IT GETS TRANSFORMED
            wire [47:0] dsp_C = { {44{1'b0}}, hold_count };
            wire [8:0] dsp_OPMODE = { 2'b00, `Z_OPMODE_P, `Y_OPMODE_C, `X_OPMODE_0 };
            wire [3:0] dsp_ALUMODE = `ALUMODE_SUM_ZXYCIN;
            wire [2:0] dsp_CARRYINSEL = `CARRYINSEL_CARRYIN;
            
            wire [47:0] dsp_P;
            assign tx_count[i] = dsp_P[0 +: 32];            
            (* CUSTOM_CC_DST = WBCLKTYPE *)
            DSP48E2 #( `A_UNUSED_ATTRS,
                       `B_UNUSED_ATTRS,
                       `DE2_UNUSED_ATTRS,
                       `CONSTANT_MODE_ATTRS,
                       `NO_MULT_ATTRS,
                       .CREG(1'b0),
                       .PREG(1'b1))
                       u_dsp( .CLK(wb_clk_i),
                              `A_UNUSED_PORTS,
                              `B_UNUSED_PORTS,
                              `D_UNUSED_PORTS,                              
                              .C(dsp_C),
                              .OPMODE(dsp_OPMODE),
                              .ALUMODE(dsp_ALUMODE),
                              .CARRYINSEL(dsp_CARRYINSEL),
                              .CARRYIN(1'b0),
                              .CEP(count_done_wbclk),
                              .RSTP(rst_i),
                              .P(dsp_P));                       
            always @(posedge aclk) begin : ACL
                // clk  count_done  valid   active_count    hold_count  count_done_wbclk wbclk_count
                // 0    0           0       0               0
                // 1    0           1       0               0
                // 2    0           1       1               0
                // 3    0           1       2               0
                // 4    0           0       3               0
                // 5    0           0       3               0
                // 6    0           0       3               0
                // 7    1           1       3               0
                // 8    0           0       1               3           0               0
                // 9    0           0       1               3           1               0
                //10    0           0       1               3           0               3
                if (count_done) active_count <= { {2{1'b0}}, tx_valid_i[i] };
                else active_count <= active_count + tx_valid_i[i];
                
                if (count_done) hold_count <= active_count;
            end  
            assign tx_count_o[32*i +: 32] = tx_count[i];
        end
    endgenerate    
    
endmodule

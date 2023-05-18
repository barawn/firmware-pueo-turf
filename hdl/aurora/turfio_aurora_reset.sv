`timescale 1ns / 1ps
// Reset module for the TURF's turfio_aurora module.
module turfio_aurora_reset(
        input reset_i,
        input user_clk_i,
        input init_clk_i,
        input gt_reset_i,
        output system_reset_o,
        output gt_reset_o
    );
    
    (* ASYNC_REG = "TRUE" *)
    (* SHREG_EXTRACT = "NO" *)
    reg [0:3]   debounce_gt_rst_r = {4{1'b0}};
    reg [0:3]   reset_debounce_r = {4{1'b0}};
    reg         reset_debounce_r2 = 1'b1;
    reg         gt_rst_r;
    
    wire gt_rst_sync;
    wire system_reset;
    
    // Clock synchronizer.
    // In the support Xilinx uses a universal-type
    // synchronizer but it's configured as:
    // single bit, register the input, level sync with no ack, 3 MTBF stages
    // They also list "vector_width" but that's pointless since there is no vector passed.
    // 3 MTBF stages means they do:
    // register the input (1 flop)
    // output is s_level_out_d3 which is 3 flops deep
    // This is equivalent to XPM_CDC_SINGLE with SRC_INPUT_REG(1) and
    // DEST_SYNC_FF(3)
    xpm_cdc_single #(.SRC_INPUT_REG(1),
                     .DEST_SYNC_FF(3))
            gt_rst_r_cdc_sync( .src_clk(init_clk_i),
                               .dest_clk(user_clk_i),
                               .src_in(gt_rst_r),
                               .dest_out(gt_rst_sync));

    // Doofy debounce for the reset input, if it's coming from
    // a switch or something.                               
    always @(posedge user_clk_i or posedge gt_rst_sync) begin
        if (gt_rst_sync) reset_debounce_r <= {4{1'b1}};
        else reset_debounce_r <= { reset_i, reset_debounce_r[0:2] };
    end
    always @(posedge user_clk_i) begin
        reset_debounce_r2 <= &reset_debounce_r;
    end    

    // And similarly debounce the gt_reset_i signal
    always @(posedge init_clk_i) begin
        debounce_gt_rst_r <= { gt_reset_i, debounce_gt_rst_r[0:2]};
        
        gt_rst_r <= &debounce_gt_rst_r;
    end
    
    assign system_reset_o = reset_debounce_r2;
    assign gt_reset_o = gt_rst_r;
endmodule

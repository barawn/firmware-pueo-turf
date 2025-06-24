`timescale 1ns / 1ps
// DEADTIME TRACKING AND BUFFER MANAGEMENT
// THIS IS THE SIMPLE VERSION: The only thing it does is count NUMBER
// of buffers held in the SURFs, not WHICH ONE.
//
// The occupancy output is a measure of the average buffer occupancy
// over the second. Every cycle it counts either 0,1,2,3 or 4.
// So if you imagine the ideal case with 100 Hz where no triggers
// overlap and it takes roughly 0.2 ms per readout, the counter
// would measure 0.2 * 100 = 20 ms/s or 2,457,600. 
//
// This module DOES NOT handle deadtime calcs, that happens in the
// time core so that when it's read out, you can read everything
// sync'd to the second you're reading. I don't think occupancy
// is helpful for anything other than monitoring, so it's just free.
module trig_buffer_track #(parameter SYSCLKTYPE = "NONE",
                           parameter WBCLKTYPE = "NONE",
                           parameter DEBUG = "TRUE")(
        input sys_clk_i,
        input pps_i,

        // trigger issued from master trig process
        input trig_i,
        // run reset (to clear errors and reset deadtime counter)
        input runrst_i,
        // run stop (holds deadtime)
        input runstop_i,
        
        // flag indicating that an event is complete and in RAM
        input last_flag_i,

        // no more triggers, yo
        output dead_o,
        // wtf you doin'
        
        input wb_clk_i,
        // occupancy at last PPS (roughly), in wishbone domain
        output [31:0] occupancy_o,
        output surf_err_o,
        output turf_err_o
    );

    reg [2:0] buffers_held = {3{1'b0}};

    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg surf_err = 0;
    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg turf_err = 0;
    
    (* CUSTOM_CC_DST = WBCLKTYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] surf_err_wbclk = {2{1'b0}};
    (* CUSTOM_CC_DST = WBCLKTYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] turf_err_wbclk = {2{1'b0}};    
    
    (* CUSTOM_MC_SRC_TAG = "TRIG_DEAD", CUSTOM_MC_MIN = "0.0", CUSTOM_MC_MAX = "1.0" *)
    reg dead = 0;

    reg running = 0;
    
    // occupancy is a pain in the neck but we be cheapin' yo
    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg [31:0] occupancy_counter = {32{1'b0}};
    wire pps_sync_wbclk;
    wire sync_wbclk_busy;
    flag_sync u_pps_sync(.in_clkA(pps_i),.out_clkB(pps_sync_wbclk),
                         .clkA(sys_clk_i),.clkB(wb_clk_i),
                         .busy_clkA(sync_wbclk_busy));
    // holdoff checks pps_i || sync_wbclk_busy to prevent counting
    // and then resets on sync_wbclk_was_busy && !sync_wbclk_busy.
    reg sync_wbclk_was_busy = 0;
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] occupancy_hold = {32{1'b0}};
    
    always @(posedge sys_clk_i) begin
        if (runrst_i) running <= 1;
        else if (runstop_i) running <= 0;

        // reset at run reset
        // if trigger, increment, if last flag, decrement,
        // if trigger and last flag do nothing, if last flag
        // and buffers_held == 0, freak out, if trigger and
        // buffers_held = 4, freak out.

        // Note that buffers_held *free runs*         
        if (runrst_i) buffers_held <= {3{1'b0}};
        else begin
            if (trig_i && !last_flag_i) buffers_held <= buffers_held + 1;
            else if (!trig_i && last_flag_i) buffers_held <= buffers_held - 1;
        end

        if (runrst_i) surf_err <= 0;                        
        else if (last_flag_i && buffers_held == 0 && running) surf_err <= 1;
        
        if (runrst_i) turf_err <= 0;
        else if (trig_i && buffers_held == 4 && running) turf_err <= 1;
        
        dead <= (buffers_held == 4) && running;

        sync_wbclk_was_busy <= sync_wbclk_busy;        
        if (sync_wbclk_was_busy && !sync_wbclk_busy)
            occupancy_counter <= {32{1'b0}};
        else begin
            if (!pps_i && !sync_wbclk_busy)
                occupancy_counter <= occupancy_counter + buffers_held;
        end        
    end
    
    // the occupancy counter isn't like, stupidly exact because we
    // don't care. we hold off the PPS reset until wbclk side's captured it.
    always @(posedge wb_clk_i) begin
        if (pps_sync_wbclk)
            occupancy_hold <= occupancy_counter;
            
        surf_err_wbclk <= { surf_err_wbclk[0], surf_err };
        turf_err_wbclk <= { turf_err_wbclk[0], turf_err };                   
    end
    
    generate
        if (DEBUG == "TRUE" ) begin : ILA
            buffer_track_ila u_ila(.clk(sys_clk_i),
                                   .probe0(buffers_held),
                                   .probe1(trig_i),
                                   .probe2(last_flag_i),
                                   .probe3(dead_o),
                                   .probe4(running));
        end
    endgenerate
    
    assign dead_o = dead;
    assign surf_err_o = surf_err_wbclk[1];
    assign turf_err_o = turf_err_wbclk[1];
    
    assign occupancy_o = occupancy_hold;
endmodule

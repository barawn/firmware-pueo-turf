`timescale 1ns / 1ps
// Reset module for the TURF's turfio_aurora module.
// This is version 2, because I don't think version 1 works
// AT ALL, even though it's taken from the exdes.
//
// Specifically, the power-on reset seems to be totally borked.
//
// The TURFIO's module seems to work, so we'll use it.
module turfio_aurora_reset_v2(
        input reset_i,
        input user_clk_i,
        input init_clk_i,
        input gt_reset_i,
        output system_reset_o,
        output gt_reset_o
    );
    parameter SIM_SPEEDUP = "FALSE";
    parameter DEBUG = "TRUE";
    
    localparam [47:0] HOTPLUG_DELAY = (SIM_SPEEDUP == "TRUE") ? 48'h10 : 48'h400_0000;
    
    // we work off a rising edge on reset_i
    reg reset_rereg = 0;
    
    // N.B.: the GT reset input is totally ignored.
    // reset_i is an input in the init_clk domain and starts the entire process.

    // system reset in init clk
    (* CUSTOM_CC_SRC = "INITCLK" *)
    reg system_reset_initclk = 1'b1;
    // resynced in user_clk
    (* ASYNC_REG = "TRUE", CUSTOM_CC_SRC="USERCLK", CUSTOM_CC_DST="USERCLK" *)
    reg [1:0] system_reset = 2'b11;
    
    // GT reset, sync to init clk
    reg gt_reset = 1'b1;
    // enable DSP counting for hotplug
    reg enable_hotplug_delay = 1'b0;

    // system reset, resynchronized back to init_clk
    (* ASYNC_REG = "TRUE", CUSTOM_CC_DST="INITCLK" *)
    reg [2:0] system_reset_resync = {3{1'b1}};    
    // Hotplug delay reached
    wire hotplug_delay_reached;
    // Reset begin delay reached
    wire gt_reset_delay_reached;
                
    localparam FSM_BITS=2;
    localparam [FSM_BITS-1:0] RESET = 0;            // exit either at power-on or after 2^26 clocks
    localparam [FSM_BITS-1:0] RESET_ENDING = 1;
    localparam [FSM_BITS-1:0] IDLE = 2;
    localparam [FSM_BITS-1:0] RESET_STARTING = 3;
    reg [FSM_BITS-1:0] state = RESET;
    
    // We have to special-case the situation where we get "stuck" in reset_ending because
    // user clk never comes up. I don't entirely know why this happens but _shrug_
    wire reset_flag = reset_i && !reset_rereg;

    always @(posedge init_clk_i) begin
        reset_rereg <= reset_i;
        
        case (state)
            RESET: if (!enable_hotplug_delay || hotplug_delay_reached) state <= RESET_ENDING;
            RESET_ENDING: if (!system_reset_resync[2]) state <= IDLE;
                          else if (reset_flag) state <= RESET_STARTING;
            IDLE: if (reset_flag) state <= RESET_STARTING;
            RESET_STARTING: if (gt_reset_delay_reached) state <= RESET;
        endcase
        if (state == RESET_STARTING && gt_reset_delay_reached) enable_hotplug_delay <= 1'b1;
        else if (state == RESET_ENDING) enable_hotplug_delay <= 1'b0;
        
        if (state == RESET_ENDING && !reset_flag) system_reset_initclk <= 1'b0;
        else begin
            if ((state == IDLE || state == RESET_ENDING) && reset_flag) system_reset_initclk <= 1'b1;                
        end

        if (state == RESET && (!enable_hotplug_delay || hotplug_delay_reached)) gt_reset <= 1'b0;
        else if (state == RESET_STARTING && gt_reset_delay_reached) gt_reset <= 1'b1;
        
        system_reset_resync <= {system_reset_resync[1:0], system_reset[1]};
    end
    
    always @(posedge user_clk_i) begin
        system_reset <= {system_reset[0],system_reset_initclk};
    end

    dsp_counter_terminal_count #(.FIXED_TCOUNT("TRUE"),
                                 .FIXED_TCOUNT_VALUE(HOTPLUG_DELAY))
        u_hpdelay(.clk_i(init_clk_i),
                  .rst_i(state != RESET),
                  .count_i(enable_hotplug_delay),
                  .tcount_reached_o(hotplug_delay_reached));

    dsp_counter_terminal_count #(.FIXED_TCOUNT("TRUE"),
                                 .FIXED_TCOUNT_VALUE(128))
        u_rst_dly(.clk_i(init_clk_i),
                  .rst_i(state != RESET_STARTING),
                  .count_i(state == RESET_STARTING),
                  .tcount_reached_o(gt_reset_delay_reached));                                   

    generate
        if (DEBUG == "TRUE") begin : ILA
            aurora_reset_ila u_ila(.clk(init_clk_i),
                                   .probe0(state),
                                   .probe1(system_reset_initclk),
                                   .probe2(system_reset_resync[2]),
                                   .probe3(gt_reset));
        end
    endgenerate

    assign system_reset_o = system_reset[1];
    assign gt_reset_o = gt_reset;

endmodule

`timescale 1ns / 1ps
`include "interfaces.vh"
// the '32' here is fake it includes the 4 unused TURFIO ports
module trig_pueo_wrap #(parameter WBCLKTYPE = "NONE",
                        parameter SYSCLKTYPE = "NONE",
                        parameter NSURF = 32,
                        parameter DEBUG = "TRUE")(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 14, 32 ),
        // these are logically split up into 67/68 but they're
        // global fanouts.
        input sysclk_i,
        // indicates we're in clock 1 of the 8 clock command cycle.
        input sysclk_phase_i,
        // this is the 7.8125M sync cycle
        input sysclk_sync_i,
        // sysclk x2
        input sysclk_x2_i,
        // to clean capture from sysclk_i
        input sysclk_x2_ce_i,

        input pps_i,
        // SOOOOO MANY INPUTS.
        // SURFs send triggers on a 4-clock cycle, even
        // though they train on the 8-clock cycle.
        // They actually send a total of 32 bits per trigger,
        // but the trigger info is always the first one and
        // then the following data (which does not have the top bit set)
        // is 8 bits of metadata.
        // We then process them in the x2 domain so we get
        // 8 clocks per cycle, which allows us to multiplex all
        // of the SURFs into one URAM.
        input [NSURF*16-1:0] trig_dat_i,
        // we actually end up ignoring these since we use the trigger
        // mask.
        input [NSURF-1:0] trig_dat_valid_i,
        
        output [31:0] command67_o,
        output [31:0] command68_o
    );
    // it's 3 clocks from phase -> trig dat valid.
    // then the *second* trig dat valid comes in 4 clocks later.
    // so normally SRL delays would be 2 and 6.
    // we rewind those by 1 to allow a registered or:
    // giving 
    localparam [3:0] VALID_OFFSET = 4'd1;
    localparam [3:0] VALID_OFFSET_2 = 4'd5;
    
    wire phase_delayed;
    wire phase_delayed_2;
    reg trigger_valid = 0;
    // and we ALSO can use it to qualify when TURF can issue
    // a trigger.
    wire turf_trigger_ce = phase_delayed || phase_delayed_2;
    SRL16E u_delay1(.D(sysclk_phase_i),
                    .CE(1'b1),
                    .CLK(sysclk_i),
                    .A0(VALID_OFFSET[0]),
                    .A1(VALID_OFFSET[1]),
                    .A2(VALID_OFFSET[2]),
                    .A3(VALID_OFFSET[3]),
                    .Q(phase_delayed));
    SRL16E u_delay2(.D(sysclk_phase_i),
                    .CE(1'b1),
                    .CLK(sysclk_i),
                    .A0(VALID_OFFSET_2[0]),
                    .A1(VALID_OFFSET_2[1]),
                    .A2(VALID_OFFSET_2[2]),
                    .A3(VALID_OFFSET_2[3]),
                    .Q(phase_delayed_2));
    always @(posedge sysclk_i) trigger_valid <= phase_delayed || phase_delayed_2;
    
    // probably add more here or something, or maybe split off
    `DEFINE_AXI4S_MIN_IF( trig_ , 16 );
    assign trig_tvalid = 1'b0;
    assign trig_tdata = {16{1'b0}};
    
    // just grab phase and valid right now to time them up
    generate
        if (DEBUG == "TRUE") begin : DBG
            trig_ila u_ila(.clk(sysclk_i),
                           .probe0(trig_dat_valid_i),
                           .probe1(sysclk_phase_i));
        end
    endgenerate    
    trig_pueo_command #(.WBCLKTYPE(WBCLKTYPE),
                        .SYSCLKTYPE(SYSCLKTYPE))
                      u_command( .wb_clk_i(wb_clk_i),
                                 .wb_rst_i(wb_rst_i),
                                 `CONNECT_WBS_IFS( wb_ , wb_ ),
                                 .sysclk_i(sysclk_i),
                                 .sysclk_phase_i(sysclk_phase_i),
                                 .sysclk_sync_i(sysclk_sync_i),
                                 .pps_i(pps_i),
                                 
                                 .command67_o(command67_o),
                                 .command68_o(command68_o));
    
endmodule

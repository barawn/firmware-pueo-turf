`timescale 1ns / 1ps
`include "interfaces.vh"
// the '32' here is fake it includes the 4 unused TURFIO ports

// this is just called v3 because the modules in it are v3s,
// there was no v2.
module trig_pueo_wrap_v3 #(parameter WBCLKTYPE = "NONE",
                        parameter SYSCLKTYPE = "NONE",
                        parameter MEMCLKTYPE = "NONE",
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
        input [31:0] cur_sec_i,
        input [31:0] cur_time_i,
        input [31:0] last_pps_i,
        input [31:0] llast_pps_i,
        input [31:0] cur_dead_i,
        input [31:0] last_dead_i,
        input [31:0] llast_dead_i,
        
        output track_events_o,
        input event_complete_i,
        input panic_i,
        output dead_o,
        
        
        // run config
        input [3:0] tio_mask_i,         // IN SYSCLK
        input [11:0] runcfg_i,          // IN SYSCLK
        output runrst_o,
        
        input pps_trig_i,
        input [5:0] gp_in_i,
        output photoshutter_o,

        output gpo_run_ce_o, 
        output gpo_run_d_o,  
        output gpo_trig_ce_o,
        output gpo_trig_d_o, 
        
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

        // probably needs a tlast or something, who knows        
        input memclk,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( turfhdr_ , 64 ),
        output turfhdr_tlast,
        
        output [31:0] command67_o,
        output [31:0] command68_o
    );

    localparam [15:0] DEFAULT_HOLDOFF = 16'd82;
    localparam [15:0] DEFAULT_LATENCY = 16'd100;
    localparam [15:0] DEFAULT_OFFSET = 16'd0;
    localparam [15:0] DEFAULT_PHOTO_PRESCALE = 16'd100;
    localparam [3:0]  DEFAULT_RUNDLY = 3;            

    localparam REAL_SURFS_PER_TIO = 7;
    // it's 3 clocks from phase -> trig dat valid.
    // then the *second* trig dat valid comes in 4 clocks later.
    // so normally SRL delays would be 2 and 6.
    // we rewind those by 1 to allow a registered or:
    // giving 
    localparam [3:0] VALID_OFFSET = 4'd1;
    localparam [3:0] VALID_OFFSET_2 = 4'd5;

    wire [4*REAL_SURFS_PER_TIO*16-1:0] real_trigin;
    generate
        genvar t;
        for (t=0;t<4;t=t+1) begin
            assign real_trigin[REAL_SURFS_PER_TIO*16*t +: REAL_SURFS_PER_TIO*16] =
                trig_dat_i[8*16*t +: REAL_SURFS_PER_TIO*16];
        end    
    endgenerate
    
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

    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [1:0] panic_sysclk = {2{1'b0}};
    always @(posedge sysclk_i) panic_sysclk <= { panic_sysclk[0], panic_i };
    wire panic_in_sysclk = panic_sysclk[1];
    
    // probably add more here or something, or maybe split off
    `DEFINE_AXI4S_MIN_IF( trig_ , 16 );

    wire [27:0] trig_mask;
    wire        trig_mask_update;
    wire [15:0] trig_offset;
    wire [15:0] trig_latency;
    wire [15:0] trig_holdoff;
    
    wire [11:0] turf_soft_trig;
    wire [7:0]  turf_soft_metadata;
    wire        turf_soft_valid;

    wire [11:0] turf_pps_trig;
    wire [7:0]  turf_pps_metadata;
    wire        turf_pps_valid;
    
    wire [11:0] turf_ext_trig;
    wire [7:0]  turf_ext_metadata;
    wire        turf_ext_valid;    

    wire [11:0] turf_rsv_trig = {12{1'b0}};
    wire [7:0]  turf_rsv_metadata = {8{1'b0}};
    wire        turf_rsv_valid = 1'b0;

    wire        runrst;
    wire        runstop;

    wire [11:0] cur_addr;
    wire        running;
    
    wire        trig_event_flag;
    
    wire [31:0] scal_trig;

    // over to trigctrl, in wbclk
    wire [31:0] occupancy;
    wire surf_err;
    wire turf_err;
    wire [15:0] photo_prescale;
    wire photo_en;        
    pueo_master_trig_process_v3 #(.SYSCLKTYPE(SYSCLKTYPE),
                               .MEMCLKTYPE(MEMCLKTYPE),
                               .WBCLKTYPE(WBCLKTYPE),
                               .DEFAULT_OFFSET(DEFAULT_OFFSET),
                               .DEFAULT_LATENCY(DEFAULT_LATENCY),
                               .DEFAULT_HOLDOFF(DEFAULT_HOLDOFF),
                               .DEFAULT_PHOTO_PRESCALE(DEFAULT_PHOTO_PRESCALE))
        u_master_trig(.sysclk_i(sysclk_i),
                      .sysclk_phase_i(sysclk_phase_i),
                      .sysclk_x2_i(sysclk_x2_i),
                      .sysclk_x2_ce_i(sysclk_x2_ce_i),
                      .trigmask_i(trig_mask),
                      .trigmask_update_i(trig_mask_update),
                      .trig_offset_i(trig_offset),
                      .trig_latency_i(trig_latency),
                      .trig_holdoff_i(trig_holdoff),
                      .photo_prescale_i(photo_prescale),
                      .photo_en_i(photo_en),
                      
                      .gpo_run_ce_o(gpo_run_ce_o),
                      .gpo_run_d_o(gpo_run_d_o),
                      .gpo_trig_ce_o(gpo_trig_ce_o),
                      .gpo_trig_d_o(gpo_trig_d_o),
                      
                      .trigin_dat_i(real_trigin),
                      .trigin_dat_valid_i(trigger_valid),
                      
                      .turf_trig0_i(turf_soft_trig),
                      .turf_metadata0_i(turf_soft_metadata),
                      .turf_valid0_i(turf_soft_valid),
                      
                      .turf_trig1_i(turf_pps_trig),
                      .turf_metadata1_i(turf_pps_metadata),
                      .turf_valid1_i(turf_pps_valid),
                      
                      .turf_trig2_i(turf_ext_trig),
                      .turf_metadata2_i(turf_ext_metadata),
                      .turf_valid2_i(turf_ext_valid),
                      
                      .turf_trig3_i(turf_rsv_trig),
                      .turf_metadata3_i(turf_rsv_metadata),
                      .turf_valid3_i(turf_rsv_valid),                      
                      
                      .runrst_i(runrst),
                      .runstop_i(runstop),
                      .address_o(cur_addr),
                      .running_o(running),
                      
                      .scal_trig_o(scal_trig),
                      
                      .cur_sec_i(cur_sec_i),
                      .cur_time_i(cur_time_i),
                      .last_pps_i(last_pps_i),
                      .llast_pps_i(llast_pps_i),
                      .cur_dead_i(cur_dead_i),
                      .last_dead_i(last_dead_i),
                      .llast_dead_i(llast_dead_i),
                      .dead_o(dead_o),
                      .pps_i(pps_i),
                      
                      .wb_clk_i(wb_clk_i),
                      .event_complete_i(event_complete_i),
                      .panic_i(panic_in_sysclk),
                      .occupancy_o(occupancy),
                      .surf_err_o(surf_err),
                      .turf_err_o(turf_err),
                      
                      .tio_mask_i(tio_mask_i),
                      .runcfg_i(runcfg_i),

                      .photoshutter_o(photoshutter_o),

                      .event_o(trig_event_flag),
                                            
                      `CONNECT_AXI4S_MIN_IF(trigout_ , trig_ ),
                      
                      .memclk_i(memclk),
                      `CONNECT_AXI4S_MIN_IF(turf_hdr_ , turfhdr_ ),
                      .turf_hdr_tlast(turfhdr_tlast));

    generate
        genvar i;
        if (DEBUG == "TRUE") begin : DBG
            trig_ila u_ila(.clk(sysclk_i),
                           .probe0(turf_soft_valid),
                           .probe1(turf_pps_valid),
                           .probe2(turf_ext_valid),
                           .probe3(turf_ext_trig),
                           .probe4(cur_addr),
                           .probe5(trig_tdata),
                           .probe6(trig_tvalid));
        end
    endgenerate    
    // our wb space here is 8 bits = 64 registers
    // we obviously have 14 total
    // we can do:
    // trigger control (also 8 bits)
    // 0: trigger masks (probably also add a global or something)
    // 1: trigger latency (time to allow SURF triggers to arrive)
    // 2: common trigger offset (subtract from trigger time)
    // 3: software trigger offset (combined with common)
    // 4: pps trigger offset (combined with common)
    // 5: ext trigger offset (combined with common)
    // 6: soft trigger generation
    // 7: ext/pps trigger control
    // and then maybe an additional block for
    // system time (clocks, pps, deadtime, etc.)
    // plus another for scalers (this will need ~32 addresses, but that's OK)
    // .... it's like it's an experiment or something
    // that gives us 4 blocks to start out with.
    //
    // scalers, as always, will be a mild pain in the ass since
    // they functionally will need to be dual-ported. it's fine, it's fine.
    wire [1:0] wb_block = wb_adr_i[8 +: 2];    
    wire [31:0] wb_dat_vec[3:0];
    wire [3:0] wb_ack_vec;
    wire [3:0] wb_rty_vec;
    wire [3:0] wb_err_vec;
    `DEFINE_WB_IF( cmd_ , 8, 32 );
    `DEFINE_WB_IF( trigctl_ , 8, 32 );
    // WHO KNOWS, MAN
    `DEFINE_WB_IF( rsvd_ , 8, 32 );
    `DEFINE_WB_IF( scaler_ , 8, 32 );
    
    `define MAP_BLOCK( outpfx , inpfx , idx )    \
        assign outpfx``dat_o = inpfx``dat_i;    \
        assign outpfx``adr_o = inpfx``adr_i;    \
        assign outpfx``cyc_o = inpfx``cyc_i;    \
        assign outpfx``stb_o = inpfx``stb_i && (wb_block == idx);   \
        assign outpfx``we_o = inpfx``we_i;      \
        assign outpfx``sel_o = inpfx``sel_i;    \
        assign inpfx``dat_vec[idx] = outpfx``dat_i;  \
        assign inpfx``ack_vec[idx] = outpfx``ack_i; \
        assign inpfx``rty_vec[idx] = outpfx``rty_i; \
        assign inpfx``err_vec[idx] = outpfx``err_i

    `MAP_BLOCK( cmd_ , wb_ , 0);
    `MAP_BLOCK( trigctl_ , wb_ , 1);
    `MAP_BLOCK( rsvd_ , wb_ , 2);
    `MAP_BLOCK( scaler_ , wb_ , 3);

    wbs_dummy #(.ADDRESS_WIDTH(8),.DATA_WIDTH(32))
        u_rsvd( `CONNECT_WBS_IFM( wb_ , rsvd_ ) );

    pueo_scaler_wrap #(.WBCLKTYPE(WBCLKTYPE),
                       .SYSCLKTYPE(SYSCLKTYPE),
                       .ETHCLKTYPE(MEMCLKTYPE))
                     u_scalers(.wb_clk_i(wb_clk_i),
                               .wb_rst_i(wb_rst_i),
                               `CONNECT_WBS_IFM(wb_ , scaler_ ),
                               .pps_i(pps_i),
                               .gp_gate_i(gp_in_i),
                               
                               .sys_clk_i(sysclk_i),
                               .sys_adr_i(),
                               .sys_dat_o(),
                               .eth_clk_i(),
                               .eth_adr_i(),
                               .eth_dat_o(),
                               
                               .trig_i(scal_trig));

    assign wb_ack_o = wb_ack_vec[wb_block];
    assign wb_dat_o = wb_dat_vec[wb_block];
    assign wb_err_o = wb_err_vec[wb_block];
    assign wb_rty_o = wb_rty_vec[wb_block];
    
    pueo_trig_ctrl_v3 #(.WBCLKTYPE(WBCLKTYPE),
                     .SYSCLKTYPE(SYSCLKTYPE),
                     .DEFAULT_LATENCY(DEFAULT_LATENCY),
                     .DEFAULT_HOLDOFF(DEFAULT_HOLDOFF),
                     .DEFAULT_OFFSET(DEFAULT_OFFSET),
                     .DEFAULT_PHOTO_PRESCALE(DEFAULT_PHOTO_PRESCALE))
                      u_trigctrl( .wb_clk_i(wb_clk_i),
                                  .wb_rst_i(wb_rst_i),
                                  `CONNECT_WBS_IFM(wb_ , trigctl_ ),
                                  .sysclk_i(sysclk_i),
                                  .sysclk_phase_i(sysclk_phase_i),
                                  .turf_soft_trig_o(turf_soft_trig),
                                  .turf_soft_metadata_o(turf_soft_metadata),
                                  .turf_soft_valid_o(turf_soft_valid),
                                  
                                  .turf_pps_trig_o(turf_pps_trig),
                                  .turf_pps_metadata_o(turf_pps_metadata),
                                  .turf_pps_valid_o(turf_pps_valid),

                                  .turf_ext_trig_o(turf_ext_trig),
                                  .turf_ext_metadata_o(turf_ext_metadata),
                                  .turf_ext_valid_o(turf_ext_valid),
                                  
                                  .event_i(trig_event_flag),
                                  
                                  .cur_addr_i(cur_addr),
                                  .running_i(running),
                                  .trig_mask_o(trig_mask),
                                  .update_trig_mask_o(trig_mask_update),
                                  .trig_offset_o(trig_offset),
                                  .trig_latency_o(trig_latency),
                                  .trig_holdoff_o(trig_holdoff),
                                  .photo_prescale_o(photo_prescale),
                                  .photo_en_o(photo_en),
                                  
                                  .pps_trig_i(pps_trig_i),
                                  .gp_in_i(gp_in_i),
                                  .occupancy_i(occupancy),
                                  .surf_err_i(surf_err),
                                  .turf_err_i(turf_err)
                                  );
            
    trig_pueo_command #(.WBCLKTYPE(WBCLKTYPE),
                        .SYSCLKTYPE(SYSCLKTYPE),
                        .DEFAULT_RUNDLY(DEFAULT_RUNDLY))
                      u_command( .wb_clk_i(wb_clk_i),
                                 .wb_rst_i(wb_rst_i),
                                 `CONNECT_WBS_IFM( wb_ , cmd_ ),
                                 .sysclk_i(sysclk_i),
                                 .sysclk_phase_i(sysclk_phase_i),
                                 .sysclk_sync_i(sysclk_sync_i),
                                 .pps_i(pps_i),
                                 
                                 .runrst_o(runrst),
                                 .runstop_o(runstop),
                                 
                                 `CONNECT_AXI4S_MIN_IF(s_trig_ , trig_ ),
                                 
                                 .command67_o(command67_o),
                                 .command68_o(command68_o));
    assign runrst_o = runrst;
    assign track_events_o = running;
endmodule

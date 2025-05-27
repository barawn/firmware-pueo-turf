`timescale 1ns / 1ps
`define DLYFF #0.1
`include "interfaces.vh"
module pueo_master_trigger_process_tb;

    // so many clocks
    wire wb_clk;
    tb_rclk #(.PERIOD(10.0)) u_wbclk(.clk(wb_clk));
    wire sysclk;
    tb_rclk #(.PERIOD(8.0)) u_clk(.clk(sysclk));

    // we'll use the system_clock_v2 module. that way phase matches.
    wire sys_clk;
    wire sys_clk_x2;
    wire sys_clk_x2_ce;
    wire sys_clk_phase;
        
    system_clock_v2 #(.INVERT_MMCM("FALSE"))
        u_sysclk(.SYS_CLK_P(sysclk),
                 .SYS_CLK_N(~sysclk),
                 .reset(1'b0),
                 .sysclk_o(sys_clk),
                 .sysclk_x2_o(sys_clk_x2),
                 .sysclk_x2_ce_o(sys_clk_x2_ce),
                 .sysclk_phase_o(sys_clk_phase));
    // we now need to fake the HELL out of data
    reg [2:0] sys_clk_phase_dly = {3{1'b0}};
    always @(posedge sys_clk) sys_clk_phase_dly <= `DLYFF { sys_clk_phase_dly[1:0], sys_clk_phase };
    
    localparam NSURF = 28;
    localparam NBIT = 16;
    wire [NSURF*NBIT-1:0] trig_in = {NSURF*NBIT{1'b0}};
    wire trigin_dat_valid_i = sys_clk_phase_dly[2];
    wire trigin_will_be_valid = sys_clk_phase_dly[1];
        
    reg runrst = 0;
    reg runstop = 0;
    reg [11:0] turf_trig = {12{1'b0}};
    reg        turf_trig_valid = 0;
    
    reg [27:0] trigmask = {28{1'b1}};
    reg trigmask_update = 0;
    // deal with this later. you just take rdaddr and subtract
    // this. happy happy DSPs.
    reg [15:0] trig_offset = {16{1'b0}};
    // this is pretty darn big, like 1.6 us.
    reg [15:0] trig_latency = 200;

    wire [15:0] trigout_tdata;
    wire        trigout_tvalid;
    wire        trigout_tready = 1'b1;

    wire [63:0] turf_hdr_tdata;
    wire        turf_hdr_tvalid;
    wire        turf_hdr_tready;
    pueo_master_trig_process uut(.sysclk_i(sys_clk),
                                 .sysclk_phase_i(sys_clk_phase),
                                 .sysclk_x2_i(sys_clk_x2),
                                 .sysclk_x2_ce_i(sys_clk_x2_ce),
                                 .wb_clk_i(wb_clk),
                                 .trigmask_i( trigmask ),
                                 .trigmask_update_i( trigmask_update ),
                                 .trig_offset_i(trig_offset),
                                 .trig_latency_i(trig_latency),
                                 .trigin_dat_i( trig_in ),
                                 .trigin_dat_valid_i( trigin_dat_valid_i ),
                                 .turf_trig_i( turf_trig ),
                                 .turf_metadata_i( 8'h00 ),
                                 .turf_valid_i( turf_trig_valid ),
                                 .runrst_i( runrst ),
                                 .runstop_i( runstop ),
                                 `CONNECT_AXI4S_MIN_IF( trigout_ , trigout_ ),
                                 `CONNECT_AXI4S_MIN_IF( turf_hdr_ , turf_hdr_ ));
    
    reg do_trig = 0;
    reg do_trig_rereg = 0;
    // turf_trig_valid      valid_shreg
    // 1                    000
    // 1                    001
    // 1                    010
    // 1                    100
    reg [2:0] turf_trig_valid_shreg = {3{1'b0}};
    reg [31:0] cur_time = {32{1'b0}};
    // really this should just be a FIFO
    always @(posedge sys_clk) begin
        if (runrst) cur_time <= `DLYFF {32{1'b0}};
        else cur_time <= `DLYFF cur_time + 1;
        
        turf_trig_valid_shreg <= { turf_trig_valid_shreg[1:0], turf_trig_valid };
        
        if (turf_trig_valid_shreg[2]) turf_trig_valid <= `DLYFF 0;
        else if (do_trig && trigin_will_be_valid) turf_trig_valid <= `DLYFF 1;

        do_trig_rereg <= `DLYFF do_trig;
        if (do_trig && !do_trig_rereg) turf_trig <= `DLYFF cur_time[11:0];
    end

    initial begin
        #1000;
        @(posedge sys_clk); #0.1 runrst <= `DLYFF 1;
        @(posedge sys_clk); #0.1 runrst <= `DLYFF 0;
        
        #1000;
        @(posedge sys_clk); do_trig <= `DLYFF 1;
        while (!turf_trig_valid) @(posedge sys_clk);
        do_trig <= `DLYFF 0;
    end    

endmodule

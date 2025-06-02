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
    wire sys_clk_sync;
        
    system_clock_v2 #(.INVERT_MMCM("FALSE"))
        u_sysclk(.SYS_CLK_P(sysclk),
                 .SYS_CLK_N(~sysclk),
                 .reset(1'b0),
                 .sysclk_o(sys_clk),
                 .sysclk_x2_o(sys_clk_x2),
                 .sysclk_x2_ce_o(sys_clk_x2_ce),
                 .sysclk_phase_o(sys_clk_phase),
                 .sysclk_sync_o(sys_clk_sync));
    // we now need to fake the HELL out of data
    reg [2:0] sys_clk_phase_dly = {3{1'b0}};
    always @(posedge sys_clk) sys_clk_phase_dly <= `DLYFF { sys_clk_phase_dly[1:0], sys_clk_phase };
    
    localparam NSURF = 32;
    localparam NBIT = 16;
    wire [NSURF*NBIT-1:0] trig_in = {NSURF*NBIT{1'b0}};
    wire trigin_dat_valid_i = sys_clk_phase_dly[2];
    wire trigin_will_be_valid = sys_clk_phase_dly[1];
        
    // OK - with the new integrated testbench, this stuff is all internal.
//    reg runrst = 0;
//    reg runstop = 0;
//    reg [11:0] turf_trig = {12{1'b0}};
//    reg        turf_trig_valid = 0;
    
//    reg [27:0] trigmask = {28{1'b1}};
//    reg trigmask_update = 0;
//    // deal with this later. you just take rdaddr and subtract
//    // this. happy happy DSPs.
//    reg [15:0] trig_offset = {16{1'b0}};
//    // this is pretty darn big, like 1.6 us.
//    reg [15:0] trig_latency = 200;

//    wire [15:0] trigout_tdata;
//    wire        trigout_tvalid;
//    wire        trigout_tready = 1'b1;

//    wire [63:0] turf_hdr_tdata;
//    wire        turf_hdr_tvalid;
//    wire        turf_hdr_tready;
//    pueo_master_trig_process uut(.sysclk_i(sys_clk),
//                                 .sysclk_phase_i(sys_clk_phase),
//                                 .sysclk_x2_i(sys_clk_x2),
//                                 .sysclk_x2_ce_i(sys_clk_x2_ce),
//                                 .wb_clk_i(wb_clk),
//                                 .trigmask_i( trigmask ),
//                                 .trigmask_update_i( trigmask_update ),
//                                 .trig_offset_i(trig_offset),
//                                 .trig_latency_i(trig_latency),
//                                 .trigin_dat_i( trig_in ),
//                                 .trigin_dat_valid_i( trigin_dat_valid_i ),
//                                 .turf_trig_i( turf_trig ),
//                                 .turf_metadata_i( 8'h00 ),
//                                 .turf_valid_i( turf_trig_valid ),
//                                 .runrst_i( runrst ),
//                                 .runstop_i( runstop ),
//                                 `CONNECT_AXI4S_MIN_IF( trigout_ , trigout_ ),
//                                 `CONNECT_AXI4S_MIN_IF( turf_hdr_ , turf_hdr_ ));

    `DEFINE_WB_IF( wb_ , 14, 32 );
    reg wb_cyc = 0;
    reg wb_we = 0;
    reg [31:0] wb_dat = {32{1'b0}};
    reg [13:0] wb_adr = {14{1'b0}};
    assign wb_cyc_o = wb_cyc;
    assign wb_stb_o = wb_cyc;
    assign wb_we_o = wb_we;
    assign wb_sel_o = {4{1'b1}};
    assign wb_adr_o = wb_adr;
    assign wb_dat_o = wb_dat;
    `DEFINE_AXI4S_MIN_IF( turfhdr_ , 64 ); 
    assign turfhdr_tready = 1'b1;           
    trig_pueo_wrap #(.DEBUG("FALSE"))
        u_trig( .wb_clk_i(wb_clk),
                .wb_rst_i(1'b0),
                `CONNECT_WBS_IFM( wb_ , wb_ ),
                .sysclk_i(sys_clk),
                .sysclk_phase_i(sys_clk_phase),
                .sysclk_sync_i(sys_clk_sync),
                .sysclk_x2_i(sys_clk_x2),
                .sysclk_x2_ce_i(sys_clk_x2_ce),
                .pps_i(1'b0),
                .trig_dat_i(trig_in),
                .trig_dat_valid_i(trigin_dat_valid_i),
                `CONNECT_AXI4S_MIN_IF( turfhdr_ , turfhdr_ ));
                    
//    reg do_trig = 0;
//    reg do_trig_rereg = 0;
//    // turf_trig_valid      valid_shreg
//    // 1                    000
//    // 1                    001
//    // 1                    010
//    // 1                    100
//    reg [2:0] turf_trig_valid_shreg = {3{1'b0}};
//    reg [31:0] cur_time = {32{1'b0}};
//    // really this should just be a FIFO
//    always @(posedge sys_clk) begin
//        if (runrst) cur_time <= `DLYFF {32{1'b0}};
//        else cur_time <= `DLYFF cur_time + 1;
        
//        turf_trig_valid_shreg <= { turf_trig_valid_shreg[1:0], turf_trig_valid };
        
//        if (turf_trig_valid_shreg[2]) turf_trig_valid <= `DLYFF 0;
//        else if (do_trig && trigin_will_be_valid) turf_trig_valid <= `DLYFF 1;

//        do_trig_rereg <= `DLYFF do_trig;
//        if (do_trig && !do_trig_rereg) turf_trig <= `DLYFF cur_time[11:0];
//    end

//    initial begin
//        #1000;
//        @(posedge sys_clk); #0.1 runrst <= `DLYFF 1;
//        @(posedge sys_clk); #0.1 runrst <= `DLYFF 0;
        
//        #1000;
//        @(posedge sys_clk); do_trig <= `DLYFF 1;
//        while (!turf_trig_valid) @(posedge sys_clk);
//        do_trig <= `DLYFF 0;
//    end    

    task wb_write;
        input [13:0] addr;
        input [31:0] data;
        begin
            @(posedge wb_clk);
            #1 wb_cyc = 1;
               wb_we = 1;
               wb_adr = addr;
               wb_dat = data;
            @(posedge wb_clk);
            while (!wb_ack_i) @(posedge wb_clk);
            #1 wb_cyc = 0;
               wb_we = 0;
               wb_adr = {14{1'b0}};
               wb_dat = {32{1'b0}};
        end
    endtask                       

    initial begin
        #1000;
        wb_write( 32'h104, 32'd200 );
        #100;
        wb_write( 32'h000, 32'd2 );        
        #1000;
        wb_write( 32'h110, 32'd1 );
        #1000;
        wb_write( 32'h110, 32'd1 );
        #1000;
        wb_write( 32'h110, 32'd1 );
    end        

endmodule

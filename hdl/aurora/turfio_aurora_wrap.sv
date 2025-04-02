`timescale 1ns / 1ps
`include "interfaces.vh"
`include "mgt.vh"
// Wrap the entire TURFIO aurora interface.
//
// DRP takes up 10 bits, and we have 4 of them, so we need
// 12 bits nominally. 14-bits because we need a 32-bit interface
// (yes DRP is 16 but not doing that)
// and we grab an additional bit for the control space.
// So 15-bits total.
// 0x0000 - 3FFF : Overall control/status space
// 0x4000 - 4FFF : DRP aurora 0
// 0x5000 - 5FFF : DRP aurora 1
// 0x6000 - 6FFF : DRP aurora 2
// 0x7000 - 7FFF : DRP aurora 3
// so DRP is wb_adr_i[14]
// The control/status space is similarly split up in half and in 4, but the
// "individual" controls are in the beginning. We don't have any globals yet
// but that'll come. So:
// 0x0000 - 1FFF : Individual control/status space
//   0000 - 07FF : control/status aurora 0
//   0800 - 0FFF : control/status aurora 1
//   1000 - 17FF : control/status aurora 2
//   1800 - 1FFF : control/status aurora 3
//   2000 - 3FFF : global control/status
// So the individual controls are selected when
// !wb_adr_i[13] && (wb_adr_i[12:11] == i)
// Individual control/status:
//   base +  000 : link control
//   base +  004 : link status
//   base +  008 : eye scan controls
//   base +  00C : digital monitor outputs
// Global control/status:
//   base +  000 : global link control
//
// Note that bits 0 and 1 (reset/gt_reset) are common
// in all individual control/status and the global control/status.
// This is done by only checking the low 11 bits.
// Set them once, set them everywhere. This is because since the user_clocks
// are common and screwed with, it's best to just do a full reset everywhere.
module turfio_aurora_wrap
    #(  parameter TX_CLOCK_SEL = 0,
        parameter NUM_MGT = 4,
        parameter USE_DEBUG = 4'b0001,
        parameter WBCLKTYPE = "NONE" )
    (
        // this is the LOCAL aurora WISHBONE interface
        // it is NOT the interface for talking to the
        // TURFIOs via MGT. Those are handled externally
        // and treated as AXI4-Stream interfaces here.
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 15, 32 ),
        
        // This is the AXI4-Stream input for command path to TURFIO. In wb_clk domain
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_cmd_ , 32 ),
        // This is the destination Aurora link
        input [1:0] s_cmd_tdest,
        // This indicates it's the last of a transaction
        input       s_cmd_tlast,
        // This is the AXI4-Stream response from TURFIO. In wb_clk domain
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_resp_ , 32 ),
        // This indicates which Aurora link it comes from
        output [1:0] m_resp_tuser,
        // Last of a transaction
        output       m_resp_tlast,
        
        // Logic indications that the links are up
        output [3:0] aurora_up_o,        
        
        // Aurora clock output for monitoring
        output      aurora_clk_o,

        // array of MGT interfaces
        output [32*NUM_MGT-1:0] m_aurora_tdata,
        output [NUM_MGT-1:0]    m_aurora_tvalid,
        output [NUM_MGT-1:0]    m_aurora_tlast,
        // ignored
        input  [NUM_MGT-1:0]    m_aurora_tready,
            
        input MGTCLK_P,
        input MGTCLK_N,
        
        input [NUM_MGT-1:0] MGTRX_P,
        input [NUM_MGT-1:0] MGTRX_N,
        output [NUM_MGT-1:0] MGTTX_P,
        output [NUM_MGT-1:0] MGTTX_N                
    );

    // Link status vectors.
    wire [31:0] link_status[NUM_MGT-1:0];
    // Link control registers.
    wire [31:0] link_control[NUM_MGT-1:0];
    // Link digital monitor registers
    wire [31:0] link_dmonitor[NUM_MGT-1:0];
    // Link eye scan control registers
    wire [31:0] link_eyescan[NUM_MGT-1:0];
        
    // create the interfaces. 
    `DEFINE_AXI4S_IFV( aurora_tx_ , 32, [NUM_MGT-1:0] );
    `DEFINE_AXI4S_IFV( aurora_rx_ , 32, [NUM_MGT-1:0] );
    // and devec-ify for the output (ignoring tkeep)
    assign m_aurora_tdata = { aurora_rx_tdata[3], aurora_rx_tdata[2], aurora_rx_tdata[1], aurora_rx_tdata[0] };
    assign m_aurora_tvalid ={ aurora_rx_tvalid[3], aurora_rx_tvalid[2], aurora_rx_tvalid[1], aurora_rx_tvalid[0] };
    assign m_aurora_tlast = { aurora_rx_tlast[3], aurora_rx_tvalid[2], aurora_rx_tvalid[1], aurora_rx_tvalid[0] };

    // The UFC interfaces are spliced into the normal ones:
    // their AXI4-Stream data indicates the *length*. The data
    // is carried via a separate path.
    `DEFINE_AXI4S_IFV( ufc_tx_ , 8, [NUM_MGT-1:0] );
    wire [31:0] ufc_tx_aurora_data[NUM_MGT-1:0];

    // UFC receive path, in userclk
    `DEFINE_AXI4S_MIN_IFV( ufc_rx_ , 32, [NUM_MGT-1:0] );
    wire ufc_rx_tlast[NUM_MGT-1:0];
    
    // we HAVE to have a small CC fifo for each Aurora link b/c we don't have a tready
    `DEFINE_AXI4S_MIN_IFV( ufc_rx_wbclk_ , 32, [NUM_MGT-1:0] );
    wire ufc_rx_wbclk_tlast[NUM_MGT-1:0];
        
    // MGT clock input buffer. Note that this is *inverted*, although
    // it doesn't matter: the MGT interface is treated as asynchronous to system clock.
    wire mgt_clk_ibuf;
    wire mgt_clk_bufg;
    wire mgt_clk;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00))
        u_mgt_ibuf(.I(MGTCLK_N),.IB(MGTCLK_P),.CEB(1'b0),.O(mgt_clk), .ODIV2(mgt_clk_ibuf));

    BUFG_GT u_aurclk(.I(mgt_clk_ibuf),.O(aurora_clk_o));
        
    wire [NUM_MGT-1:0] bufg_gt_clr;
    wire pll_not_locked;
    wire user_clk;
    wire sync_clk;
    wire [NUM_MGT-1:0] tx_out_clk;
    wire [NUM_MGT-1:0] tx_lock;
    wire bufg_gt_clr_in = bufg_gt_clr[TX_CLOCK_SEL];
    // sync clock is user_clk, god knows why it exists
    turfio_aurora_clock u_clock( .gt_clk_i( tx_out_clk[TX_CLOCK_SEL] ),
                                 .gt_clk_locked_i( tx_lock[TX_CLOCK_SEL] ),
                                 .bufg_gt_clr_i( bufg_gt_clr_in),
                                 .user_clk_o(user_clk),
                                 .sync_clk_o(sync_clk),
                                 .pll_not_locked_o(pll_not_locked));
    wire system_reset;
    wire gt_reset;
    // these are both wb_clk_i-land
    reg reset_in = 1'b0;
    reg gt_reset_in = 1'b0;
    reg [NUM_MGT-1:0] linkerr_reset = 1'b0;
    reg global_linkerr_reset = 1'b0;
    reg [NUM_MGT-1:0] datapath_reset = 1'b0;
    reg global_datapath_reset = 1'b0;
    reg [NUM_MGT-1:0] eyescan_reset = {NUM_MGT{1'b0}};
    reg [NUM_MGT-1:0] gt_powerdown = {NUM_MGT{1'b0}};
    reg [2:0] gt_loopback[NUM_MGT-1:0];
    reg [3:0] txdiffctrl[NUM_MGT-1:0];
    reg [4:0] txprecursor[NUM_MGT-1:0];
    reg [4:0] txpostcursor[NUM_MGT-1:0];

    // Userclk cmd, before switch
    `DEFINE_AXI4S_MIN_IF( cmd_userclk_ , 32 );
    wire [1:0] cmd_userclk_tdest;
    wire       cmd_userclk_tlast;
    // generates tsize
    wire       cmd_userclk_tuser;

    // register for handling the logic of tsize
    reg        second_xfer = 0;        
    assign     cmd_userclk_tuser = cmd_userclk_tvalid && (cmd_userclk_tlast ^ !second_xfer);
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg        wb_user_areset = 0;
    (* CUSTOM_CC_DST = "USERCLK", ASYNC_REG = "TRUE" *)
    reg        [1:0] user_areset = 2'b00;;
    wire       user_aresetn = !user_areset[1];
    
    // second xfer logic
    always @(posedge user_clk) begin
        user_areset <= { user_areset[0], wb_user_areset };
        if (!user_aresetn) second_xfer <= 1'b0;
        else begin
            // tvalid && tready && !tlast
            if (cmd_userclk_tvalid && cmd_userclk_tready)
                second_xfer <= !cmd_userclk_tlast;
        end
    end
    
    // Transition the command requests over to user_clk domain
    // We do this before the switch to limit the number of FIFOs
    // needed.
    aurora_cmd_ccfifo u_cmdccfifo( .s_aclk(wb_clk_i),
                                   .m_aclk(user_clk),
                                   .s_aresetn(!wb_user_areset),
                                   `CONNECT_AXI4S_MIN_IF( s_axis_ , s_cmd_ ),
                                   .s_axis_tdest( s_cmd_tdest ),
                                   .s_axis_tlast( s_cmd_tlast ),
                                   `CONNECT_AXI4S_MIN_IF( m_axis_ , cmd_userclk_ ),
                                   .m_axis_tdest( cmd_userclk_tdest ),
                                   .m_axis_tlast( cmd_userclk_tlast ));    
    // NOTE: A normal switch won't work here, because UFC works differently (sigh).
    // So we need a custom process here.
    aurora_cmd_fwd_switch u_cmdswitch( .aclk(user_clk),
                                       .aresetn(user_aresetn),
                                       `CONNECT_AXI4S_MIN_IF( s_axis_ , cmd_userclk_ ),
                                       .s_axis_tdest( cmd_userclk_tdest ),
                                       .s_axis_tlast( cmd_userclk_tlast ),
                                       
                                       .m_axis_tdata( { ufc_tx_tdata[3], ufc_tx_tdata[2], ufc_tx_tdata[1], ufc_tx_tdata[0] } ),
                                       .m_axis_tvalid({ ufc_tx_tvalid[3],ufc_tx_tvalid[2],ufc_tx_tvalid[1],ufc_tx_tvalid[0]} ),
                                       .m_axis_tready({ ufc_tx_tready[3],ufc_tx_tready[2],ufc_tx_tready[1],ufc_tx_tready[0]} ),
                                       .cmd_tdata( { ufc_tx_aurora_data[3],
                                                     ufc_tx_aurora_data[2],
                                                     ufc_tx_aurora_data[1],
                                                     ufc_tx_aurora_data[0] } ));
    // UFC *receive* works correctly though, so a normal switch will work here
    aurora_resp_switch u_respswitch( .aclk(wb_clk_i),
                                     .aresetn(!wb_user_areset),
                                     .s_req_suppress(4'b0000),
                                     .s_axis_tdata( { ufc_rx_wbclk_tdata[3], ufc_rx_wbclk_tdata[2], ufc_rx_wbclk_tdata[1], ufc_rx_wbclk_tdata[0] } ),
                                     .s_axis_tvalid({ ufc_rx_wbclk_tvalid[3],ufc_rx_wbclk_tvalid[2],ufc_rx_wbclk_tvalid[1],ufc_rx_wbclk_tvalid[0]} ),
                                     .s_axis_tready({ ufc_rx_wbclk_tready[3],ufc_rx_wbclk_tready[2],ufc_rx_wbclk_tready[1],ufc_rx_wbclk_tready[0]} ),
                                     .s_axis_tlast( { ufc_rx_wbclk_tlast[3], ufc_rx_wbclk_tlast[2], ufc_rx_wbclk_tlast[1], ufc_rx_wbclk_tlast[0]}  ),
                                     .s_axis_tuser( { 2'b11,           2'b10,          2'b01,            2'b00 } ),
                                     `CONNECT_AXI4S_MIN_IF( m_axis_ , m_resp_ ),
                                     .m_axis_tlast( m_resp_tlast ),
                                     .m_axis_tuser( m_resp_tuser )
                                     );                             
                                       
    
//    // pop them through the switch.
//    // FIXME: use a real reset
//    aurora_cmd_switch u_cmdswitch( .aclk(user_clk),
//                                   .aresetn(user_aresetn),
//                                   `CONNECT_AXI4S_MIN_IF( s_axis_ , cmd_userclk_ ),
//                                   .s_axis_tdest( cmd_userclk_tdest ),
//                                   .s_axis_tlast( cmd_userclk_tlast ),
//                                   .s_axis_tuser( cmd_userclk_tuser ),
//                                   // have to do it manually
//                                   .m_axis_tdata( { ufc_tx_tdata[3], ufc_tx_tdata[2], ufc_tx_tdata[1], ufc_tx_tdata[0] }),
//                                   .m_axis_tvalid({ ufc_tx_tvalid[3],ufc_tx_tvalid[2],ufc_tx_tvalid[1],ufc_tx_tvalid[0]}),
//                                   .m_axis_tready({ ufc_tx_tready[3],ufc_tx_tready[2],ufc_tx_tready[1],ufc_tx_tready[0]}),
//                                   .m_axis_tuser( { ufc_tx_tuser[3], ufc_tx_tuser[2], ufc_tx_tuser[1], ufc_tx_tuser[0]}),
//                                   .m_axis_tlast( { ufc_tx_tlast[3], ufc_tx_tlast[2], ufc_tx_tlast[1], ufc_tx_tlast[0]}));

    // Resets are supposed to be:
    // At power on:
    // GT_RESET high, RESET high. GT_RESET goes low, RESET goes low sync to user_clk
    // At reset:
    // assert reset, 128 user-clks later assert gt_reset, wait 26-bit counter or 1 sec,
    // deassert gt_reset, deassert reset.
    // We handle that sequence in software so here it just looks like we can go nutso.
    turfio_aurora_reset_v2 u_reset( .reset_i(reset_in),
                                 .gt_reset_i(gt_reset_in),
                                 .user_clk_i(user_clk),
                                 .init_clk_i(wb_clk_i),
                                 .system_reset_o(system_reset),
                                 .gt_reset_o(gt_reset));
    // DRP interfaces
    `DEFINE_DRP_IFV( gt_ , 10, [NUM_MGT-1:0] );    
    // This is the general DRP access cycle.
    wire wb_drp_access;
    wire [1:0] wb_drp = (wb_adr_i[12 +: 2]); 
    wire       wb_gt_ctrl_en = !wb_adr_i[13];
    wire [1:0] wb_gt_ctrl_sel = (wb_adr_i[12:11]);
    wire [10:0] wb_gt_ctrl_adr = {wb_adr_i[10:2], 2'b00};
    wire [15:0] wb_drp_outdata = gt_drpdo[wb_drp];    
    generate
        genvar i;
        for (i=0;i<NUM_MGT;i=i+1) begin : ALN
            initial begin : INIT
                gt_loopback[i] <= 3'b000;
                txdiffctrl[i] <= 4'b1100;
                txprecursor[i] <= 5'h00;
                txpostcursor[i] <= 5'h00;
            end
        
            wire channel_up;
            wire lane_up;
            wire gt_powergood;
            wire tx_resetdone_out;
            wire rx_resetdone_out;
            wire sys_reset_out;
            wire link_reset_out;
            wire hard_err;
            wire soft_err;
            wire frame_err;
            wire [2:0] loopback;
            wire [15:0] dmonitor;
            (* CUSTOM_CC = "TO_USERCLK", ASYNC_REG = "TRUE" *)
            reg [1:0] powerdown = {2{1'b0}};            
            wire this_powerdown = powerdown[1];
            
            // Control register:
            // [0] = reset
            // [1] = gt_reset
            // [2] = eyescan_reset
            // [3] = powerdown
            // [6:4] = loopback
            // [7] = reserved
            // [8] = user_areset
            // [29:9] = reserved
            // [30] = datapath reset
            // [31] = link error reset
            
            // Cross loopback over to user-clock domain.
            async_register #(.WIDTH(3)) u_loopback_sync(.in_clkA(link_control[i][6:4]),
                                                   .clkA(wb_clk_i),
                                                   .out_clkB(loopback),
                                                   .clkB(user_clk));    
            always @(posedge user_clk) begin : PDS
                powerdown <= {powerdown[0],link_control[i][3]};
            end
            
            // LAAAAZY
            assign link_status[i][0] = lane_up;
            assign link_status[i][1] = channel_up;
            assign link_status[i][2] = gt_powergood;
            assign link_status[i][3] = tx_lock[i];
            assign link_status[i][4] = tx_resetdone_out;
            assign link_status[i][5] = rx_resetdone_out;
            assign link_status[i][6] = link_reset_out;
            assign link_status[i][7] = sys_reset_out;
            assign link_status[i][8] = hard_err;
            assign link_status[i][9] = soft_err;
            assign link_status[i][10] = frame_err;
            assign link_status[i][11] = bufg_gt_clr[i];
            assign link_status[i][31:12] = {20{1'b0}};
            // also laazy
            assign link_control[i][0] = reset_in;
            assign link_control[i][1] = gt_reset_in;
            assign link_control[i][2] = eyescan_reset[i];
            assign link_control[i][3] = gt_powerdown[i];
            assign link_control[i][4 +: 3] = gt_loopback[i];
            assign link_control[i][7] = 1'b0;
            assign link_control[i][8] = user_areset;
            assign link_control[i][9 +: 21] = {21{1'b0}};
            assign link_control[i][30] = datapath_reset[i];
            assign link_control[i][31] = linkerr_reset[i];
            
            assign link_eyescan[i][0 +: 4] = txdiffctrl[i];
            assign link_eyescan[i][4 +: 4] = {4{1'b0}};
            assign link_eyescan[i][8 +: 5] = txprecursor[i];
            assign link_eyescan[i][13 +: 3] = {3{1'b0}};
            assign link_eyescan[i][16 +: 5] = txpostcursor[i];
            assign link_eyescan[i][21 +: 3] = {3{1'b0}};
            assign link_eyescan[i][24 +: 8] = {8{1'b0}};
            
            assign link_dmonitor[i] = { {16{1'b0}}, dmonitor };
            // OK, handle per lane controls/eyescans here:
            always @(posedge wb_clk_i) begin : PLC
                if (wb_cyc_i && wb_stb_i && wb_ack_o && wb_we_i && wb_gt_ctrl_en && wb_gt_ctrl_sel == i) begin
                    if (wb_gt_ctrl_adr == 11'h000) begin
                        // control register
                        if (wb_sel_i[0]) begin
                            eyescan_reset[i] <= wb_dat_i[2];
                            gt_powerdown[i] <= wb_dat_i[3];
                            gt_loopback[i] <= wb_dat_i[4 +: 3];
                        end
                        if (wb_sel_i[3]) begin
                            datapath_reset[i] <= wb_dat_i[30];
                            linkerr_reset[i] <= wb_dat_i[31];
                        end
                    end
                    if (wb_gt_ctrl_adr == 11'h008) begin
                        if (wb_sel_i[0]) txdiffctrl[i] <= wb_dat_i[0 +: 4];
                        if (wb_sel_i[1]) txprecursor[i] <= wb_dat_i[8 +: 5];
                        if (wb_sel_i[2]) txpostcursor[i] <= wb_dat_i[16 +: 5];
                    end
                end
            end
                        
            
            // just kill the interfaces for now
            assign aurora_tx_tvalid[i] = 1'b0;            
            assign aurora_tx_tlast[i] = 1'b0;
            assign aurora_tx_tdata[i] = {32{1'b0}};            
            assign aurora_tx_tkeep[i] = 4'h0;
            
            // Create a multiplexed TX path.
            `DEFINE_AXI4S_IF( muxed_tx_ , 32 );
            // And hook up the UFC.
            `DEFINE_AXI4S_MIN_IF( muxed_ufc_ , 3);
            // Multiplex the data. Nothing else needs to be muxed.
            assign muxed_tx_tdata = (aurora_tx_tready[i]) ? aurora_tx_tdata[i] : ufc_tx_aurora_data[i];
            assign muxed_tx_tkeep = aurora_tx_tkeep[i];
            assign muxed_tx_tlast = aurora_tx_tlast[i];                        
            assign muxed_tx_tvalid = aurora_tx_tvalid[i];
            assign aurora_tx_tready[i] = muxed_tx_tready;
            
            // and hook up UFC
            assign muxed_ufc_tdata = ufc_tx_tdata[i][2:0];
            assign muxed_ufc_tvalid = ufc_tx_tvalid[i];
            assign ufc_tx_tready[i] = muxed_ufc_tready;
            
            // OK, hook up our DRP interface constants.
            assign gt_drpaddr[i][9:0] = wb_adr_i[2 +: 10];
            assign gt_drpdi[i] = wb_dat_i[15:0];
            assign gt_drpwe[i] = wb_we_i;
            assign gt_drpen[i] = wb_drp_access && (wb_drp == i);
            
            if (USE_DEBUG[i]) begin : DBG
                aurora_tx_ila u_ila(.clk(user_clk),
                                    .probe0( muxed_tx_tdata ),
                                    .probe1( muxed_tx_tkeep ),
                                    .probe2( muxed_tx_tvalid ),
                                    .probe3( muxed_tx_tready ),
                                    .probe4( muxed_tx_tlast ),
                                    .probe5( muxed_ufc_tdata ),
                                    .probe6( muxed_ufc_tvalid ),
                                    .probe7( muxed_ufc_tready ));
            end

            // response data crossing
            aurora_resp_ccfifo u_respfifo( .s_axis_aclk( user_clk ),
                                           .m_axis_aclk( wb_clk_i ),
                                           .s_axis_aresetn( user_aresetn ),
                                           `CONNECT_AXI4S_MIN_IFV( s_axis_ , ufc_rx_ , [i] ),
                                           .s_axis_tlast( ufc_rx_tlast[i] ),
                                           `CONNECT_AXI4S_MIN_IFV( m_axis_ , ufc_rx_wbclk_ , [i] ),
                                           .m_axis_tlast( ufc_rx_wbclk_tlast[i] ));
            
            turfio_aurora u_aurora( `CONNECT_AXI4S_IF( s_axi_tx_ , muxed_tx_ ),
                                    `CONNECT_AXI4S_MIN_IF( s_axi_ufc_tx_ , muxed_ufc_ ),
                                    // Can't use the connect helpers because Aurora doesn't have tready
                                    .m_axi_rx_tdata( aurora_rx_tdata[i] ),
                                    .m_axi_rx_tkeep( aurora_rx_tkeep[i] ),
                                    .m_axi_rx_tlast( aurora_rx_tlast[i] ),
                                    .m_axi_rx_tvalid(aurora_rx_tvalid[i]),
                                    .m_axi_ufc_rx_tdata( ufc_rx_tdata[i]),
                                    .m_axi_ufc_rx_tlast( ufc_rx_tlast[i]),
                                    .m_axi_ufc_rx_tvalid(ufc_rx_tvalid[i]),
                                    
                                    // No DRP for now. Later we'll add it in the monitoring loop.
                                    `CONNECT_DRP_IFV( gt0_ , gt_ , [i]),
                                    .loopback(loopback),
                                    .pll_not_locked(pll_not_locked),
                                    .power_down(this_powerdown),
                                    .reset( system_reset ),
                                    .gt_reset( gt_reset ),
                                    .init_clk_in( wb_clk_i ),
                                    .user_clk(user_clk),
                                    .sync_clk(sync_clk),
                                    .gt_refclk1(mgt_clk),
                                    
                                    .bufg_gt_clr_out( bufg_gt_clr[i]),
                                    .channel_up(channel_up),
                                    .lane_up(lane_up),
                                    .hard_err(hard_err),
                                    .soft_err(soft_err),
                                    .frame_err(frame_err),
                                    .tx_resetdone_out(tx_resetdone_out),
                                    .rx_resetdone_out(rx_resetdone_out),
                                    .tx_lock(tx_lock[i]),
                                    .link_reset_out(link_reset_out),
                                    .sys_reset_out(sys_reset_out),
                                    .gt_powergood(gt_powergood),
                                    .tx_out_clk(tx_out_clk[i]),
                                    
                                    `UNUSED_GTH_DEBUG_AURORA_PORTS,
                                     .gt_eyescanreset(link_control[i][2]),
                                    // use RXOUT_DIV
                                    .gt_rxrate(3'b000),
                                    // this should default to 1100 (bit 0 tacked on)
                                    .gt_txdiffctrl({link_eyescan[i][0 +: 4], 1'b0}),
                                    // this shold default to 0
                                    .gt_txprecursor(link_eyescan[i][8 +: 5]),
                                    // also default to 0
                                    .gt_txpostcursor(link_eyescan[i][16 +: 5]),
                                    .gt_rxlpmen(1'b1),
                                    
                                    .gt_dmonitorout(dmonitor),
                                    
                                    .txp(MGTTX_P[i]),
                                    .txn(MGTTX_N[i]),
                                    .rxp(MGTRX_P[i]),
                                    .rxn(MGTRX_N[i]));
            
        end
    endgenerate 

    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] ACK = 1;
    localparam [FSM_BITS-1:0] DRP_WAIT = 2;
    reg [FSM_BITS-1:0] state = IDLE;
    
    assign wb_drp_access = (state == IDLE && wb_cyc_i && wb_stb_i && wb_adr_i[14]);

    // individual controlstat registers. Only 4 right now. Expand only to powers of 2.
    wire [31:0] ind_ctrlstat[3:0];
    assign ind_ctrlstat[0] = link_control[wb_gt_ctrl_sel];
    assign ind_ctrlstat[1] = link_status[wb_gt_ctrl_sel];
    assign ind_ctrlstat[2] = link_eyescan[wb_gt_ctrl_sel];
    assign ind_ctrlstat[3] = link_dmonitor[wb_gt_ctrl_sel];
    
    // only one right now
    wire [31:0] glob_ctrlstat;
    assign glob_ctrlstat = { global_linkerr_reset, global_datapath_reset,
                             {21{1'b0}},
                             user_areset,
                             {6{1'b0}},
                             gt_reset_in , reset_in };
    
    reg [31:0] dat_out = {32{1'b0}};
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) state <= IDLE;
        else begin
            case (state)
                IDLE: if (wb_cyc_i && wb_stb_i) begin
                    if (wb_adr_i[14]) state <= DRP_WAIT;
                    else state <= ACK;
                end
                ACK: state <= IDLE;
                DRP_WAIT: if (gt_drprdy[wb_drp]) state <= ACK;
            endcase
        end
        
        if (wb_cyc_i && wb_stb_i && wb_we_i && wb_ack_o) begin
            if (!wb_adr_i[14] && !wb_gt_ctrl_en && wb_gt_ctrl_adr == 11'h000) begin
                if (wb_sel_i[0]) begin
                    reset_in <= wb_dat_i[0];
                    gt_reset_in <= wb_dat_i[1];
                end
                if (wb_sel_i[1]) begin
                    wb_user_areset <= wb_dat_i[8];
                end                    
                if (wb_sel_i[3]) begin
                    global_linkerr_reset <= wb_dat_i[31];
                    global_datapath_reset <= wb_dat_i[30];
                end
            end
        end
        
        if (wb_cyc_i && wb_stb_i && !wb_we_i) begin
            if (state == IDLE) begin
                if (!wb_gt_ctrl_en) dat_out <= glob_ctrlstat;
                else dat_out <= ind_ctrlstat[wb_adr_i[3:2]];
            end else if (state == DRP_WAIT && gt_drprdy[wb_drp]) begin
                dat_out <= { {16{1'b0}}, wb_drp_outdata };
            end
        end        
     end
    
    assign wb_ack_o = (state == ACK);
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    assign wb_dat_o = dat_out;    

    assign aurora_up_o[3] = link_status[3][0] && link_status[3][1];
    assign aurora_up_o[2] = link_status[2][0] && link_status[2][1];
    assign aurora_up_o[1] = link_status[1][0] && link_status[1][1];
    assign aurora_up_o[0] = link_status[0][0] && link_status[0][1];
                            
//    (* ASYNC_REG = "TRUE" *)
//    reg [15:0] vio_status_0 = {16{1'b0}};
//    (* ASYNC_REG = "TRUE" *)
//    reg [15:0] vio_status_1 = {16{1'b0}};
//    always @(posedge init_clk) begin
//        vio_status_0 <= gt_status[0];
//        vio_status_1 <= vio_status_0;
//    end
     
//    aurora_mgt_vio u_vio(.clk(init_clk),
//                         .probe_out0( reset_in ),
//                         .probe_out1( gt_reset_in ),
//                         .probe_out2( loopback_init_clk[0] ),
//                         .probe_out3( loopback_init_clk[1] ),
//                         .probe_out4( loopback_init_clk[2] ),
//                         .probe_out5( loopback_init_clk[3] ),
//                         .probe_in0(vio_status_1));            
endmodule

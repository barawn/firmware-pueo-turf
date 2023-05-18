`timescale 1ns / 1ps
`include "interfaces.vh"
`include "mgt.vh"
// Wrap the entire TURFIO aurora interface.
// No actual interface for now!
module turfio_aurora_wrap
    #(  parameter TX_CLOCK_SEL = 0,
        parameter NUM_MGT = 4 )
    (
        input init_clk,
    
        input MGTCLK_P,
        input MGTCLK_N,
        
        input [NUM_MGT-1:0] MGTRX_P,
        input [NUM_MGT-1:0] MGTRX_N,
        output [NUM_MGT-1:0] MGTTX_P,
        output [NUM_MGT-1:0] MGTTX_N                
    );
    // create the interfaces. 
    `DEFINE_AXI4S_IFV( aurora_tx_ , 16, [NUM_MGT-1:0] );
    `DEFINE_AXI4S_IFV( aurora_rx_ , 16, [NUM_MGT-1:0] );

    // The UFC interfaces are actually multiplexed onto the direct ones.
    // The additional 3-bit interface specifies the size of the UFC message.
    `DEFINE_AXI4S_IFV( ufc_tx_ , 16, [NUM_MGT-1:0] );
    wire [2:0] ufc_tx_tsize[NUM_MGT-1:0];
    `DEFINE_AXI4S_IFV( ufc_rx_ , 16, [NUM_MGT-1:0] );
    
    // MGT clock input buffer. Note that this is *inverted*, although
    // it doesn't matter: the MGT interface is treated as asynchronous to system clock.
    wire mgt_clk_ibuf;
    wire mgt_clk_bufg;
    wire mgt_clk;
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00))
        u_mgt_ibuf(.I(MGTCLK_N),.IB(MGTCLK_P),.CEB(1'b0),.O(mgt_clk), .ODIV2(mgt_clk_ibuf));
        
    wire [NUM_MGT-1:0] bufg_gt_clr;
    wire pll_not_locked;
    wire user_clk;
    wire sync_clk;
    wire [NUM_MGT-1:0] tx_out_clk;
    wire [NUM_MGT-1:0] tx_lock;
    wire bufg_gt_clr_in = bufg_gt_clr[TX_CLOCK_SEL];

    turfio_aurora_clock u_clock( .gt_clk_i( tx_out_clk[TX_CLOCK_SEL] ),
                                 .gt_clk_locked_i( tx_lock[TX_CLOCK_SEL] ),
                                 .bufg_gt_clr_i( bufg_gt_clr_in),
                                 .user_clk_o(user_clk),
                                 .sync_clk_o(sync_clk),
                                 .pll_not_locked_o(pll_not_locked));
    wire system_reset;
    wire gt_reset;
    wire reset_in;      // needs to be synced to user_clk
    wire gt_reset_in;   // needs to be synced to init_clk
    wire [2:0] loopback_init_clk;
    wire [2:0] loopback_user_clk;
    async_register #(.WIDTH(3)) u_loopback_sync(.in_clkA(loopback_init_clk),
                                           .clkA(init_clk),
                                           .out_clkB(loopback_user_clk),
                                           .clkB(user_clk));    
    // we need a way to ignore paths to this specific guy
    (* ASYNC_REG = "TRUE" *)
    (* CUST_ASYNC_INPUT = "TRUE" *)
    reg reset_in_resync0 = 0;
    (* ASYNC_REG = "TRUE" *)
    reg reset_in_resync1 = 0;

    always @(posedge user_clk) begin
        reset_in_resync0 <= reset_in;
        reset_in_resync1 <= reset_in_resync0;
    end 
    
    turfio_aurora_reset u_reset( .reset_i(reset_in_resync1),
                                 .gt_reset_i(gt_reset_in),
                                 .user_clk_i(user_clk),
                                 .init_clk_i(init_clk),
                                 .system_reset_o(system_reset),
                                 .gt_reset_o(gt_reset));
    // DRP interfaces and IBERT controls
    `DEFINE_DRP_IFV( gt_ , 10, [NUM_MGT-1:0] );
    wire [NUM_MGT-1:0] gt_eyescanreset;
    wire [3*NUM_MGT-1:0] gt_rxrate;
    wire [5*NUM_MGT-1:0] gt_txdiffctrl;
    wire [5*NUM_MGT-1:0] gt_txprecursor;
    wire [5*NUM_MGT-1:0] gt_txpostcursor;
    wire [NUM_MGT-1:0] gt_rxlpmen;
    // IBERT
    turfio_ibert u_ibert( .clk(init_clk),
                          .rxoutclk_i( {4{user_clk}} ),
                          `CONNECT_IBERT_DRP_IFV( gt0_ , gt_ , [0] ),
                          `CONNECT_IBERT_DRP_IFV( gt1_ , gt_ , [1] ),
                          `CONNECT_IBERT_DRP_IFV( gt2_ , gt_ , [2] ),
                          `CONNECT_IBERT_DRP_IFV( gt3_ , gt_ , [3] ),
                          .eyescanreset_o( gt_eyescanreset ),
                          .rxrate_o( gt_rxrate ),
                          .txdiffctrl_o( gt_txdiffctrl ),
                          .txprecursor_o( gt_txprecursor ),
                          .txpostcursor_o( gt_txpostcursor ),
                          .rxlpmen_o( gt_rxlpmen ) );
    
    // Status crap. There are lots of status bits in a transceiver, so we collect them all here.
    wire [15:0] gt_status[NUM_MGT-1:0];
    generate
        genvar i;
        for (i=0;i<NUM_MGT;i=i+1) begin : ALN
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
            
            // LAAAAZY
            assign gt_status[i][0] = lane_up;
            assign gt_status[i][1] = channel_up;
            assign gt_status[i][2] = gt_powergood;
            assign gt_status[i][3] = tx_lock[i];
            // this is loopback
            assign gt_status[i][6:4] = 3'b000;
            // powerdown
            assign gt_status[i][7] = 1'b0;
            assign gt_status[i][8] = tx_resetdone_out;
            assign gt_status[i][9] = rx_resetdone_out;
            assign gt_status[i][10] = link_reset_out;
            assign gt_status[i][11] = sys_reset_out;
            assign gt_status[i][12] = hard_err;
            assign gt_status[i][13] = soft_err;
            assign gt_status[i][14] = frame_err;
            assign gt_status[i][15] = 1'b0;
            // just kill the interfaces for now
            assign aurora_tx_tvalid[i] = 1'b0;            
            assign aurora_tx_tlast[i] = 1'b0;
            assign aurora_tx_tdata[i] = {16{1'b0}};            
            assign ufc_tx_tvalid[i] = 1'b0;
            assign ufc_tx_tdata[i] = {16{1'b0}};
            assign ufc_tx_tsize[i] = {3{1'b0}};
            assign ufc_tx_tlast[i] = 1'b0;
            
            // Create a multiplexed TX path..
            `DEFINE_AXI4S_IF( muxed_tx_ , 16 );
            // And a fakey path for UFC
            `DEFINE_AXI4S_MIN_IF( muxed_ufc_ , 3);
            
            // Multiplex the path.
            assign muxed_tx_tvalid = aurora_tx_tvalid[i];            
            assign aurora_tx_tready[i] = muxed_tx_tready;
            assign muxed_tx_tdata = (aurora_tx_tready[i]) ? aurora_tx_tdata[i] : ufc_tx_tdata[i];
            assign muxed_tx_tkeep = (aurora_tx_tready[i]) ? aurora_tx_tkeep[i] : ufc_tx_tkeep[i];
            assign muxed_tx_tlast = (aurora_tx_tlast[i]) ? aurora_tx_tlast[i] : ufc_tx_tlast[i];
            // and create the fakey path
            assign muxed_ufc_tdata = ufc_tx_tsize[i];
            assign muxed_ufc_tvalid = ufc_tx_tvalid[i];
            assign ufc_tx_tready[i] = muxed_ufc_tready;
            
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
                                    .loopback(loopback_user_clk),
                                    .pll_not_locked(pll_not_locked),
                                    .power_down(1'b0),
                                    .reset( system_reset ),
                                    .gt_reset( gt_reset ),
                                    .init_clk_in( init_clk ),
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
                                    
                                    .gt_eyescanreset( gt_eyescanreset[i] ),
                                    .gt_rxrate( gt_rxrate[3*i +: 3] ),
                                    .gt_txdiffctrl( gt_txdiffctrl[5*i +: 5] ),
                                    .gt_txprecursor( gt_txprecursor[5*i +: 5] ),
                                    .gt_txpostcursor( gt_txpostcursor[5*i +: 5] ),
                                    .gt_rxlpmen( gt_rxlpmen[i] ),
                                    
                                    .txp(MGTTX_P[i]),
                                    .txn(MGTTX_N[i]),
                                    .rxp(MGTRX_P[i]),
                                    .rxn(MGTRX_N[i]));
            
        end
    endgenerate 
                            
    (* ASYNC_REG = "TRUE" *)
    reg [15:0] vio_status_0 = {16{1'b0}};
    (* ASYNC_REG = "TRUE" *)
    reg [15:0] vio_status_1 = {16{1'b0}};
    always @(posedge init_clk) begin
        vio_status_0 <= gt_status[0];
        vio_status_1 <= vio_status_0;
    end
     
    aurora_mgt_vio u_vio(.clk(init_clk),
                         .probe_out0( reset_in ),
                         .probe_out1( gt_reset_in ),
                         .probe_out2( loopback_init_clk ),
                         .probe_in0(vio_status_1));            
endmodule

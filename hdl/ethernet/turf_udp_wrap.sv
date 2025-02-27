`timescale 1ns / 1ps
`include "interfaces.vh"

// This module wraps up the various SFP and UDP related stuff.
// 
module turf_udp_wrap #( parameter NSFP=2,
                        parameter DEBUG_IN="TRUE",
                        parameter DEBUG_OUT="TRUE",
                        parameter DEBUG_ACKNACK="TRUE",
                        parameter DEBUG_EVENT_VIO="TRUE",
                        parameter WBCLKTYPE = "NONE",
                        parameter ETHCLKTYPE = "ETHCLK"
        )(
        output [2*NSFP-1:0] sfp_led,
        output [NSFP-1:0] sfp_tx_p,
        output [NSFP-1:0] sfp_tx_n,
        input [NSFP-1:0] sfp_rx_p,
        input [NSFP-1:0] sfp_rx_n,
        input sfp_refclk_p,
        input sfp_refclk_n,
        output [NSFP-1:0] sfp_tx_disable,
        input [NSFP-1:0] sfp_npres,
        input [NSFP-1:0] sfp_los,
        output [NSFP-1:0] sfp_rs,
        
        // THESE STREAMS ARE ALL ETHCLK
        output aclk,
        // acking path
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_ack_ , 16),
        // nacking path
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_nack_ , 16),
        // event open interface
        output event_open_o,        
        // event control input
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_ev_ctrl_ , 32),
        // event data input
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_ev_data_ , 64),            
        input [7:0] s_ev_data_tkeep,
        input s_ev_data_tlast,

        // WB CLK SIDE
        input wb_clk_i,
        // this is the DRP side interface + maybe more? who knows??
        // put the whole effing thing in reset???
        `TARGET_NAMED_PORTS_WB_IF( gtp_ , 13, 32 ),        
        // this is the master interface        
        `HOST_NAMED_PORTS_WB_IF( wb_ , 28, 32 )
    );


    localparam COMMON_SFP=0;
    
    wire sfp_mgt_refclk;
    // 161.1328125
    wire sfp_refclk;    
    wire sfp_gtpowergood;
    wire sfp_qpll0lock;
    wire sfp_qpll0outclk;
    wire sfp_qpll0outrefclk;
        
    wire [NSFP-1:0] sfp_tx_clk;
    wire [NSFP-1:0] sfp_tx_rst;
    wire [63:0]     sfp_txd[NSFP-1:0];
    wire [7:0]      sfp_txc[NSFP-1:0];
    wire [NSFP-1:0] sfp_rx_clk;
    wire [NSFP-1:0] sfp_rx_rst;
    wire [63:0]     sfp_rxd[NSFP-1:0];
    wire [7:0]      sfp_rxc[NSFP-1:0];    
    wire [NSFP-1:0] sfp_rx_block_lock;

    wire clk156 = sfp_tx_clk[0];
    wire clk156_rst = sfp_tx_rst[0];    

    wire refclk_int;
    // the defaults here are all 0, which implies ODIV2 is actually just O = 161 MHz
    IBUFDS_GTE4 ibufds_refclk(.I(sfp_refclk_p),.IB(sfp_refclk_n),
                              .CEB(1'b0),
                              .O(sfp_mgt_refclk),
                              .ODIV2(refclk_int));
    BUFG_GT bufg_gt_refclk(.I(refclk_int),.O(sfp_refclk),
                           .CE(sfp_gtpowergood),
                           .CEMASK(1'b1),
                           .CLR(1'b0),
                           .CLRMASK(1'b1),
                           .DIV(3'b000));

    // The original turf_udp_wrap from exanic_turf_test
    // needed a 125 MHz clock here for... reasons, I guess
    // we don't: the DRP clock and freerunning clock
    // is just the PS clock.
    wire xcvr_ctrl_clk = wb_clk_i;

    wire [1:0] drpen;
    wire drpwe;
    wire [9:0] drpaddr;
    wire [15:0] drpdi;
    wire [31:0] drpdo;
    wire [1:0] drprdy;
                                        
    wb_to_drpx2 u_wbtodrp(.wb_clk_i(wb_clk_i),
                          `CONNECT_WBS_IFS(wb_ , gtp_ ),
                          .drpen(drpen),
                          .drpwe(drpwe),
                          .drpaddr(drpaddr),
                          .drprdy(drprdy),
                          .drpdo(drpdo),
                          .drpdi(drpdi));
    generate
        genvar i;
        for (i=0;i<NSFP;i=i+1) begin : SFP        
            wire powergood;
            wire qpll0lock;
            wire qpll0outclk;
            wire qpll0outrefclk;
            
            wire qpll0lock_in;
            wire qpll0outclk_in;
            wire qpll0outrefclk_in;
                        
            if (i==COMMON_SFP) begin : HEAD
                assign sfp_gtpowergood = powergood;
                assign sfp_qpll0lock = qpll0lock;
                assign sfp_qpll0outclk = qpll0outclk;
                assign sfp_qpll0outrefclk = qpll0outrefclk;
            end else begin : BODY
                assign qpll0lock_in = sfp_qpll0lock;
                assign qpll0outclk_in = sfp_qpll0outclk;
                assign qpll0outrefclk_in = sfp_qpll0outrefclk;
            end
            // COUNT_125US is number of 156 MHz clock cycles in
            // 125 us. Needs to be an integer because more recent
            // versions of Vivado bitch about it.
            eth_xcvr_phy_wrapper #(.HAS_COMMON(i==0?1:0),
                                   .COUNT_125US(19531))
                u_phy( .xcvr_ctrl_clk( xcvr_ctrl_clk ),
                       .xcvr_ctrl_rst( 1'b0 ),
                       .xcvr_gtpowergood_out(powergood),
                       .xcvr_gtrefclk00_in(sfp_mgt_refclk),
                       .xcvr_qpll0lock_out(qpll0lock),
                       .xcvr_qpll0outclk_out(sfp_qpll0outclk),
                       .xcvr_qpll0outrefclk_out(sfp_qpll0outrefclk),
                       
                       .xcvr_qpll0lock_in(qpll0lock_in),
                       .xcvr_qpll0reset_out(),
                       .xcvr_qpll0clk_in(qpll0outclk_in),
                       .xcvr_qpll0refclk_in(qpll0outrefclk_in),
                       
                       .xcvr_txp(sfp_tx_p[i]),
                       .xcvr_txn(sfp_tx_n[i]),
                       .xcvr_rxp(sfp_rx_p[i]),
                       .xcvr_rxn(sfp_rx_n[i]),
                       
                       .drpclk_in(wb_clk_i),
                       .drpen_in(drpen[i]),
                       .drpwe_in(drpwe),
                       .drpaddr_in(drpaddr),
                       .drpdi_in(drpdi),
                       .drpdo_out(drpdo[16*i +: 16]),
                       .drprdy_out(drprdy[i]),
                       
                       .phy_tx_clk(sfp_tx_clk[i]),
                       .phy_tx_rst(sfp_tx_rst[i]),
                       .phy_xgmii_txd(sfp_txd[i]),
                       .phy_xgmii_txc(sfp_txc[i]),
                       .phy_rx_clk(sfp_rx_clk[i]),
                       .phy_rx_rst(sfp_rx_rst[i]),
                       .phy_xgmii_rxd(sfp_rxd[i]),
                       .phy_xgmii_rxc(sfp_rxc[i]),
                       .phy_rx_block_lock(sfp_rx_block_lock[i]));
           assign sfp_led[2*i + 0] = sfp_rx_block_lock[i];
           assign sfp_tx_disable[i] = 1'b0;
           assign sfp_rs[i] = 1'b1;
        end        
    endgenerate

    // kill the unused. well, make it go idle I guess
    assign sfp_txd[1] = 64'h0707070707070707;
    assign sfp_txc[1] = 8'hff;
    
    // the header path is always 64 bits
    localparam PAYLOAD_WIDTH=64;

    // OK, now the UDP stuff. See how much more compact this is...?
    `DEFINE_AXI4S_MIN_IF( udpin_hdr_ , 64);
    wire [15:0] udpin_hdr_tdest;
    `DEFINE_AXI4S_IF( udpin_data_ , PAYLOAD_WIDTH);
    
    `DEFINE_AXI4S_MIN_IF( udpout_hdr_ , 64);
    wire [15:0] udpout_hdr_tuser;
    `DEFINE_AXI4S_IF( udpout_data_ , PAYLOAD_WIDTH);       
    
    // Its clock is clk156, its reset is clk156_rst.
    wire [47:0] my_mac_address;
    turf_udp_core u_udp_core( .clk(clk156), .rst(clk156_rst),
        .sfp_tx_clk(sfp_tx_clk[0]),
        .sfp_tx_rst(sfp_tx_rst[0]),
        .sfp_txd(sfp_txd[0]),
        .sfp_txc(sfp_txc[0]),
        .sfp_rx_clk(sfp_rx_clk[0]),
        .sfp_rx_rst(sfp_rx_rst[0]),
        .sfp_rxd(sfp_rxd[0]),
        .sfp_rxc(sfp_rxc[0]),
        .my_mac_address(my_mac_address),
        `CONNECT_AXI4S_MIN_IF( m_udphdr_ , udpin_hdr_ ),
        .m_udphdr_tdest( udpin_hdr_tdest ),
        `CONNECT_AXI4S_IF( m_udpdata_ , udpin_data_ ),
        
        `CONNECT_AXI4S_MIN_IF( s_udphdr_ , udpout_hdr_ ),
        .s_udphdr_tuser( udpout_hdr_tuser ),
        `CONNECT_AXI4S_IF( s_udpdata_ , udpout_data_ ));

    // OK! Now we can hook up the UDP port switch, the RDWR/ack/nack/control core and finally the fragment generator.
    // Our inbound ports are
    // 'Tr', 'Tw', 'Ta', 'Tn', 'Tc'
    // 21601 ('Ta') - port 4 - 0x5461 0110 0001
    // 21603 ('Tc') - port 3 - 0x5463 0110 0011
    // 21614 ('Tn') - port 2 - 0x546E 0110 1110
    // 21618 ('Tr') - port 1 - 0x5472 0111 0010
    // 21623 ('Tw') - port 0 - 0x5477 0111 0111
    // We combine the last two by just looking for 0x547(0-7)        

    localparam NUM_INBOUND = 4;
    localparam [NUM_INBOUND*16-1:0]
        INBOUND = { 16'd21601,      // 3
                    16'd21603,      // 2
                    16'd21614,      // 1
                    16'd21618 };    // 0
                 // 16'd21623   is covered in the last match
    localparam [NUM_INBOUND*16-1:0]
        INBOUND_MASK = { 16'd0,                     // exact match
                         16'd0,                     // exact match
                         16'd0,                     // exact match
                         16'b0000_0000_0000_0111 }; // match 21616-21623
    localparam TA_PORT = 3;
    localparam TC_PORT = 2;
    localparam TN_PORT = 1;
    localparam TRW_PORT = 0;
        
    wire [NUM_INBOUND*64-1:0] hdr_tdata;
    wire [NUM_INBOUND-1:0]    hdr_tvalid;
    wire [NUM_INBOUND-1:0]    hdr_tready;
    wire [NUM_INBOUND*16-1:0] hdr_tdest;
        
    wire [NUM_INBOUND*PAYLOAD_WIDTH-1:0] data_tdata;
    wire [NUM_INBOUND-1:0] data_tvalid;
    wire [NUM_INBOUND-1:0] data_tready;
    wire [NUM_INBOUND*(PAYLOAD_WIDTH/8)-1:0] data_tkeep;
    wire [NUM_INBOUND-1:0] data_tlast;
    
    wire [NUM_INBOUND-1:0] in_port_active;
    
    localparam NUM_OUTBOUND = 5;
    localparam T0_PORT = 4;
    // we don't actually have to *specify* the outbound port values, but we do
    localparam [NUM_OUTBOUND*16-1:0]
        OUTBOUND = { 16'd21552, // T0 port
                     INBOUND };
    localparam TW_PORT_VALUE = 16'd21623;        

    // Event related stuff
    wire [9:0]  num_fragment_qwords;
    wire [15:0] fragsrc_mask;
    wire [31:0] event_ip;
    wire [15:0] event_port;
    wire        event_is_open;    
    assign event_open_o = event_is_open;
        
    wire [NUM_OUTBOUND*64-1:0] hdrout_tdata;
    wire [NUM_OUTBOUND-1:0]    hdrout_tvalid;
    wire [NUM_OUTBOUND-1:0]    hdrout_tready;
    wire [NUM_OUTBOUND*16-1:0]    hdrout_tuser;

    wire [NUM_OUTBOUND*PAYLOAD_WIDTH-1:0]   dataout_tdata;
    wire [NUM_OUTBOUND-1:0]                 dataout_tvalid;
    wire [NUM_OUTBOUND-1:0]                 dataout_tready;
    wire [NUM_OUTBOUND*(PAYLOAD_WIDTH/8)-1:0] dataout_tkeep;
    wire [NUM_OUTBOUND-1:0]                 dataout_tlast;        
    
    udp_port_switch #(.NUM_PORT(NUM_INBOUND),
                      .PORTS( INBOUND ),
                      .PORT_MASK( INBOUND_MASK ),
                      .PAYLOAD_WIDTH(PAYLOAD_WIDTH))
              u_udpin_switch( .aclk(clk156), .aresetn(!clk156_rst),
                              `CONNECT_AXI4S_MIN_IF( s_udphdr_ , udpin_hdr_ ),
                              .s_udphdr_tdest(udpin_hdr_tdest),
                              `CONNECT_AXI4S_IF( s_udpdata_ , udpin_data_ ),
                              
                              .m_udphdr_tdata( hdr_tdata ),
                              .m_udphdr_tvalid(hdr_tvalid),
                              .m_udphdr_tready(hdr_tready),
                              .m_udphdr_tdest( hdr_tdest),
                              
                              .m_udpdata_tdata( data_tdata ),
                              .m_udpdata_tvalid(data_tvalid),
                              .m_udpdata_tready(data_tready),
                              .m_udpdata_tkeep( data_tkeep),
                              .m_udpdata_tlast( data_tlast),
                              
                              .port_active(in_port_active));

    // kill non-implemented ports
    `define KILL_UDP_IN(idx) \
        assign hdr_tready[ idx ] = 1'b1; \
        assign data_tready[ idx ] = 1'b1

    `define KILL_UDP_OUT(idx) \
        assign hdrout_tvalid[ idx ] = 1'b0;                                                           \
        assign hdrout_tdata[64* idx  +: 64] = {64{1'b0}};                                             \
        assign hdrout_tuser[16* idx  +: 16] = OUTBOUND[16* idx  +: 16];                             \
        assign dataout_tvalid[ idx ] = 1'b0;                                                          \
        assign dataout_tdata[PAYLOAD_WIDTH* idx  +: PAYLOAD_WIDTH] = {PAYLOAD_WIDTH{1'b0}};           \
        assign dataout_tkeep[(PAYLOAD_WIDTH/8)* idx  +: (PAYLOAD_WIDTH/8)] = {(PAYLOAD_WIDTH/8){1'b0}};   \
        assign dataout_tlast[ idx ] = 1'b0

    // eff it, just macro things
    `define CONNECT_UDP_IN( inhdr, indata, port )                             \
        .``inhdr``tdata( hdr_tdata[(64 * port ) +: 64] ),   \
        .``inhdr``tvalid( hdr_tvalid[ port ] ),             \
        .``inhdr``tready( hdr_tready[ port ] ),             \
        .``indata``tdata( data_tdata[(PAYLOAD_WIDTH * port ) +: PAYLOAD_WIDTH] ), \
        .``indata``tkeep( data_tkeep[((PAYLOAD_WIDTH/8) * port ) +: (PAYLOAD_WIDTH/8)] ),   \
        .``indata``tready( data_tready[ port ] ),   \
        .``indata``tvalid( data_tvalid[ port ] ),   \
        .``indata``tlast(  data_tlast[ port ] )
        
    `define CONNECT_UDP_OUT( outhdr, outdata, port )                            \
        .``outhdr``tdata( hdrout_tdata[(64 * port ) +: 64] ),   \
        .``outhdr``tvalid( hdrout_tvalid[ port ] ),             \
        .``outhdr``tready( hdrout_tready[ port ] ),             \
        .``outdata``tdata( dataout_tdata[(PAYLOAD_WIDTH * port ) +: PAYLOAD_WIDTH] ), \
        .``outdata``tkeep( dataout_tkeep[((PAYLOAD_WIDTH/8) * port ) +: (PAYLOAD_WIDTH/8)] ),   \
        .``outdata``tready( dataout_tready[ port ] ),   \
        .``outdata``tvalid( dataout_tvalid[ port ] ),   \
        .``outdata``tlast(  dataout_tlast[ port ] )
            
    `define CONNECT_UDP_INOUT( inhdr, indata, outhdr, outdata, port)        \
        `CONNECT_UDP_IN( inhdr, indata, port ),                             \
        `CONNECT_UDP_OUT( outhdr, outdata, port)        
        
    
    wire en;
    wire wr;
    wire [27:0] adr;
    wire [31:0] dat_out;
    wire [31:0] dat_in;
    wire ack;                        
            
    // now try the UDP RDWR core
    wire rdwr_tuser = (hdr_tdest[16*TRW_PORT +: 16] == INBOUND[TRW_PORT*16 +: 16]);
    wire rdwrout_tuser;
    assign hdrout_tuser[16*TRW_PORT +: 16] = (rdwrout_tuser) ? OUTBOUND[TRW_PORT*16 +: 16] : TW_PORT_VALUE;
    turf_udp_rdwr_v2 #(.ACLKTYPE(ETHCLKTYPE),
                       .WBCLKTYPE(WBCLKTYPE))
                     u_rdwr( .aclk(clk156),.aresetn(!clk156_rst),
                            `CONNECT_UDP_INOUT( s_hdr_ , s_payload_ , m_hdr_ , m_payload_ , TRW_PORT ),
                            .s_hdr_tuser( rdwr_tuser ),
                            .m_hdr_tuser( rdwrout_tuser ),                          
                            // and the interface. this is a WBM/IFM
                            .wb_clk_i(wb_clk_i),
                            `CONNECT_WBM_IFM( wb_ , wb_ ));
                            
    // Control port module always responds at its own port
    assign hdrout_tuser[16*TC_PORT +: 16] = OUTBOUND[16*TC_PORT +: 16];
    turf_event_ctrl_port #(.MAX_FRAGMENT_LEN(8095),.MAX_ADDR(4095))
        u_ctrlport( .aclk(clk156),.aresetn(!clk156_rst),
                    `CONNECT_UDP_INOUT( s_udphdr_ , s_udpdata_ , m_udphdr_ , m_udpdata_ , TC_PORT),
                    .my_mac_address( my_mac_address ),
                    .nfragment_count_o( num_fragment_qwords ),
                    .fragsrc_mask_o(fragsrc_mask),
                    .event_ip_o( event_ip ),
                    .event_port_o( event_port ),
                    .event_open_o( event_is_open ));
    // Ack port module always responds at its own port
    assign hdrout_tuser[16*TA_PORT +: 16] = OUTBOUND[16*TA_PORT +: 16];
    // Acking/nacking is the same module, they do the same things.
    turf_acknack_port #(.CHECK_BITS(64'h800000FF_FFF00000))
        u_ackport( .aclk(clk156), .aresetn(!clk156_rst),
                    `CONNECT_UDP_INOUT( s_udphdr_ , s_udpdata_ , m_udphdr_ , m_udpdata_ , TA_PORT),
                    .event_open_i(event_is_open),
                    `CONNECT_AXI4S_MIN_IF( m_acknack_ , m_ack_ ));
    // Nack port module always responds to its own port
    assign hdrout_tuser[16*TN_PORT +: 16] = OUTBOUND[16*TN_PORT +: 16];
    turf_acknack_port #(.CHECK_BITS(64'h000000FF_FFFFFFFF))
        u_nackport( .aclk(clk156),.aresetn(!clk156_rst),
                    `CONNECT_UDP_INOUT( s_udphdr_ , s_udpdata_ , m_udphdr_ , m_udpdata_ , TN_PORT),
                    .event_open_i(event_is_open),
                    `CONNECT_AXI4S_MIN_IF( m_acknack_ , m_nack_ ));
    // Fragment module is a pure output. It does NOT always
    // transmit at a fixed port, so need to hook up tuser here.
    // This uses the T0_PORT.
    turf_fragment_gen u_fraggen(.aclk(clk156),.aresetn(!clk156_rst),
                                .nfragment_count_i(num_fragment_qwords),
                                .fragsrc_mask_i(fragsrc_mask),
                                `CONNECT_UDP_OUT( m_hdr_ , m_payload_ , T0_PORT ),
                                .m_hdr_tuser( hdrout_tuser[16*T0_PORT +: 16] ),
                                `CONNECT_AXI4S_MIN_IF( s_ctrl_ , s_ev_ctrl_ ),
                                `CONNECT_AXI4S_MIN_IF( s_data_ , s_ev_data_ ),
                                .s_data_tkeep(s_ev_data_tkeep),
                                .s_data_tlast(s_ev_data_tlast));


    wire [NUM_OUTBOUND-1:0] out_port_active;
    udp_port_mux #(.NUM_PORT(NUM_OUTBOUND),
                   .PAYLOAD_WIDTH(PAYLOAD_WIDTH))
                   u_udpmux(.aclk(clk156),.aresetn(!clk156_rst),
                            `CONNECT_AXI4S_MIN_IF( s_udphdr_ , hdrout_ ),
                            .s_udphdr_tuser( hdrout_tuser ),
                            `CONNECT_AXI4S_IF( s_udpdata_ , dataout_ ),
                            
                            `CONNECT_AXI4S_MIN_IF( m_udphdr_ , udpout_hdr_ ),
                            .m_udphdr_tuser( udpout_hdr_tuser ),
                            `CONNECT_AXI4S_IF( m_udpdata_ , udpout_data_ ),
                            
                            .port_active(out_port_active));

    generate
        if (DEBUG_IN == "TRUE") begin : INILA
            udp_ila u_udp_ila( .clk(clk156),
                               .probe0( udpin_hdr_tdest ),
                               .probe1( udpin_hdr_tvalid),
                               .probe2( udpin_data_tdata ),
                               .probe3( udpin_data_tkeep ),
                               .probe4( udpin_data_tvalid ),
                               .probe5( udpin_data_tready ),
                               .probe6( udpin_data_tlast ),
                               .probe7( udpin_hdr_tdata[0 +: 15] ));                      
        end
        if (DEBUG_OUT == "TRUE") begin : OUTILA    
            udp_ila u_udpout_ila( .clk(clk156),
                                     .probe0( udpout_hdr_tuser ),
                                     .probe1( udpout_hdr_tvalid ),
                                     .probe2( udpout_data_tdata ),
                                     .probe3( udpout_data_tkeep ),
                                     .probe4( udpout_data_tvalid ),
                                     .probe5( udpout_data_tready ),
                                     .probe6( udpout_data_tlast ),
                                     .probe7( udpout_hdr_tdata[0 +: 15] ));
        end
        if (DEBUG_EVENT_VIO == "TRUE") begin : EVENTVIO
            event_ctrl_vio u_evctrlvio( .clk(clk156),
                                        .probe_in0( event_ip ),
                                        .probe_in1( event_port ),
                                        .probe_in2( event_is_open ));
        end
        if (DEBUG_ACKNACK == "TRUE") begin : ACKNACKILA
            acknack_ila u_ila(.clk(clk156),
                              .probe0( m_ack_tvalid ),
                              .probe1( m_ack_tready ),
                              .probe2( m_ack_tdata ),
                              .probe3( m_nack_tvalid ),
                              .probe4( m_nack_tready ),
                              .probe5( m_nack_tdata ));
        end
    endgenerate
    // interface conversion/clock cross

    // interface runs at Ethernet speed
    assign aclk = clk156;
    
endmodule

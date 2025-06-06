`timescale 1ns / 1ps
`include "interfaces.vh"

// Based on the core modules from alexforencich's verilog-ethernet cores, but wholly rewritten by me.
// The UDP demux is a little more straightforward for us, since we drop like *all* of the damn IP stuff.
// Basically you just accept a UDP header and use that to allow a payload to flow through using an
// axis_demux. So it's basically two axis_demuxes and a lookup table for the select.
module turf_udp_core(
        input clk,
        input rst,
        // SFP base
        input sfp_tx_clk,
        input sfp_tx_rst,
        output [63:0] sfp_txd,
        output [7:0] sfp_txc,
        input sfp_rx_clk,
        input sfp_rx_rst,
        input [63:0] sfp_rxd,
        input [7:0] sfp_rxc,
        // my MAC address
        input [47:0] my_mac_address,        
        // UDP out: combination of src ip/port + length
        // [32 +: 32] = src ip
        // [16 +: 16] = src port
        // [0 +: 16] = length        
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_udphdr_ , 64 ),
        // and we put the dst port on tdest
        output [15:0] m_udphdr_tdest,
        `HOST_NAMED_PORTS_AXI4S_IF( m_udpdata_ , 64 ),
        
        // UDP in
        // [32 +: 32] = dst ip
        // [16 +: 16] = dst port
        // [0 +: 16] = length        
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_udphdr_ , 64 ),
        // src port
        input [15:0] s_udphdr_tuser,
        `TARGET_NAMED_PORTS_AXI4S_IF( s_udpdata_ , 64 )
    );
    // 10.68.65.81
    parameter [31:0] MY_IP_ADDRESS = { 8'd10,  "DAQ" };
    parameter [31:0] MY_NETMASK    = { 8'd255,  8'd255,  8'd255,  8'd0   };
    parameter [31:0] MY_GATEWAY    = { 8'd10,  "DA",    8'd1   };
        
    // Link between MAC and Ethernet
    `DEFINE_AXI4S_IF( tx_axis_ , 64);
    wire       tx_axis_tuser;
    `DEFINE_AXI4S_IF( rx_axis_ , 64);
    wire       rx_axis_tuser;
    
    eth_mac_10g_fifo_core
        u_eth_mac_10g_fifo(
            .rx_clk(sfp_rx_clk),
            .rx_rst(sfp_rx_rst),
            .tx_clk(sfp_tx_clk),
            .tx_rst(sfp_tx_rst),
            .logic_clk(clk),
            .logic_rst(rst),
            // ptp stuff, unused
            .ptp_sample_clk(clk),
            .ptp_ts_96( {96{1'b0}} ),
            .ptp_ts_step( 1'b0 ),
            .m_axis_tx_ptp_ts_ready(1'b1),
            // end ptp           
            `CONNECT_AXI4S_IF( tx_axis_ , tx_axis_ ),
            .tx_axis_tuser(tx_axis_tuser),
            `CONNECT_AXI4S_IF( rx_axis_ , rx_axis_ ),
            .rx_axis_tuser(rx_axis_tuser),
            
            .xgmii_rxd(sfp_rxd),
            .xgmii_rxc(sfp_rxc),
            .xgmii_txd(sfp_txd),
            .xgmii_txc(sfp_txc),
            
            // bunch of debugging stuff, ignore
            // interframe gap
            .ifg_delay(8'd12));

    // ethernet AXIS-to-frame. sigh, these could've been collected into another stream.
    wire rx_eth_hdr_ready;
    wire rx_eth_hdr_valid;
    wire [47:0] rx_eth_dest_mac;
    wire [47:0] rx_eth_src_mac;
    wire [15:0] rx_eth_type;
    `DEFINE_AXI4S_IF( rx_eth_payload_ , 64 );
    wire rx_eth_payload_tuser;
    
    wire tx_eth_hdr_ready;
    wire tx_eth_hdr_valid;
    wire [47:0] tx_eth_dest_mac;
    wire [47:0] tx_eth_src_mac;
    wire [15:0] tx_eth_type;
    `DEFINE_AXI4S_IF( tx_eth_payload_ , 64);
    wire tx_eth_payload_tuser;
    
    // frame receiver
    // I should really wrap this so that it's just another stream,
    // embedding src/dest/type into a giant-ass tdata
    
    // of course I could also wrap the whole damn thing with real interfaces
    eth_axis_rx #(.DATA_WIDTH(64))
        u_eth_rx( .clk(clk),
                  .rst(rst),
                  `CONNECT_AXI4S_IF(s_axis_ , rx_axis_ ),
                  .s_axis_tuser(rx_axis_tuser),
                  .m_eth_hdr_valid( rx_eth_hdr_valid ),
                  .m_eth_hdr_ready( rx_eth_hdr_ready ),
                  .m_eth_dest_mac( rx_eth_dest_mac ),
                  .m_eth_src_mac( rx_eth_src_mac ),
                  .m_eth_type( rx_eth_type ),
                  `CONNECT_AXI4S_IF( m_eth_payload_axis_ , rx_eth_payload_ ),
                  .m_eth_payload_axis_tuser(rx_eth_payload_tuser));
    // frame transmitter
    // see above
    eth_axis_tx #(.DATA_WIDTH(64))
        u_eth_tx( .clk(clk),
                  .rst(rst),
                  `CONNECT_AXI4S_IF(m_axis_ , tx_axis_ ),
                  .m_axis_tuser(tx_axis_tuser),
                  .s_eth_hdr_valid( tx_eth_hdr_valid ),
                  .s_eth_hdr_ready( tx_eth_hdr_ready ),
                  .s_eth_dest_mac(  tx_eth_dest_mac ),
                  .s_eth_src_mac(   tx_eth_src_mac  ),
                  .s_eth_type(      tx_eth_type ),
                  `CONNECT_AXI4S_IF(s_eth_payload_axis_ , tx_eth_payload_ ),
                  .s_eth_payload_axis_tuser(tx_eth_payload_tuser));

    // UDP core, now the IP packaged version
    udp_complete_64_core
    u_udp_complete(
        .clk(clk),
        .rst(rst),
        // eth frame hdr receive
        .s_eth_hdr_valid(rx_eth_hdr_valid),
        .s_eth_hdr_ready(rx_eth_hdr_ready),
        .s_eth_dest_mac(rx_eth_dest_mac),
        .s_eth_src_mac(rx_eth_src_mac),
        .s_eth_type(rx_eth_type),
        // eth frame payload receive
        `CONNECT_AXI4S_IF( s_eth_payload_axis_ , rx_eth_payload_ ),
        .s_eth_payload_axis_tuser( rx_eth_payload_tuser ),
        // eth frame hdr transmit
        .m_eth_hdr_valid(tx_eth_hdr_valid),
        .m_eth_hdr_ready(tx_eth_hdr_ready),
        .m_eth_dest_mac(tx_eth_dest_mac),
        .m_eth_src_mac(tx_eth_src_mac),
        .m_eth_type(tx_eth_type),
        `CONNECT_AXI4S_IF( m_eth_payload_axis_ , tx_eth_payload_ ),
        .m_eth_payload_axis_tuser( tx_eth_payload_tuser ),
        // IP (input) ports (unused)
        .m_ip_hdr_ready( 1'b1 ),
        .m_ip_payload_axis_tready( 1'b1 ),
        .s_ip_hdr_valid( 1'b0 ),
        .s_ip_dscp( 6'h00 ),
        .s_ip_length( {16{1'b0}} ),
        .s_ip_ecn( 2'b00 ),
        .s_ip_ttl( 8'd64 ),
        .s_ip_protocol( {8{1'b0}} ),
        .s_ip_source_ip( {32{1'b0}} ),
        .s_ip_dest_ip( {32{1'b0}} ),
        .s_ip_payload_axis_tvalid( 1'b0 ),
        .s_ip_payload_axis_tdata( {64{1'b0}} ),
        .s_ip_payload_axis_tkeep( {8{1'b0}} ),
        .s_ip_payload_axis_tuser( 1'b0 ),
        .s_ip_payload_axis_tlast( 1'b0 ),
        // Unused UDP ports
        .s_udp_ip_dscp({6{1'b0}}),
        .s_udp_ip_ecn({2{1'b0}}),
        .s_udp_ip_ttl(8'd64),
        // UDP frame input
        .s_udp_hdr_valid( s_udphdr_tvalid ),
        .s_udp_hdr_ready( s_udphdr_tready ),
        .s_udp_ip_source_ip( MY_IP_ADDRESS ),
        .s_udp_ip_dest_ip( s_udphdr_tdata[32 +: 32] ),
        .s_udp_source_port(s_udphdr_tuser ),
        .s_udp_dest_port( s_udphdr_tdata[16 +: 16]),
        .s_udp_length( s_udphdr_tdata[0 +: 16]),
        .s_udp_checksum( 16'h0000 ),
        `CONNECT_AXI4S_IF( s_udp_payload_axis_ , s_udpdata_ ),
        .s_udp_payload_axis_tuser( 1'b0 ),
        // UDP frame output
        .m_udp_hdr_valid( m_udphdr_tvalid ),
        .m_udp_hdr_ready( m_udphdr_tready ),
        .m_udp_ip_source_ip( m_udphdr_tdata[32 +: 32] ),
        .m_udp_source_port( m_udphdr_tdata[16 +: 16] ),
        .m_udp_dest_port( m_udphdr_tdest ),
        .m_udp_length( m_udphdr_tdata[0 +: 16] ),
        `CONNECT_AXI4S_IF( m_udp_payload_axis_ , m_udpdata_ ),
        // skip bunch o crap...
        .local_mac( my_mac_address ),
        .local_ip( MY_IP_ADDRESS ),
        .gateway_ip( MY_GATEWAY ),
        .subnet_mask( MY_NETMASK ),
        .clear_arp_cache( 1'b0) );        
    
endmodule

`timescale 1ns / 1ps
`include "interfaces.vh"
module turf_udp_hsk(
        input aclk,
        input aresetn,
        // hsk interface
        input sclk,
        input mosi,
        output miso,
        input [1:0] cs_b,
        // this gets hooked up to an EMIO input as an IRQ
        // we set this after processing a UDP packet and
        // clear it when it's been processed. to do this
        // we mark the end of the UDP data.
        // we also just flat dump the data if the FIFO
        // can't handle it. so sadly we need a bit of
        // a smart FIFO.
        output irq_o,
        // UDP
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_udphdr_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_IF( s_udpdata_ , 64 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_udphdr_ , 64 ),
        `HOST_NAMED_PORTS_AXI4S_IF( m_udpdata_ , 64 )
    );

    turf_udp_hsk_read #(.DEBUG("FALSE"))
        u_read( .aclk(aclk),.aresetn(aresetn),
                `CONNECT_AXI4S_MIN_IF( s_udphdr_ , s_udpdhr_ ),
                `CONNECT_AXI4S_IF( s_udpdata_ , s_udpdata_ ),
                .sclk(sclk),
                .miso(miso),
                .cs_b(cs_b[0]),
                .irq_o(irq_o),
                .complete_o(complete_o));

    // we always respond to the last IP/port that sent data    
    // BY DEFAULT we start out at 192.168.1.1 and port 16'h5368;
    reg [31:0] this_ip = 32'hC0A80101;
    reg [15:0] this_port = 16'h5368;

    always @(posedge aclk) begin
        if (s_udphdr_tvalid && s_udphdr_tready) begin
            this_ip <= s_udphdr_tdata[32 +: 32];
            this_port <= s_udphdr_tdata[16 +: 16];
        end
    end

    turf_udp_hsk_write #(.DEBUG("TRUE"))
        u_write(.aclk(aclk),.aresetn(aresetn),
                .port_i(this_port),.ip_i(this_ip),
                .sclk(sclk),.mosi(mosi),.cs_b(cs_b[1]),
                `CONNECT_AXI4S_MIN_IF( m_udphdr_ , m_udphdr_ ),
                `CONNECT_AXI4S_IF( m_udpdata_ , m_udpdata_ ) );    

//    // the transmit stuff is sleazier: we use a 9 bit shift register,
//    // initialize it to 9b0_0000_0001, and shift up each clock.
//    reg [8:0]   tx_fifo_holding_reg = {9{1'b0}};
//    reg [1:0]   mosi_reg = 3'b00;
//    reg         cs_write_rereg = 1;
//    reg         sclk_rising_rereg = 0;
//    // however, we need to sleaze things more:
//    // we have to reshape to 64 bits, so we use an 8-to-64 bit AXI4-Stream width converter.
//    // we actually shift one clock after the rising edge detection, delaying mosi
//    // if we see
//    //      rising edge and tx_fifo_holding_reg[8] => txd_tvalid && !txd_tlast
//    //                                                reset tx_fifo_holding_reg to 9'h001
//    //      cs_b rising edge and tx_fifo_holding_reg[8] => txd_tvalid && txd_tlast
//    // the width converter will then handle the TKEEPing and such when tlast hits.
//    // we also need a *second* FIFO which stores the number of bytes we receive in each
//    // transfer. That's what actually initiates the UDP write.
    
    
//    `DEFINE_AXI4S_MIN_IF( txd_ , 8 );
//    assign txd_tdata = tx_fifo_holding_reg[7:0];
//    wire txd_tlast;

//    // number of bytes received this transfer    
//    reg [12:0] txn_bytes = {13{1'b0}};
//    wire       txn_bytes_valid = txd_tlast && txd_tvalid;
        


    assign m_udphdr_tdata = {64{1'b0}};
    assign m_udphdr_tvalid = 0;
    assign m_udpdata_tdata = {64{1'b0}};
    assign m_udpdata_tvalid = 0;
    assign m_udpdata_tlast = 0;
    assign m_udpdata_tkeep = {8{1'b0}};


endmodule

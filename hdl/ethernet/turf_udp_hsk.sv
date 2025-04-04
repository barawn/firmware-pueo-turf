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
        output complete_o,
        // UDP
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_udphdr_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_IF( s_udpdata_ , 64 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_udphdr_ , 64 ),
        `HOST_NAMED_PORTS_AXI4S_IF( m_udpdata_ , 64 )
    );

    turf_udp_hsk_read #(.DEBUG("TRUE"))
        u_read( .aclk(aclk),.aresetn(aresetn),
                `CONNECT_AXI4S_MIN_IF( s_udphdr_ , s_udphdr_ ),
                `CONNECT_AXI4S_IF( s_udpdata_ , s_udpdata_ ),
                .sclk(sclk),
                .miso(miso),
                .cs_b(cs_b[0]),
                .irq_o(irq_o),
                .complete_o(complete_o));

    // we always respond to the last IP/port that sent data
    reg [31:0] this_ip = { 8'd10, "DA", 8'd1};
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
        

endmodule

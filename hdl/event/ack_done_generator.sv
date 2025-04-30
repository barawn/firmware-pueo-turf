`timescale 1ns / 1ps
`include "interfaces.vh"
// takes in ack/nack, clock-crosses them and generates
// the doneaddrs and the allow flags.
// The acks have to be able to store a lot (all 4096)
// so it'll need 2 BRAMs (sigh). Don't need to store
// the allow stuff though. They'll flag because the
// acknack ports can't do multiple writes in one.
//
// The nacks don't need to be that big, just a 512x72
// is fine.
// We peel off the constant values just to simplify
// the route, it's not smart enough.
// So this means it's actually 32 + 11 + 1 = 44 bits.
module ack_done_generator(
        // this is ethclk!!!
        input aclk,
        input aresetn,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_ack_ , 48 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_nack_ , 48 ),
        input memclk,
        input memresetn,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_nack_ , 48 ),
        output allow_o,
        // Need to accept the TIO mask because if it's masked,
        // it will autoconsume the addr (and its valid output will be blocked for safety).
        input [3:0] tio_mask_i,
        // really only 12 bits
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_hdraddr_ , 16 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_t0addr_ , 16 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_t1addr_ , 16 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_t2addr_ , 16 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_t3addr_ , 16 )
    );
    // CC the nack path, that's all we need to do
    wire [43:0] nack_din = { s_nack_tdata[46], s_nack_tdata[42:0] };
    wire        nack_full;
    assign      s_nack_tready = !nack_full;
    wire [43:0] nack_dout;
    assign       m_nack_tdata = { 1'b0, nack_dout[43], {3{1'b0}},
                                  nack_dout[42:0] };
    nack_ccfifo u_nackfifo( .wr_clk( aclk ),
                            .srst( !aresetn ),
                            .din(nack_din),
                            .wr_en( s_nack_tvalid && s_nack_tready ),
                            .full(nack_full),
                            .rd_clk( memclk ),
                            .dout( nack_dout ),
                            .valid( m_nack_tvalid ),
                            .rd_en( m_nack_tvalid && m_nack_tready ));

    // the ACK path needs to be a big FIFO. Create a temporary
    // output and use a broadcaster.
    `DEFINE_AXI4S_MIN_IF( ackfifo_ , 16 );    
    wire [11:0] ack_din = s_ack_tdata[20 +: 12];
    wire        ack_full;
    assign      s_ack_tready = !ack_full;
    wire [11:0] ack_dout;
    assign      ackfifo_tdata = { {4{1'b0}}, ack_dout };    

    wire [3:0] tio_addr_tvalid;
    assign m_t0addr_tvalid = tio_addr_tvalid[0] && !tio_mask_i[0];
    assign m_t1addr_tvalid = tio_addr_tvalid[1] && !tio_mask_i[1];
    assign m_t2addr_tvalid = tio_addr_tvalid[2] && !tio_mask_i[2];
    assign m_t3addr_tvalid = tio_addr_tvalid[3] && !tio_mask_i[3];
    wire [3:0] tio_addr_tready;
    assign tio_addr_tready[0] = m_t0addr_tready || tio_mask_i[0];
    assign tio_addr_tready[1] = m_t1addr_tready || tio_mask_i[1];
    assign tio_addr_tready[2] = m_t2addr_tready || tio_mask_i[2];
    assign tio_addr_tready[3] = m_t3addr_tready || tio_mask_i[3];

    ack_ccfifo u_ackfifo( .wr_clk( aclk ),
                          .srst( !aresetn ),
                          .din( ack_din ),
                          .full( ack_full ),
                          .wr_en( s_ack_tvalid && s_ack_tready ),
                          .rd_clk( memclk ),
                          .dout( ack_dout ),
                          .rd_en( ackfifo_tvalid && ackfifo_tready),
                          .valid( ackfifo_tvalid ) );
    // and that's it, it takes care of everything for us.
    doneaddr_broadcast u_broadcast( .aclk( memclk ),
                                    .aresetn( memresetn ),
                                    `CONNECT_AXI4S_MIN_IF( s_axis_ , ackfifo_ ),
                                    // no macros here, it's a vec
                                    .m_axis_tdata( { m_hdraddr_tdata,
                                                     m_t3addr_tdata,
                                                     m_t2addr_tdata,
                                                     m_t1addr_tdata,
                                                     m_t0addr_tdata } ),
                                    .m_axis_tvalid({ m_hdraddr_tvalid,
                                                     tio_addr_tvalid }),
                                    .m_axis_tready({ m_hdraddr_tready,
                                                     tio_addr_tready }));
                          
    // and we clock-cross the allow bit                              
    flag_sync u_allow_sync(.in_clkA( s_ack_tdata[47] && s_ack_tvalid && s_ack_tready ),
                           .out_clkB( allow_o ),
                           .clkA( aclk ),
                           .clkB( memclk ));
                                             
endmodule

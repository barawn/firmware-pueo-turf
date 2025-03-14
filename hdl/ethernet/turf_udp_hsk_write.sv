`timescale 1ns / 1ps
`include "interfaces.vh"
module turf_udp_hsk_write(
        input aclk,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_udphdr_ , 64 ),
        `HOST_NAMED_PORTS_AXI4S_IF( m_udpdata_ , 64 ),
        input sclk,
        input mosi,
        input cs_b,
        input [15:0] port_i,
        input [15:0] ip_i
    );
    parameter DEBUG = "TRUE";
    
    // use 8-bit shift register: start with a 1 in the low bit, when
    // it reaches the top we're done. Bottom bit is mosi_reg.
    reg [7:0] shift_in_reg = 8'd1;
    // clock register. 1 = rising edge 2 = falling edge. sequence goes 0/1/3/2
    reg [1:0] wr_clk_reg = {2{1'b0}};
    wire SCLK_RISING = wr_clk_reg == 2'd1;
    wire SCLK_FALLING = wr_clk_reg == 2'd2;
    
    // we want to capture mosi the same time sclk is high, so delay it
    reg       mosi_reg = 0;
    // we're going to need to detect edges on cs_b too
    reg [1:0] cs_b_reg = {2{1'b0}};
    
    // 0000_0001 A    start
    // 0000_001A B    shift in A
    // 0000_01AB C    shift in B
    // 0000_1ABC D    shift in C
    // 0001_ABCD E    shift in D
    // 001A_BCDE F    shift in E
    // 01AB_CDEF G    shift in F
    // 1ABC_DEFG H    reset
    
    // however, we use a SECONDARY register to hold data AGAIN because
    // we need to figure out if our data is the LAST data. This is
    // what we capture it in to. Capture occurs when wr_clk_reg == 1 && shift_in_reg[7].
    reg [7:0] secondary_reg = {8{1'b0}};
    // we stupidly need another register to verify that the secondary data is valid
    reg       secondary_is_valid = 0;
    
    // After capture, if we get ANOTHER rising edge on sclk, we feed the secondary
    // reg into an AXI4-Stream width converter. If we get a rising edge on cs_b,
    // we feed it into the AXI4-Stream width converter with tlast set.
    `DEFINE_AXI4S_MIN_IF( wc_ , 8);
    wire wc_tlast;
    
    assign wc_tdata = secondary_reg;
    assign wc_tlast = (cs_b_reg == 2'b1);
    assign wc_tvalid = (cs_b_reg == 2'b1 || (wr_clk_reg == 2'b1 && shift_in_reg[7]))
                        && secondary_is_valid;

    `DEFINE_AXI4S_IF( wc64_ , 64);
    
    // we sleaze the FIFO slightly to pass tlast in a 72-bit word:
    // we drop tkeep[0] (since it's always set) and replace it with
    // tlast.
    wire [71:0] wr_fifo_din = { wc64_tkeep[6:1], wc64_tlast, wc64_tdata };
    wire        wr_fifo_full;
    wire        wr_fifo_wren = (wc64_tready && wc64_tvalid);
    assign wc64_tready = !wr_fifo_full;
    
    // now we ALSO need to count the number of bytes we're going to send.
    // we always start with 8 and we increment with every wc_tvalid && wc_tready,
    // resetting back to 8 after we write.
    // max out at 12 bits for fun.
    reg [11:0]  wr_byte_count = 12'd8;
    reg         last_byte_write = 0;
    reg         write_wr_byte_count = 0;
    
    // Now the output sides.
    wire [71:0] packet_fifo_dout;
    wire        packet_fifo_valid;
    wire        packet_fifo_read;
    // Count fifo outputs
    wire [11:0] count_fifo_dout;
    wire        count_fifo_valid;
    wire        count_fifo_read;
    
    always @(posedge aclk) begin
        wr_clk_reg <= { wr_clk_reg[0], sclk };
        cs_b_reg <= { cs_b_reg[0], cs_b };
        mosi_reg <= mosi;
        
        if (cs_b_reg[0]) shift_in_reg <= 8'd1;                
        else if (!cs_b_reg[0] && SCLK_RISING) begin
            if (shift_in_reg[7]) shift_in_reg <= 8'd1;
            else shift_in_reg <= {shift_in_reg[6:0], mosi_reg };
        end
        
        if (!cs_b_reg[0] && SCLK_RISING && shift_in_reg[7]) begin
            secondary_reg <= { shift_in_reg[6:0], mosi_reg };
            secondary_is_valid <= 1;
        end else if (wc_tvalid) secondary_is_valid <= 0;        

        // the secondary_is_valid qualifier here means everything
        // will go to hell if you don't write in multiples of 8
        // which isn't a problem. it prevents cs_b assertion/deassertion
        // which ALSO shouldn't happen
        last_byte_write <= (cs_b_reg == 2'd1 && secondary_is_valid);
        write_wr_byte_count <= last_byte_write;
        
        if (write_wr_byte_count) wr_byte_count <= 12'd8;
        else if (wc_tvalid && wc_tready) wr_byte_count <= wr_byte_count + 1;
    end
    
    // I SHOULD JUST BE ABLE TO HOOK UP THESE FIFOS TO THE STREAMS!!    
    axis_8to64 u_axiwc(.aclk(aclk),.aresetn(aresetn),
                        `CONNECT_AXI4S_MIN_IF(s_axis_ , wc_ ),
                        .s_axis_tlast(wc_tlast),
                        `CONNECT_AXI4S_IF(m_axis_ , wc64_ ));
    udp_hsk_txfifo u_txfifo(.clk(aclk),.srst(!aresetn),
                            .din(wr_fifo_din),
                            .wr_en(wr_fifo_wren),
                            .full(wr_fifo_full),
                            .dout(packet_fifo_dout),
                            .valid(packet_fifo_valid),
                            .read(packet_fifo_read));
    udp_hsk_txcount u_txcount(.clk(aclk),.srst(!aresetn),
                              .din(wr_byte_count),
                              .wr_en(write_wr_byte_count),
                              .dout(count_fifo_dout),
                              .valid(count_fifo_valid),
                              .rd_en(count_fifo_read));

    generate
        if (DEBUG == "TRUE") begin : DBG
            // sclk/mosi/cs_b/secondary reg/secondary is valid
            // and then count_fifo_dout/count_fifo_valid/count_fifo_read
            // and packet_fifo_valid/packet_fifo_read
            // this is 11 total
            // 1 / 1 / 1 
            // 8 / 1
            // 12 / 1 / 1
            // 1 / 1
            hsk_tx_ila u_ila(.clk(aclk),
                             .probe0(sclk),
                             .probe1(mosi),
                             .probe2(cs_b),
                             .probe3(secondary_reg),
                             .probe4(secondary_is_valid),
                             .probe5(count_fifo_dout),
                             .probe6(count_fifo_valid),
                             .probe7(count_fifo_read),
                             .probe8(packet_fifo_valid),
                             .probe9(packet_fifo_read));
        end
    endgenerate


    // HOOK EM UP HERE!!!!                              
    assign m_udphdr_tdata = { ip_i, port_i, {4{1'b0}}, count_fifo_dout };
    assign m_udphdr_tvalid = count_fifo_valid;
    assign count_fifo_read = (m_udphdr_tvalid && m_udphdr_tready);
    
    assign m_udpdata_tdata = packet_fifo_dout[0 +: 64];
    assign m_udpdata_tlast = packet_fifo_dout[64];
    assign m_udpdata_tkeep = { packet_fifo_dout[65 +: 6], 1'b1 };
    assign m_udpdata_tvalid = packet_fifo_valid;
    assign packet_fifo_read = (m_udpdata_tvalid && m_udpdata_tready); 
                                        
endmodule

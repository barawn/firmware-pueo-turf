`timescale 1ns / 1ps
`include "interfaces.vh"

// This is the read functionality of the TURF UDP HSK port, factored out.
module turf_udp_hsk_read(
        input aclk,
        input aresetn,
        
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_udphdr_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_IF( s_udpdata_ , 64 ),
        
        input sclk,
        output miso,
        input cs_b,
        output irq_o,
        output complete_o
    );
    
    parameter DEBUG = "TRUE";

    localparam [9:0] MAX_WRITE = 512;
    reg [9:0] this_check = {10{1'b0}};
    // this is actually datagram length + 8: the nice thing
    // about this is that we can just drop the bottom 3 bits
    // and it's a safe upward round.
    wire [15:0] this_length = s_udphdr_tdata[0 +: 16];
    wire [12:0] this_length64 = this_length[15:3];

    wire [9:0] wr_data_count;    
    wire       wr_fifo_full;
    wire       wr_fifo_write;
    // We have to swizzle the write FIFO data and also qualify it on TKEEP to make sure
    // to push extra zeros, and also to deal with the fact that the endianness is swapped.
    // that is: when we WRITE into the FIFO, the aspect ratio swap means you READ OUT
    // MSB to LSB. Except the LSB here is the FIRST byte in the UDP packet. So we need to swap.
    wire [63:0] wr_fifo_data;
    assign wr_fifo_data[0 +: 8]  = s_udpdata_tdata[56 +: 8] & {8{s_udpdata_tkeep[7]}};
    assign wr_fifo_data[8 +: 8]  = s_udpdata_tdata[48 +: 8] & {8{s_udpdata_tkeep[6]}};
    assign wr_fifo_data[16 +: 8] = s_udpdata_tdata[40 +: 8] & {8{s_udpdata_tkeep[5]}};
    assign wr_fifo_data[24 +: 8] = s_udpdata_tdata[32 +: 8] & {8{s_udpdata_tkeep[4]}};
    assign wr_fifo_data[32 +: 8] = s_udpdata_tdata[24 +: 8] & {8{s_udpdata_tkeep[3]}};
    assign wr_fifo_data[40 +: 8] = s_udpdata_tdata[16 +: 8] & {8{s_udpdata_tkeep[2]}};
    assign wr_fifo_data[48 +: 8] = s_udpdata_tdata[8 +: 8] & {8{s_udpdata_tkeep[1]}};
    assign wr_fifo_data[56 +: 8] = s_udpdata_tdata[0 +: 8] & {8{s_udpdata_tkeep[0]}};

    wire        rd_fifo_empty;
    reg         rd_fifo_read = 0;    
    reg         rd_fifo_next_sclk = 0;
    wire [7:0]  rd_fifo_data;
    reg  [7:0]  rd_fifo_holding_reg = {8{1'b0}};
    reg  [2:0]  rd_bit_counter = {3{1'b0}};
    // 1 = rising edge
    // 2 = falling edge
    reg  [1:0]  rd_clk_reg = {2{1'b0}};
    wire        SCLK_RISING = (rd_clk_reg == 2'd1);
    wire        SCLK_FALLING = (rd_clk_reg == 2'd2);
    
    // we also need to store number of written bytes into the FIFO. We disallow
    // anything bigger than 511 qwords, so this is a 9 bit number.
    reg [8:0]   packet_qword_counter = {9{1'b0}};
    wire        write_packet_count;
    wire        packet_count_full;
    wire        packet_count_valid;
    wire        read_packet_count;
    reg         packet_count_was_read = 0;
    wire [8:0]  available_packet_count;
    // this is the number of bytes _read out_ 12 bit number
    reg [11:0]  rx_read_counter = {12{1'b0}};
    // this indicates we *will* terminate at the next byte completion
    reg         rx_read_will_terminate = 0;
    
    // this indicates that we're reading a packet
    reg         rx_reading_packet = 0;
    // reregister so we can see the start
    reg         rx_reading_packet_rereg = 0;    
    // cs registered
    reg         cs_read_reg = 1;
    // reregister cs so we can see a falling edge
    reg         cs_read_rereg = 1;

    //////////////////////////////////////////////////////////////
    //              OK I NEED TO SPELL THIS OUT NOW             //
    //////////////////////////////////////////////////////////////
    // This is getting too complicated. Spell it out.           //
    // We don't care about the registration delay with cs_b     //
    // since practically those happen infinitely in front.      //
    //
    // Assume packet_count_valid = 1. Assume a 4-cycle SCLK to be safe.
    //
    // clk  sclk    csb     rx_reading_packet   rx_read_counter available_packet_count  rd_clk_reg  rd_bit_counter  rx_read_will_terminate  rd_fifo_holding_reg     MISO            read_next_sclk read
    // 0    0       1       0                   1               2                       0           0               0                       X                                       0               0
    // 1    0       0       1                   1               2                       0           0               0                       X                                       0               0
    // 2    0       0       1                   1               2                       0           0               0                       A[7:0]                  A7              1               0
    // 3    1       0       1                   1               2                       0           0               0                       A[7:0]                  A7      <--     1               0
    // 4    1       0       1                   1               2                       1           0               0                       A[7:0]                  A7              1               0
    // 5    0       0       1                   1               2                       3           1               0                       A[7:0]<<1               A6              1               0
    // 6    0       0       1                   1               2                       2           1               0                       A[7:0]<<1               A6              1               1
    // 7    1       0       1                   1               2                       0           1               0                       A[7:0]<<1               A6      <--     0               0
    // 8    1       0       1                   1               2                       1           1               0                       A[7:0]<<1               A6              
    // 9    0       0       1                   1               2                       3           2               0                       A[7:0]<<2               A5
    // 10   0       0       1                   1               2                       2           2               0                       A[7:0]<<2               A5
    // 11   1       0       1                   1               2                       0           2               0                       A[7:0]<<2               A5      <--
    // 12   1       0       1                   1               2                       1           2               0                       A[7:0]<<2               A5
    // 13   0       0       1                   1               2                       3           3               0                       A[7:0]<<3               A4
    // 14   0       0       1                   1               2                       2           3               0                       A[7:0]<<3               A4
    // 11   1       0       1                   1               2                       0           3               0                       A[7:0]<<3               A4      <--
    // 12   1       0       1                   1               2                       1           3               0                       A[7:0]<<3               A4
    // 13   0       0       1                   1               2                       3           4               0                       A[7:0]<<4               A3
    // 14   0       0       1                   1               2                       2           4               0                       A[7:0]<<4               A3
    // 11   1       0       1                   1               2                       0           4               0                       A[7:0]<<4               A3      <--
    // 12   1       0       1                   1               2                       1           4               0                       A[7:0]<<4               A3
    // 13   0       0       1                   1               2                       3           5               0                       A[7:0]<<5               A2
    // 14   0       0       1                   1               2                       2           5               0                       A[7:0]<<5               A2
    // 11   1       0       1                   1               2                       0           5               0                       A[7:0]<<5               A2      <--
    // 12   1       0       1                   1               2                       1           5               0                       A[7:0]<<5               A2
    // 13   0       0       1                   1               2                       3           6               0                       A[7:0]<<6               A1
    // 14   0       0       1                   1               2                       2           6               0                       A[7:0]<<6               A1
    // 11   1       0       1                   1               2                       0           6               0                       A[7:0]<<6               A1      <--
    // 12   1       0       1                   1               2                       1           6               0                       A[7:0]<<6               A1
    // 13   0       0       1                   1               2                       3           7               0                       A[7:0]<<7               A0
    // 14   0       0       1                   1               2                       2           7               0                       A[7:0]<<7               A0
    // 11   1       0       1                   1               2                       0           7               0                       A[7:0]<<7               A0      <--
    // 12   1       0       1                   1               2                       1           7               0                       A[7:0]<<7               A0
    // 13   0       0       1                   2               2                       3           0               0                       B[7:0]                  B7
    // 14   0       0       1                   2               2                       2           0               1                       B[7:0]                  B7               0 (bc of rx_read_will_terminate)
    //...
    // 11   1       0       1                   2               2                       0           6               1                       B[7:0]<<6               B1      <--
    // 12   1       0       1                   2               2                       1           6               1                       B[7:0]<<6               B1
    // 13   0       0       1                   2               2                       3           7               1                       B[7:0]<<7               B0
    // 14   0       0       1                   2               2                       2           7               1                       B[7:0]<<7               B0
    // 11   1       0       1                   2               2                       0           7               1                       B[7:0]<<7               B0      <--
    // 12   1       0       1                   2               2                       1           7               1                       B[7:0]<<7               B0
    // 13   0       0       0                   3               2                       3           0               1                       00                      0
    // 14   0       0       0                   1               2                       2           0               0                       00                      0
    
    // observations:
    // rx_read_counter reset to 1, increment at rising edge (rd_clk_reg=1) when bit_counter == 7
    // rx_read_will_terminate is just (rx_read_counter == available_packet_count<<3)
    // read_next_sclk is rising edge of rx_reading_packet OR (rd_clk_reg=2 AND bit counter == 0 AND NOT rx_read_will_terminate) and cleared by rx_fifo_read OR cs_b
    // rx_fifo_read is rd_clk_reg=2 and read_next_sclk
    // rd_fifo_holding_reg is (rd_fifo_data IF rising edge rx_reading_packet) or IF (rd_clk_reg == 1), IF(bit_counter==7) rd_fifo_data ELSE rd_fifo_holding_reg<<1
    // --> read from read count FIFO on falling edge of rx_reading_packet

    assign      read_packet_count = (!rx_reading_packet && rx_reading_packet_rereg);
    
    // triggers rx_read_counter, clearing rx_reading_packet, and load rd_fifo_holding_reg
    wire        FINAL_SCLK_RISING = (SCLK_RISING && (rd_bit_counter == 7));

    // sleazy checks:
    // to check if this_length64 > MAX_WRITE, just check if the top bits are set.
    // You can only send 511 qwords. Boo hoo.
    // to check if there are enough bytes to check, we need to do:
    // (MAX_WRITE - wr_data_count) > this_length64
    // ==> MAX_WRITE - wr_data_count - this_length64 > 0
    // ==> MAX_WRITE + ~wr_data_count +1 + ~this_length64 +1 > 0
    // ==> MAX_WRITE+2 + ~wr_data_count + ~this_length64 > 0
    // ==> check if top bit of (~wr_data_count + ~this_length64 + MAX_WRITE+2) is NOT set
    // this SHOULD compress to an easy ternary adder: we'll see!
    localparam [9:0] MAX_WRITE_ADJUST = MAX_WRITE + 2;
    wire [9:0] inv_wr_data_count = ~wr_data_count;
    wire [9:0] inv_length64 = ~this_length64[9:0];
    wire [3:0] top_length64 = this_length64[12:9];
    wire [9:0] count_remain = MAX_WRITE_ADJUST + inv_wr_data_count + inv_length64;    
            
    localparam RX_FSM_BITS = 2;
    localparam [RX_FSM_BITS-1:0] RX_IDLE = 0;
    localparam [RX_FSM_BITS-1:0] RX_STORE = 1;
    localparam [RX_FSM_BITS-1:0] RX_COMPLETE = 2;
    localparam [RX_FSM_BITS-1:0] RX_DUMP = 3;
    reg [RX_FSM_BITS-1:0] rx_state = RX_IDLE;

    // interrupt goes high when a packet count becomes valid, clears when it completes        
    reg interrupt = 0;
    // complete will go high when a packet completes and will go low on the next cs_b falling
    reg complete = 0;

    assign wr_fifo_write = (s_udpdata_tvalid && s_udpdata_tready && (rx_state == RX_STORE) );
    assign s_udpdata_tready = (rx_state == RX_DUMP) || (rx_state == RX_STORE && !wr_fifo_full);
    assign write_packet_count = (rx_state == RX_COMPLETE);
        
    always @(posedge aclk) begin
        cs_read_reg <= cs_b;

        // count number of qwords written to FIFO
        if (rx_state == RX_IDLE) 
            packet_qword_counter <= {9{1'b0}};
        else if (rx_state == RX_STORE && s_udpdata_tvalid && s_udpdata_tready)
            packet_qword_counter <= packet_qword_counter + 1;
                            
        if (!aresetn) rx_state <= RX_IDLE;
        else case (rx_state)
            RX_IDLE: if (s_udphdr_tvalid && s_udphdr_tready) begin            
                if (top_length64 != {4{1'b0}} ||
                    count_remain[9] ||
                    packet_count_full)
                        rx_state <= RX_DUMP;
                else
                        rx_state <= RX_STORE;
            end
            RX_STORE: if (s_udpdata_tvalid && s_udpdata_tready && s_udpdata_tlast) 
                        rx_state <= RX_COMPLETE;
            RX_COMPLETE: rx_state <= RX_IDLE;
            RX_DUMP: if (s_udpdata_tvalid && s_udpdata_tready && s_udpdata_tlast)
                        rx_state <= RX_IDLE;
        endcase
        
        // interrupt logic: go high when packet count valid is high,
        // low when we read from it. But because of latency we need to hold off a clock.
        packet_count_was_read <= read_packet_count;

        if (packet_count_was_read) interrupt <= 0;
        else if (packet_count_valid) interrupt <= 1;
    
        if (!cs_read_reg && cs_read_rereg) complete <= 0;
        else if (packet_count_was_read) complete <= 1;         
   
        // by default we read out MSB first, so we shift UP
        // so we change on rising edge of clock.
        // we also reload on falling edge just to make it easier.
        rd_clk_reg <= { rd_clk_reg[0], sclk };

        // reregister cs so we can see it fall
        cs_read_rereg <= cs_read_reg;

    // rx_read_counter reset to 1, increment at rising edge (rd_clk_reg=1) when bit_counter == 7
    // rx_read_will_terminate is just (rx_read_counter == available_packet_count<<3)
    // read_next_sclk is rising edge of rx_reading_packet OR (rd_clk_reg=2 AND bit counter == 0 AND NOT rx_read_will_terminate) and cleared by rx_fifo_read OR cs_b
    // rx_fifo_read is rd_clk_reg=2 and read_next_sclk
    // rd_fifo_holding_reg is (rd_fifo_data IF rising edge rx_reading_packet) or IF (rd_clk_reg == 1), IF(bit_counter==7) rd_fifo_data ELSE rd_fifo_holding_reg<<1
    // --> read from read count FIFO on falling edge of rx_reading_packet
        
        // determine if we have a packet to read at falling edge,
        // clear when we marked a terminate ending and we just sent the last bit
        if (!cs_read_reg && cs_read_rereg)
            rx_reading_packet <= packet_count_valid;
        else if (rx_read_will_terminate && FINAL_SCLK_RISING)
            rx_reading_packet <= 1'b0;
        
        rx_reading_packet_rereg <= rx_reading_packet;
        // If we are not reading a packet, it's always zero.
        // When we _start_ reading a packet, capture the available data (since it was zero before)
        //      or if there's a falling clock edge and we've hit the bit counter, capture new data
        // If there's a rising clock edge, shift the data. 
        if (!rx_reading_packet)
            rd_fifo_holding_reg <= {8{1'b0}};
        else if (rx_reading_packet && !rx_reading_packet_rereg)
            rd_fifo_holding_reg <= rd_fifo_data;
        else if (SCLK_RISING) begin
            if (FINAL_SCLK_RISING) rd_fifo_holding_reg <= rd_fifo_data;
            else rd_fifo_holding_reg <= {rd_fifo_holding_reg[6:0],1'b0};
        end          
        
        // tick the read counter at the rising edge
        if (cs_read_reg) rd_bit_counter <= {3{1'b0}};
        else if (SCLK_RISING) rd_bit_counter <= rd_bit_counter + 1;

        // start read counter at 1
        if (!rx_reading_packet) rx_read_counter <= 12'd1;
        // increment at final sclk rising
        else if (FINAL_SCLK_RISING) rx_read_counter <= rx_read_counter + 1;
        
        rx_read_will_terminate <= (rx_read_counter == {available_packet_count,3'b000});        
                
        if (rd_fifo_read)
            rd_fifo_next_sclk <= 0;
        else if ((rx_reading_packet && !rx_reading_packet_rereg) || (SCLK_FALLING && rd_bit_counter == 2'b00 && !rx_read_will_terminate))
            rd_fifo_next_sclk <= 1;

        rd_fifo_read <= SCLK_RISING && rd_fifo_next_sclk;

    end

    generate
        if (DEBUG == "TRUE") begin : DBG
            // ok we need to probe this crap better now
            // we need
            // packet_count_valid       1
            // available_packet_count   9
            // read_packet_count        1
            // interrupt                1
            // rx_reading_packet        1
            // rx_read_counter          12
            // rd_fifo_holding_reg      8
            // sclk                     1
            // mosi                     1
            // miso                     1
            // cs_b                     2
            hsk_ila u_ila(.clk(aclk),
                          .probe0(packet_count_valid),
                          .probe1(available_packet_count),
                          .probe2(read_packet_count),
                          .probe3(interrupt),
                          .probe4(rx_reading_packet),
                          .probe5(rx_read_counter),
                          .probe6(rd_fifo_holding_reg),
                          .probe7(sclk),
                          .probe8(rd_fifo_next_sclk),
                          .probe9(miso),
                          .probe10(cs_b),
                          .probe11(rx_state)
                          );
        end
    endgenerate

    udp_hsk_rxcount u_rxcountfifo(.clk(aclk),.srst(!aresetn),
                                  .din(packet_qword_counter),
                                  .full(packet_count_full),
                                  .wr_en(write_packet_count),
                                  .dout(available_packet_count),
                                  .valid(packet_count_valid),
                                  .rd_en(read_packet_count));
                                  
    udp_hsk_rxfifo u_rxfifo(.clk(aclk),.srst(!aresetn),
                            .full(wr_fifo_full),
                            .din(wr_fifo_data),
                            .wr_en(wr_fifo_write),
                            .wr_data_count(wr_data_count),
                            .empty(rd_fifo_empty),
                            .dout(rd_fifo_data),
                            .rd_en(rd_fifo_read));

    assign s_udphdr_tready = (rx_state == RX_IDLE);    
    assign miso = rd_fifo_holding_reg[7];
    assign irq_o = interrupt;  
    assign complete_o = complete;
        
endmodule

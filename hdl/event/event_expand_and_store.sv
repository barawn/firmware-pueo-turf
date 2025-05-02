`timescale 1ns / 1ps
// takes a stream of 64 bits and expands to 512 bits.
// nominally we do this by expanding to 192, doubling, and
// expanding 12->16. however this module also allows
// for just 64 -> 512 by just taking 8 in (uses a different
// FIFO).
`include "interfaces.vh"
module event_expand_and_store(
        input clk,
        input rst,
        input [63:0] payload_i,
        input        payload_valid_i,
        input        payload_last_i,
        output       space_avail_o,
        `HOST_NAMED_PORTS_AXI4S_IF( m_axis_ , 512 )
    );
    parameter EXPAND_DATA = "TRUE";
    parameter DEBUG = "TRUE";

    // this remaps the incoming data so that it stacks correctly
    //remap [0  +: 12] = [48 +: 4], [56 +: 8] 000
    //remap [12 +: 12] = [40 +: 8], [52 +: 4] 001
    //remap [24 +: 12] = [24 +: 4], [32 +: 8] 001
    //remap [36 +: 12] = [16 +: 8], [28 +: 4] 002
    //remap [48 +: 12] = [0 +: 4], [8 +: 8] 002
    //remap [60 +: 4] = [4 +: 4] 3    
    function [63:0] remap_data;
        input [63:0] data_in;
        begin
            remap_data[0 +: 12]  = {data_in[48 +: 4], data_in[56 +: 8] };
            remap_data[12 +: 12] = {data_in[40 +: 8], data_in[52 +: 4] };
            remap_data[24 +: 12] = {data_in[24 +: 4], data_in[32 +: 8] };
            remap_data[36 +: 12] = {data_in[16 +: 8], data_in[28 +: 4] };
            remap_data[48 +: 12] = {data_in[00 +: 4], data_in[08 +: 8] };
            remap_data[60 +: 04] = data_in[4 +: 4];
        end
    endfunction

    // yes yes yes this is overloading this name. DEAL WITH IT.
    wire [63:0] payload = remap_data(payload_i);

    // this is the expansion from 12->16. 32 samples, so loop
    function [511:0] expand_data;
        input [383:0] pack_in;
        integer i;
        begin
            for (i=0;i<32;i=i+1) begin
                expand_data[16*i +: 16] = { {4{1'b0}}, pack_in[12*i +: 12] };
            end
        end
    endfunction

    generate
        if (EXPAND_DATA == "TRUE") begin : EXP
            reg [127:0] payload_storage = {128{1'b0}};
            // Remapping above makes payload equal to:
            // sample[5][11:8], sample[4], sample[3], sample[2], sample[1], sample[0]
            // So we can literally just stack them now.
            // (192 bits = 16 samples @ 12 bits)
            // we're trying to feed in 192 bits at a time (every 3 clocks
            // feed control goes
            // clk  valid   feed_control
            // 0    0       00
            // 1    1       00
            // 2    1       01
            // 3    1       11
            // 4    1       00
            // etc.
            reg [1:0] feed_control = {2{1'b0}};
            wire      fifo_last = (payload_last_i && feed_control[1]);
            
            // FIFO FOR EXPANDING FROM 192->384
            // WE REORDER THINGS HERE SO THAT THE FIRST SAMPLE IS LOWEST ADDRESS
            wire [192:0] fifo_in_data = { payload_last_i, payload, payload_storage };
// This was all wrong from when I thought the data was coming in first sample first
// We now remap it so that first sample in payload is [11:0] (when it's aligned obviously).
//            assign fifo_in_data[0   +:  12] = payload_storage[116 +: 12];
//            assign fifo_in_data[12  +:  12] = payload_storage[104 +: 12];
//            assign fifo_in_data[24  +:  12] = payload_storage[ 92 +: 12];
//            assign fifo_in_data[36  +:  12] = payload_storage[ 80 +: 12];
//            assign fifo_in_data[48  +:  12] = payload_storage[ 68 +: 12];
//            assign fifo_in_data[60  +:  12] = payload_storage[ 56 +: 12];
//            assign fifo_in_data[72  +:  12] = payload_storage[ 44 +: 12];
//            assign fifo_in_data[84  +:  12] = payload_storage[ 32 +: 12];
//            assign fifo_in_data[96  +:  12] = payload_storage[ 20 +: 12];
//            assign fifo_in_data[108 +:  12] = payload_storage[ 08 +: 12];
//            assign fifo_in_data[120 +:  12] = {payload_storage[ 0 +: 8], payload[60 +: 4] };
//            assign fifo_in_data[132 +:  12] = payload[48 +: 12];
//            assign fifo_in_data[144 +:  12] = payload[36 +: 12];
//            assign fifo_in_data[156 +:  12] = payload[24 +: 12];
//            assign fifo_in_data[168 +:  12] = payload[12 +: 12];
//            assign fifo_in_data[180 +:  12] = payload[0 +: 12];
            // I dunno why I ever thought I needed to qualify this
//            assign fifo_in_data[192] = payload_last_i;
            wire         fifo_in_write = feed_control[1];
            wire         fifo_in_full; // pointless but leave for debugging
            wire         fifo_in_prog_full; // if set, don't have space for a chunk readout
            assign       space_avail_o = !fifo_in_prog_full;
            
            wire [385:0] fifo_out_data;
            // FIFO orderings when width expanding is always
            // { oldest, newest } and we want
            // { newest, oldest } - so flop again here, jumping over tlast
            wire [383:0] fifo_out_payload = { fifo_out_data[0 +: 192], fifo_out_data[193 +: 192] };            
            // repack
            wire [1:0]   fifo_out_last = { fifo_out_data[192], fifo_out_data[385] };
            wire         fifo_out_valid;
            wire         fifo_out_read;
            
            always @(posedge clk) begin : EXP_LOGIC
                if (rst) feed_control <= {2{1'b0}};
                else begin
                    feed_control[0] <= payload_valid_i && !feed_control[1];
                    feed_control[1] <= payload_valid_i && (feed_control[1:0] == 2'b01);
                end
                // We want the newest data at the TOP bits so we need to shift RIGHT
                if (payload_valid_i)
                    payload_storage <= { payload, payload_storage[64 +: 64] };
            end
            event_in_dm_fifo u_fifo(.clk(clk),
                                    .srst(rst),
                                    .din(fifo_in_data),
                                    .wr_en(fifo_in_write),
                                    .full(fifo_in_full),
                                    .prog_full(fifo_in_prog_full),
                                    .dout(fifo_out_data),
                                    .rd_en(fifo_out_read),
                                    .valid(fifo_out_valid));
                                    
            if (DEBUG == "TRUE") begin : ILA
                expander_ila u_ila(.clk(clk),
                                   .probe0(payload_valid_i),
                                   .probe1(fifo_out_valid),
                                   .probe2(payload),
                                   .probe3(m_axis_tdata),
                                   .probe4(feed_control));
            end                                   
            assign m_axis_tdata = expand_data(fifo_out_payload);
            assign m_axis_tvalid = fifo_out_valid;
            assign m_axis_tlast = fifo_out_last[1];
            assign fifo_out_read = m_axis_tvalid && m_axis_tready;
        end else begin : NEXP
            wire [64:0] fifo_in_data = { payload_last_i, payload_i };
            wire [519:0] fifo_out_data;
            wire         fifo_in_prog_full;
            
            assign       space_avail_o = !fifo_in_prog_full;
            
            // note that a SURF chunk is normally 384 x 64 bits,
            // = 2 x 1024 x 12 = 24,576
            // which is still just 48x512 so we can just grab the top TLAST.
            wire [7:0] fifo_out_last = { fifo_out_data[65*7 + 64],
                                         fifo_out_data[65*6 + 64],
                                         fifo_out_data[65*5 + 64],
                                         fifo_out_data[65*4 + 64],
                                         fifo_out_data[65*3 + 64],
                                         fifo_out_data[65*2 + 64],
                                         fifo_out_data[65*1 + 64],
                                         fifo_out_data[65*0 + 64] };
            assign m_axis_tdata = { fifo_out_data[65*7 +: 64],
                                    fifo_out_data[65*6 +: 64],
                                    fifo_out_data[65*5 +: 64],
                                    fifo_out_data[65*4 +: 64],
                                    fifo_out_data[65*3 +: 64],
                                    fifo_out_data[65*2 +: 64],
                                    fifo_out_data[65*1 +: 64],
                                    fifo_out_data[65*0 +: 64] };
            assign m_axis_tlast = fifo_out_last[7];
            event_in_dm_fifo_noexpand u_fifo(.clk(clk),
                                             .srst(rst),
                                             .din(fifo_in_data),
                                             .wr_en(payload_valid_i),
                                             .prog_full(fifo_in_prog_full),
                                             .dout(fifo_out_data),
                                             .valid(m_axis_tvalid),
                                             .rd_en(m_axis_tvalid && m_axis_tready));                                   
        end
    endgenerate        

    assign m_axis_tkeep = {64{1'b1}};
endmodule

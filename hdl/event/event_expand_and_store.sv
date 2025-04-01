`timescale 1ns / 1ps
// takes a stream of 64 bits and expands to 512 bits.
// nominally we do this by expanding to 192, doubling, and
// expanding 12->16. however this module also allows
// for just 64 -> 512 by just taking 8 in (uses a different
// FIFO).
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
            reg [1:0] feed_control = {2{1'b0}};
            reg       fifo_last = 0;
            
            // FIFO FOR EXPANDING FROM 192->384
            wire [192:0] fifo_in_data = { fifo_last, payload_storage, payload_i };
            wire         fifo_in_write = feed_control[1];
            wire         fifo_in_full; // pointless but leave for debugging
            wire         fifo_in_prog_full; // if set, don't have space for a chunk readout
            
            wire [385:0] fifo_out_data;
            // skip over tlasts...
            wire [383:0] fifo_out_payload = { fifo_out_data[193 +: 192], fifo_out_data[0 +: 192] };
            // repack
            wire [1:0]   fifo_out_last = { fifo_out_data[385], fifo_out_data[192] };
            wire         fifo_out_valid;
            wire         fifo_out_read;
            
            always @(posedge clk) begin : EXP_LOGIC
                if (rst) feed_control <= {2{1'b0}};
                else begin
                    feed_control[0] <= payload_valid_i && !feed_control[1];
                    feed_control[1] <= payload_valid_i && (feed_control[1:0] == 2'b01);
                end
                if (payload_valid_i)
                    payload_storage <= { payload_storage[63:0], payload_i };
                fifo_last <= (feed_control[1] && payload_last_i );                        
            end
            event_in_dm_fifo u_fifo(.clk(clk),
                                    .srst(rst),
                                    .din(fifo_in_data),
                                    .wr_en(fifo_in_write),
                                    .full(fifo_in_full),
                                    .prog_full(space_avail_o),
                                    .dout(fifo_out_data),
                                    .rd_en(fifo_out_read),
                                    .valid(fifo_out_valid));
            assign m_axis_tdata = expand_data(fifo_out_payload);
            assign m_axis_tvalid = fifo_out_valid;
            assign m_axis_tlast = fifo_out_last;
            assign fifo_out_read = m_axis_tvalid && m_axis_tready;
        end else begin : NEXP
            wire [64:0] fifo_in_data = { payload_last_i, payload_i };
            wire [519:0] fifo_out_data;
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
                                             .prog_full(space_avail_o),
                                             .dout(fifo_out_data),
                                             .valid(m_axis_tvalid),
                                             .rd_en(m_axis_tvalid && m_axis_tready));                                   
        end
    endgenerate        

    assign m_axis_tkeep = {64{1'b1}};
endmodule

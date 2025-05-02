`timescale 1ns / 1ps
// sigh xilinx stupidity
`define DLYFF #0.1
`include "interfaces.vh"
`include "uram.vh"
// Stores/rearranges events from a TURFIO.
// This has been worked/reworked/rereworked a ton, but to speed
// things up we're just going to sacrifice a bit of transfer
// speed for simplicity. The TURFIO needs to combine the
// SURF streams to push into the data interface, and *by far*
// the easiest way to do that is to just concatenate them
// and ignore the top (8th byte) for now.
//
// On the TURF side this makes things a little more awkward,
// but what we're going to do is:
// 1. Widen each incoming SURF data stream by 2. The events are always multiples
//    of 8 words anyway.
// 2: FIFO for each incoming SURF data stream (siphoning off the header words)
//    which also widens them. Each SURF fundamentally generates 1.5 x 1024
//    data bytes = 1536 bytes/ch. If we expand it to 64 bit chunks (8 bytes) this
//    is 192 chunks/SURF.
// 3: URAM bank to store channels temporarily. We don't need to store a full
//    event since we can empty faster than we fill. But we do want to be able to
//    store a decent amount of data.
//    So imagine SURF1 gets 0-383, SURF2 gets 384-767, SURF3 gets 1151,
//    SURF4 gets 1152-1535, SURF5 gets 1536-1919, SURF6 gets 1920-2303.
//    We use 2 URAMs in cascade and bounce the addresses.
// 4: On the memclk side (readout of URAM) we then need to expand to 512 bits
//    and buffer for the datamover. This will take 8 BRAMs, but we only need
//    ONE per TURFIO because the readout bandwidth is FASTER than the write.
//    
//    Consider the overall maximum bandwidth:
//    - 7x SURFs (max) x 8 bits x 62.5 MHz (max) = 3.5 Gbps
//    - This means each FIFO for the SURF stream can generate at most
//      1 64-bit word every 16 clocks. There are 7 SURFs (max)
//      so this means the rate *into* the URAM is 7 64-bit writes every 16
//      clocks.
//    - This means that a full chunk (words 0 to 2303) takes (16/7)*2304*8
//      = 42.130 us.
//    - On the URAM readout side, we can read out a full 64-bit word every
//      clock, running at 300 MHz. This can dump a full chunk in 2304*(10/3)
//      = 7.680 us. 
//    - So the readout bandwidth is well above the fill rate, and we don't need
//      to worry. If we DO end up needing to worry we can use the URAMs a bit
//      more efficiently to gain a third buffer (so an additional 42 us of readout
//      time).
//
module turfio_event_accumulator(
        input aclk,
        input aresetn,
        
        input memclk,
        input memresetn,
        // Input data stream.
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_axis_ , 32 ),
        input s_axis_tlast,
        // Header data. This STAYS in aclk!
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_hdr_ , 64 ),
        output m_hdr_tlast,

        // READ OUTPUT. This is NO LONGER an AXI4-Stream interface.
        output [63:0] payload_o,
        output [5:0]  payload_ident_o,
        output        payload_valid_o,
        output        payload_last_o,
        input         payload_has_space_i,

        // error tracks
        output [1:0] errdet_aclk_o,
        output [0:0] errdet_memclk_o
    );

    parameter DEBUG = "TRUE";        
    // first expand to 64 bits. This will always work because on the
    // TURFIO side we bounce between S0/S3 and S4/S6+TIO so we ALWAYS
    // have an even set of words. 
    `DEFINE_AXI4S_MIN_IF( in64_ , 64 );
    wire [7:0] in64_tkeep;
    wire in64_tlast;
    // we splice in a tdest: 0 = header, 1 = payload
    wire in64_tdest;

    // this is BEFORE the mux. we combine with the header tlast.
    wire in64_tlast_premux;
    wire indata_width_err = (in64_tkeep[4] != in64_tkeep[0]) && in64_tvalid && in64_tready;
    reg indata_width_err_seen = 0;

    // axi spec is LSB first so this does what we want:
    // if we have
    // clk  in  out
    // 0    AA  XX
    // 1    BB  BBAA
    // so that means our output stream can be split up
    // [7:0] = surf1
    // [15:8] = surf2
    // etc. etc. and the top byte [63:56] is unused (TURFIO)
    axis_32to64 u_widener(.aclk(aclk),
                          .aresetn(aresetn),
                          `CONNECT_AXI4S_MIN_IF( s_axis_ , s_axis_ ),
                          .s_axis_tlast(s_axis_tlast),
                          `CONNECT_AXI4S_MIN_IF( m_axis_ , in64_ ),
                          .m_axis_tkeep(in64_tkeep),
                          .m_axis_tlast(in64_tlast_premux));
    // ok, now that we're at 64, we can split off the headers and data.
    // for this we need a small data counter. we might need to have something
    // check total length later too.
    // each SURF generates 4 data bytes for a header.
    reg in_payload = 0;
    reg [1:0] header_counter = {2{1'b0}};
    // data counter, to flag errors. our datapath length should be
    // 12,292 so need a 14 bit counter
    reg [13:0] indata_length_counter = 0;
    reg indata_target = 0;
    reg indata_length_err_seen = 0;
    

    always @(posedge aclk) begin
        if (in64_tvalid && in64_tready) begin
            if (in64_tlast_premux) in_payload <= `DLYFF 0;
            else if (header_counter == 3) in_payload <= `DLYFF 1;
            
            if (in_payload) header_counter <= `DLYFF 0;
            else header_counter <= `DLYFF header_counter + 1;
            
            if (in64_tlast_premux) indata_length_counter <= `DLYFF {14{1'b0}};
            else indata_length_counter <= `DLYFF indata_length_counter + 1;
            
            // goes high on word 12291 = last word
            indata_target <= `DLYFF (indata_length_counter == 14'd12290);
        end        
        if (!aresetn) begin
            indata_length_err_seen <= `DLYFF 1'b0;
            indata_width_err_seen <= `DLYFF 1'b0;
        end else if (in64_tvalid && in64_tready) begin
            if (indata_target && !in64_tlast_premux)
                indata_length_err_seen <= `DLYFF 1'b1;
            if (indata_width_err)
                indata_width_err_seen <= `DLYFF 1'b1;
        end
    end

    // splice in the tdest
    assign in64_tdest = in_payload;
    // generate the tlast
    assign in64_tlast = (!in_payload && header_counter == {2{1'b1}}) || in64_tlast_premux;

    // now the demux peels off the data, and header goes out of module
    `DEFINE_AXI4S_MIN_IF( data64_ , 64);
    wire data64_tlast;
    
    axis_demux #(.M_COUNT(2),.DATA_WIDTH(64),
                 .KEEP_ENABLE(0),.ID_ENABLE(0),.DEST_ENABLE(1),.M_DEST_WIDTH(0),
                 .USER_ENABLE(0),.TDEST_ROUTE(1))
        u_hdrdata_demux(.clk(aclk),.rst(!aresetn),
                         `CONNECT_AXI4S_MIN_IF( s_axis_ , in64_ ),
                         .s_axis_tlast(in64_tlast),
                         .s_axis_tdest(in64_tdest),
                         // can't use macros
                         .m_axis_tdata( { data64_tdata , m_hdr_tdata } ),
                         .m_axis_tvalid({ data64_tvalid, m_hdr_tvalid} ),
                         .m_axis_tready({ data64_tready, m_hdr_tready} ),
                         .m_axis_tlast( { data64_tlast,  m_hdr_tlast } ),
                         
                         .enable(1'b1),
                         .drop(1'b0),
                         .select(1'b0));

    // We now take data64 and shove it into 7 separate FIFOs which
    // will also widen to 64 bits each and clock-cross.

    // here are the output vec streams. we kinda blindly assume everything's
    // OK there, so no tlasts or anything.
    `DEFINE_AXI4S_MIN_IFV( surf_ , 64, [7:0] );
    
    wire [7:0] surf_fifo_full;
    wire [7:0] surf_fifo_almost_empty;
    assign     surf_fifo_full[7] = 1'b0;
    // these are all just to make sims happy
    assign     surf_tvalid[7] = 1'b1;
    assign     surf_fifo_almost_empty[7] = 1'b0;
    assign     surf_tdata[7] = {64{1'b0}};
    
    assign     data64_tready = &(~surf_fifo_full);
    generate
        genvar i;
        for (i=0;i<7;i=i+1) begin : CCF
            wire [7:0] fifo_din = data64_tdata[8*i +: 8];

            surf_fifo u_fifo(.rst(!aresetn),
                             .wr_clk(aclk),
                             .din(fifo_din),
                             .full(surf_fifo_full[i]),
                             .wr_en(data64_tready && data64_tvalid),
                             .rd_clk(memclk),
                             .dout(surf_tdata[i]),
                             .valid(surf_tvalid[i]),
                             .almost_empty(surf_fifo_almost_empty[i]),
                             .rd_en(surf_tready[i] && surf_tvalid[i]));
        end
    endgenerate                          

    // Once out of the SURF FIFO, we now need a state machine to bounce
    // between the values and store them properly into the URAM buffer.

    // MOVE THIS TO AN INCLUDE
    // The issue here is that for the cascade we need to pass a bunch of signals:
    // cas_X_addr_Y
    // cas_X_bwe_Y
    // cas_X_dbiterr_Y
    // cas_X_din_Y
    // cas_X_dout_Y
    // cas_X_en_Y
    // cas_X_rdaccess_Y
    // cas_X_rdb_wr_Y
    // cas_X_sbiterr_Y
    // In other cases we connect A Bunch so it's easier to clean up.
    // Here we need a length of 2, we terminate the inputs to 0 and leave
    // the outputs of 1 unconnected, and then use the hookup helper
    // to connect the outputs of 0 to the inputs of 1.
    `DEFINE_URAM_FULL_CASCADE_VEC( casc_ , 2 );
    `HOOKUP_URAM_CASCADE( casc_ , casc_ , a,  [1], [0] );
    `HOOKUP_URAM_CASCADE( casc_ , casc_ , b,  [1], [0] );
    `TERMINATE_URAM_CASCADE_INPUT( casc_ , a, [0] );
    `TERMINATE_URAM_CASCADE_INPUT( casc_ , b, [0] );
    // unused 1 outputs can be left alone
    wire uram_en_write;
    // we're going to try just demultiplexing by 7
    // straight off. If this isn't fast enough we can try
    // other methods.
    reg [63:0] uram_write_data = {64{1'b0}};
    wire [71:0] uram_write_data_in = { {8{1'b0}}, uram_write_data };
    // uram address.
    reg [11:0] uram_write_addr = {12{1'b0}};
    // sample counter
    reg [8:0] write_sample_counter = {9{1'b0}};
    // chunk counter. there are 4 chunks of 2 channels per event
    // the low bit of this is used for the URAM bank (top address)
    // the chunk counter does get pushed into a FIFO to queue up the readout
    reg [1:0] write_chunk_counter = {2{1'b0}};
    wire [22:0] uram_full_write_addr = { {10{1'b0}}, 
                                         write_chunk_counter[0], 
                                         uram_write_addr };
    // and readout side.
    reg uram_en_read = 0;
    // out of the FIFO
    wire [1:0] read_chunk_counter_next;
    // valid from fifo
    wire read_chunk_counter_valid;
    // stored
    reg [1:0] read_chunk_counter = {2{1'b0}};
    // now this goes straight linear up to 2687.
    reg [11:0] uram_read_addr = {12{1'b0}};
    // whatever, just sleaze this
    reg [8:0] uram_read_sample_count = {9{1'b0}};
    // full read addr
    wire [22:0] uram_full_read_addr = { {10{1'b0}},
                                        read_chunk_counter[0],
                                        uram_read_addr };
    // out of URAM
    wire [71:0] uram_read_data_out;
    // last indicator will go on the next clock
    reg         uram_will_tlast = 0;
    // last indicator for the datamover
    reg         uram_tlast = 0;
    // surf counter - helps with the datamover
    reg [2:0]   uram_read_surf_counter = {3{1'b0}};    
    
    // uram bank full indicators, for our new Ultra Simple backpressure
    reg [1:0]   uram_bank_is_full = {2{1'b0}};
    // these indicate that the bank should be cleared
    reg [1:0]   uram_bank_clear = {2{1'b0}};
    
    // overflow indicator    
    reg         uram_read_overflow_seen = 0;
    
    localparam FSM_BITS = 4;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] PREP_0 = 1;
    localparam [FSM_BITS-1:0] WRITE_0_PREP_1 = 2;
    localparam [FSM_BITS-1:0] WRITE_1_PREP_2 = 3;
    localparam [FSM_BITS-1:0] WRITE_2_PREP_3 = 4;
    localparam [FSM_BITS-1:0] WRITE_3_PREP_4 = 5;
    localparam [FSM_BITS-1:0] WRITE_4_PREP_5 = 6;
    localparam [FSM_BITS-1:0] WRITE_5_PREP_6 = 7;
    localparam [FSM_BITS-1:0] WRITE_6_PREP_0_OR_PREFINISH = 8;
    localparam [FSM_BITS-1:0] SIGNAL_READOUT = 9;
    localparam [FSM_BITS-1:0] PAUSE = 10;
    reg [FSM_BITS-1:0] state = IDLE;

    assign uram_en_write = (state == WRITE_0_PREP_1 ||
                            state == WRITE_1_PREP_2 ||
                            state == WRITE_2_PREP_3 ||
                            state == WRITE_3_PREP_4 ||
                            state == WRITE_4_PREP_5 ||
                            state == WRITE_5_PREP_6 ||
                            state == WRITE_6_PREP_0_OR_PREFINISH);
    assign surf_tready[0] = (state == WRITE_0_PREP_1);
    assign surf_tready[1] = (state == WRITE_1_PREP_2);
    assign surf_tready[2] = (state == WRITE_2_PREP_3);
    assign surf_tready[3] = (state == WRITE_3_PREP_4);
    assign surf_tready[4] = (state == WRITE_4_PREP_5);
    assign surf_tready[5] = (state == WRITE_5_PREP_6);
    assign surf_tready[6] = (state == WRITE_6_PREP_0_OR_PREFINISH);        
    // make sim happy
    assign surf_tready[7] = 1'b0;
    // the overall sequence looks like:
    // clk      state       surf_tvalid[0]  sample_counter  uram_addr   chunk_counter
    // 0        IDLE        1               0               0           0
    // 1        PREP_0      1               0               0           0
    // 2        W0P1        0               0               0           0
    // 3        W1P2        0               0               384         0
    // 4        W2P3        0               0               768         0
    // 5        W3P4        0               0               1152        0
    // 6        W4P5        0               0               1536        0
    // 7        W5P6        0               0               1920        0
    // 8        W6P0        1               1               2304        0
    // 9        W0P1        0               1               1           0
    // 10       W1P2        0               1               385         0
    // .
    // 16       W6P0        1               2               2305        0
    // .
    // 3071     W5P6        0               383             2303        0
    // 3072     W6PF        1               0               2687        0
    // 3073     SR          1               0               0           0
    // 3074     PREP_0      1               0               0           1
    // ..
    // 6143     W5P6        0               383             2303        1
    // 6144     W6PF        1               0               2687        1
    // 6145     SR          1               0               0           1
    // 6146     PREP_0      1               0               0           2
    // ..
    // 12287    W5P6        0               383             2303        3
    // 12288    W6PF        0               0               2687        3
    // 12289    SR          0               0               0           3
    // 12290    IDLE    
    // pretty easy, just hope we can do it at MEMCLK SPEED
    // .... otherwise we might *write* at half and readout at full
    // since the readout logic is simpler. which means MORE MULTICYCLE PATHS
    // OH JOY
    
    // OKAY THIS IS EFFING STUPID
    // THIS IS *WAY* TOO HARD
    // We need to think about this a bit:
    // if instead of just valid, we also add almost_empty, we'll actually
    // be able to run full-speed:
    // in prep_0 wait for everyone valid
    // in write_6_prep_0_or_prefinish if [5:0] valid && ![6] almost empty,
    // jump to write_0_prep_1 otherwise jump to prep_0.
    // Then we can just go straight through each stage, and use the stage
    // as the tready. We can blind capture in each one too because worst
    // case we just keep recapturing in prep_0 until it really is valid.
    //
    // We can't use reduction ops since these aren't multibit, they're arrayed
    // (e.g. wire blah[7:0] not wire [7:0] blah)

    // so here's what we check in prep_0.
    wire all_valid = (surf_tvalid[0] && surf_tvalid[1] && surf_tvalid[2] &&
                      surf_tvalid[3] && surf_tvalid[4] && surf_tvalid[5] &&
                      surf_tvalid[6]);
    // and here's what we check in w6p0oPF
    wire all_next_valid = 
                     (surf_tvalid[0] && surf_tvalid[1] && surf_tvalid[2] &&
                      surf_tvalid[3] && surf_tvalid[4] && surf_tvalid[5] &&
                      !surf_fifo_almost_empty[6]);
                      
    always @(posedge memclk) begin    
        if (!memresetn) uram_read_overflow_seen <= `DLYFF 0;
        else begin
            // read overflows happen when the SURF fifo fills up. Capture
            // that here.
        end

        // the order here doesn't matter, it won't start until one's clear anyway.
        if (uram_bank_clear[0]) uram_bank_is_full[0] <= 1'b0;
        else if (!write_chunk_counter[0] && uram_en_write) uram_bank_is_full[0] <= 1'b1;
        if (uram_bank_clear[1]) uram_bank_is_full[1] <= 1'b0;
        else if (write_chunk_counter[0] && uram_en_write) uram_bank_is_full[1] <= 1'b1;        
        
        if (!memresetn) state <= `DLYFF IDLE;
        else begin
            case (state)
                // We need to check bank availability in 3 states: IDLE, SIGNAL_READOUT, and PAUSE.
                IDLE: if (surf_tvalid[0] && !uram_bank_is_full[0]) state <= `DLYFF PREP_0;
                PREP_0: if (all_valid) state <= `DLYFF WRITE_0_PREP_1;
                WRITE_0_PREP_1: state <= `DLYFF WRITE_1_PREP_2;
                WRITE_1_PREP_2: state <= `DLYFF WRITE_2_PREP_3;
                WRITE_2_PREP_3: state <= `DLYFF WRITE_3_PREP_4;
                WRITE_3_PREP_4: state <= `DLYFF WRITE_4_PREP_5;
                WRITE_4_PREP_5: state <= `DLYFF WRITE_5_PREP_6;
                WRITE_5_PREP_6: state <= `DLYFF WRITE_6_PREP_0_OR_PREFINISH;
                WRITE_6_PREP_0_OR_PREFINISH: begin
                    if (write_sample_counter == 0)
                        state <= `DLYFF SIGNAL_READOUT;
                    else begin
                        if (all_next_valid) state <= `DLYFF WRITE_0_PREP_1;
                        else state <= `DLYFF PREP_0;
                    end
                end
                // Here we have to be smarter since we're flipping the
                // uram bank. So check uram_bank_is_full[~write_chunk_counter[0]],
                // otherwise go to pause. There we can just check directly.
                // Note that this is ALWAYS (!!!) a flag! We always exit it
                // in one clock!
                SIGNAL_READOUT: begin
                    if (write_chunk_counter == 2'd3) state <= `DLYFF IDLE;
                    else begin
                        if (!uram_bank_is_full[~write_chunk_counter[0]])
                            state <= `DLYFF PREP_0;
                        else
                            state <= `DLYFF PAUSE;
                    end
                end
                // We flipped the chunk counter in SIGNAL_READOUT.
                PAUSE: if (!uram_bank_is_full[write_chunk_counter[0]])
                            state <= `DLYFF PREP_0;
            endcase
        end
        if (state == IDLE) 
            write_sample_counter <= `DLYFF 0;
        else if (state == WRITE_5_PREP_6) begin
            if (write_sample_counter == 383)
                write_sample_counter <= `DLYFF 0;
            else
                write_sample_counter <= `DLYFF write_sample_counter + 1;
        end
            
        if (state == IDLE)
            write_chunk_counter <= `DLYFF {2{1'b0}};
        else if (state == SIGNAL_READOUT)
            write_chunk_counter <= `DLYFF write_chunk_counter + 1;
            
        if (state == IDLE)
            uram_write_addr <= `DLYFF {12{1'b0}};
        else if (state == WRITE_6_PREP_0_OR_PREFINISH)
            uram_write_addr <= `DLYFF write_sample_counter;
        else if (state == WRITE_0_PREP_1 ||
                 state == WRITE_1_PREP_2 ||
                 state == WRITE_2_PREP_3 ||
                 state == WRITE_3_PREP_4 ||
                 state == WRITE_4_PREP_5 ||
                 state == WRITE_5_PREP_6)
            uram_write_addr <= `DLYFF uram_write_addr + 384;            

        if (state == WRITE_0_PREP_1)
            uram_write_data <= `DLYFF surf_tdata[1];
        else if (state == WRITE_1_PREP_2)
            uram_write_data <= `DLYFF surf_tdata[2];
        else if (state == WRITE_2_PREP_3)
            uram_write_data <= `DLYFF surf_tdata[3];
        else if (state == WRITE_3_PREP_4)
            uram_write_data <= `DLYFF surf_tdata[4];
        else if (state == WRITE_4_PREP_5)
            uram_write_data <= `DLYFF surf_tdata[5];
        else if (state == WRITE_5_PREP_6)
            uram_write_data <= `DLYFF surf_tdata[6];
        else
            uram_write_data <= `DLYFF surf_tdata[0];          
            
        // reading isn't that much harder now - we just hold off setting 1 until space is available
        if (uram_tlast && uram_read_surf_counter == 6) uram_en_read <= `DLYFF 0;
        else if (read_chunk_counter_valid && payload_has_space_i) uram_en_read <= `DLYFF 1;

        // clearing is just the same thing that clears en_read
        uram_bank_clear[0] <= (uram_will_tlast && uram_read_surf_counter == 6 && ~read_chunk_counter[0]);
        uram_bank_clear[1] <= (uram_will_tlast && uram_read_surf_counter == 6 && read_chunk_counter[0]);
        
        if (uram_tlast || !uram_en_read) uram_read_sample_count <= `DLYFF {9{1'b0}};
        else if (uram_en_read) uram_read_sample_count <= `DLYFF uram_read_sample_count + 1;
        
        uram_will_tlast <= `DLYFF (uram_read_sample_count == 381);
        uram_tlast <= `DLYFF uram_will_tlast;
        
        if (!uram_en_read) uram_read_addr <= `DLYFF {12{1'b0}};
        else uram_read_addr <= `DLYFF uram_read_addr + 1;
        
        if (!uram_en_read) uram_read_surf_counter <= `DLYFF {3{1'b0}};
        else if (uram_tlast) uram_read_surf_counter <= `DLYFF uram_read_surf_counter + 1;
        
        if (!uram_en_read && read_chunk_counter_valid)
            read_chunk_counter <= `DLYFF read_chunk_counter_next;
    end     

    // 4 bit state
    // 7 bit tready
    // 7 bit tvalid
    // 2 bit write_chunk_counter
    // 9 bit write_sample_counter
    // 2 bit uram_bank_is_full
    // 2 bit uram_bank_clear
    wire [6:0] sv_tready = { surf_tready[6],
                             surf_tready[5],
                             surf_tready[4],
                             surf_tready[3],
                             surf_tready[2],
                             surf_tready[1],
                             surf_tready[0] };
    wire [6:0] sv_tvalid = { surf_tvalid[6],
                             surf_tvalid[5],
                             surf_tvalid[4],
                             surf_tvalid[3],
                             surf_tvalid[2],
                             surf_tvalid[1],
                             surf_tvalid[0] };
    
    generate
        if (DEBUG == "TRUE") begin : ILA
            accumulator_ila u_ila(.clk(memclk),
                                  .probe0(state),
                                  .probe1(sv_tready),
                                  .probe2(sv_tvalid),
                                  .probe3(write_chunk_counter),
                                  .probe4(write_sample_counter),
                                  .probe5(uram_bank_is_full),
                                  .probe6(uram_bank_clear));
        end
    endgenerate    
    
    event_chunk_fifo u_chkfifo( .clk(memclk),
                                .srst(!memresetn),
                                .din(write_chunk_counter),
                                .wr_en(state == SIGNAL_READOUT),
                                .dout(read_chunk_counter_next),
                                .valid(read_chunk_counter_valid),
                                .rd_en(read_chunk_counter_valid && !uram_en_read && payload_has_space_i));
    
    URAM288 #(.EN_AUTO_SLEEP_MODE("FALSE"),
              .CASCADE_ORDER_A("FIRST"),
              .CASCADE_ORDER_B("FIRST"),
              // doesn't actually matter I think but I can tie a byte write low
              .BWE_MODE_A("PARITY_INDEPENDENT"),
              .BWE_MODE_B("PARITY_INDEPENDENT"),
              .SELF_ADDR_A(11'd0),
              .SELF_MASK_A(11'h7FE),
              .SELF_ADDR_B(11'd0),
              .SELF_MASK_B(11'h7FE),
              .OREG_A("FALSE"),
              .OREG_B("TRUE"),
              .REG_CAS_A("TRUE"),
              .REG_CAS_B("TRUE"))
              u_lower_uram( .CLK(memclk),
                            .DIN_A( uram_write_data_in ),
                            .EN_A( uram_en_write ),
                            .RDB_WR_A( 1'b1 ),
                            .BWE_A( { 1'b0, 8'hFF } ),
                            .ADDR_A( uram_full_write_addr ),                            
                            // no data output since that comes from B
                            .EN_B( uram_en_read ),
                            .OREG_CE_B(1'b1),
                            .RDB_WR_B( 1'b0 ),
                            .ADDR_B( uram_full_read_addr ),
                            // cascades
                            `CONNECT_URAM_ACASCIN_VEC( casc_ , [0] ),
                            `CONNECT_URAM_ACASCOUT_VEC( casc_ , [0] ),
                            `CONNECT_URAM_BCASCIN_VEC( casc_ , [0] ),
                            `CONNECT_URAM_BCASCOUT_VEC( casc_ , [0] ),                                                        
                            // unuseds
                            .RST_A( 1'b0 ),
                            .RST_B( 1'b0 ),
                            .SLEEP(1'b0),
                            .OREG_CE_A(1'b0),
                            .DIN_B( {72{1'b0}} ),                            
                            .BWE_B ( {9{1'b0}} ),
                            .OREG_ECC_CE_A(1'b0),
                            .OREG_ECC_CE_B(1'b0),
                            .INJECT_DBITERR_A(1'b0),
                            .INJECT_DBITERR_B(1'b0),
                            .INJECT_SBITERR_A(1'b0),
                            .INJECT_SBITERR_B(1'b0));
    URAM288 #(.EN_AUTO_SLEEP_MODE("FALSE"),
              .CASCADE_ORDER_A("LAST"),
              .CASCADE_ORDER_B("LAST"),
              // doesn't actually matter I think but I can tie a byte write low
              .BWE_MODE_A("PARITY_INDEPENDENT"),
              .BWE_MODE_B("PARITY_INDEPENDENT"),
              .SELF_ADDR_A(11'd1),
              .SELF_MASK_A(11'h7FE),
              .SELF_ADDR_B(11'd1),
              .SELF_MASK_B(11'h7FE),              
              .OREG_A("FALSE"),
              .OREG_B("TRUE"),
              .REG_CAS_A("TRUE"),
              .REG_CAS_B("TRUE"))
              u_upper_uram( .CLK(memclk),
                            .OREG_CE_B(1'b1),
                            .DOUT_B( uram_read_data_out ),
                            `CONNECT_URAM_ACASCIN_VEC( casc_ , [1] ),
                            `CONNECT_URAM_ACASCOUT_VEC( casc_ , [1] ),
                            `CONNECT_URAM_BCASCIN_VEC( casc_ , [1] ),
                            `CONNECT_URAM_BCASCOUT_VEC( casc_ , [1] ),                                                        
                            // unuseds
                            .RST_A( 1'b0 ),
                            .RST_B( 1'b0 ),
                            .SLEEP(1'b0),
                            .OREG_CE_A(1'b0),
                            .DIN_B( {72{1'b0}} ),                            
                            .BWE_B ( {9{1'b0}} ),
                            .OREG_ECC_CE_A(1'b0),
                            .OREG_ECC_CE_B(1'b0),
                            .INJECT_DBITERR_A(1'b0),
                            .INJECT_DBITERR_B(1'b0),
                            .INJECT_SBITERR_A(1'b0),
                            .INJECT_SBITERR_B(1'b0));

    // OK we ALSO will need to delay
    // uram_read_surf_counter
    // uram_read_chunk_counter
    // uram_en_read
    // uram_tlast
    // Sim says 3 clocks: in total we've got
    // 7 bits to delay (5 in tuser, 1 tvalid, 1 tlast).
    localparam URAM_DELAY = 3;
    localparam URAM_DELAY_BITS = 7;
    reg [URAM_DELAY_BITS-1:0] uram_delay_reg = {URAM_DELAY_BITS{1'b0}};
    wire [URAM_DELAY_BITS-1:0] uram_delay_out;
    srlvec #(.NBITS(URAM_DELAY_BITS))
        u_dly(.clk(memclk),
              .ce(1'b1),
              .a(URAM_DELAY-2),
              .din( { read_chunk_counter, uram_read_surf_counter,
                      uram_tlast, uram_en_read } ),
              .dout(uram_delay_out));
    always @(posedge memclk) uram_delay_reg <= `DLYFF uram_delay_out;
    
    assign payload_o = uram_read_data_out[0 +: 64];
    assign payload_valid_o = uram_delay_reg[0];
    assign payload_last_o = uram_delay_reg[1];
    assign payload_ident_o = uram_delay_reg[2 +: 5];
    
    assign errdet_aclk_o = { indata_length_err_seen, indata_width_err_seen };
    assign errdet_memclk_o = { uram_read_overflow_seen };    
endmodule

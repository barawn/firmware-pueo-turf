`timescale 1ns / 1ps
`include "interfaces.vh"
`include "mem_axi.vh"
// headers come in way earlier than everything else so we don't need
// to buffer much. We DO need to buffer the actual trigger data
// but that'll come later.

// THIS IS JUST THE FIRST VERSION WE WILL PROBABLY CHANGE THIS LATER
// BECAUSE IT'S A TON OF REPEATED DATA!!!
module hdr_accumulator(
        // aclk-land
        input aclk,
        input aresetn,
        // if set, fake the stream from the specified 
        // TURFIO. this is so much harder than it needs to be
        // lives in ACLK land
        input [3:0] tio_mask_i,

        // input addresses
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_done_ , 16 ),
        // output completions. here we only need 4 bits + 13 bits,
        // expand to 24 but our FIFO will only be 18 anyway
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_cmpl_, 24 ),        
        
        // turf header input, this needs more buffering
        // god I hope we have enough
        // THE TURF HEADER INPUT **MUST** BE ENOUGH TO FILL
        // EVERYTHING SO HERE IT NEEDS TO BE 16 BEATS LONG!!!
        // 16 * 8 = first 128 bytes
        // NO FIFO IN HERE, IT EXISTS OUTSIDE!!
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_thdr_ , 64 ),        
        input s_thdr_tlast,
        // these end up being 128 bytes total, we put them
        // at 0x80-0xFF.        
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr0_ , 64 ),
        input s_hdr0_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr1_ , 64 ),
        input s_hdr1_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr2_ , 64 ),
        input s_hdr2_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr3_ , 64 ),
        input s_hdr3_tlast,
        // ADD OTHER CRAP LATER
        input memclk,
        input memresetn,
        `M_AXIM_PORT_DW( m_axi_ , 1, 64)
    );
    parameter DEBUG = "TRUE";
    
    // our low 19 bits are fixed, it's 0x4000 back 256.
    localparam [18:0] BASE_ADDR = 19'h03F00;
    
    // each of the TURFIOs needs to go in a FIFO.
    // we also need to have a fake stream generator, which
    // just generates 4 beats high whenever a TURF header
    // last beat is seen.
    `DEFINE_AXI4S_MIN_IFV( tio_ , 64, [3:0]);
    wire [3:0] tio_tlast;
    
    `define AXIS_VASSIGN( to, tosuffix, from )      \
        assign to``tdata``tosuffix = from``tdata;   \
        assign to``tvalid``tosuffix = from``tvalid; \
        assign from``tready = to``tready``tosuffix; \
        assign to``tlast``tosuffix = from``tlast

    `AXIS_VASSIGN( tio_ , [0],  s_hdr0_ );
    `AXIS_VASSIGN( tio_ , [1],  s_hdr1_ );
    `AXIS_VASSIGN( tio_ , [2],  s_hdr2_ );
    `AXIS_VASSIGN( tio_ , [3],  s_hdr3_ );

    // FFS we need a FIFO to store the TURF header bc we use
    // its tlast to generate fake masked TURFIO data.
    `DEFINE_AXI4S_MIN_IF( thdrfifo_ , 64 );
    wire thdrfifo_tlast;
    wire thdrfifo_full;
    assign s_thdr_tready = !thdrfifo_full;
    turf_header_fifo u_turfhdr_fifo(.clk(memclk),
                                    .srst(!memresetn),
                                    .din( { s_thdr_tlast, s_thdr_tdata } ),
                                    .full( thdrfifo_full ),
                                    .wr_en( s_thdr_tvalid && s_thdr_tready ),
                                    .dout( { thdrfifo_tlast, thdrfifo_tdata } ),
                                    .rd_en( thdrfifo_tready && thdrfifo_tvalid ),
                                    .valid( thdrfifo_tvalid ));
                                    
    // We need to generate a flag to indicate when the masked TURFIOs
    // need to start, then clock-cross it to aclk.
    wire start_masked_turfio = s_thdr_tlast && s_thdr_tvalid && s_thdr_tready;
    wire start_masked_turfio_aclk;
    flag_sync u_startsync(.in_clkA(start_masked_turfio),.out_clkB(start_masked_turfio_aclk),
                          .clkA(memclk),.clkB(aclk));

    `DEFINE_AXI4S_MIN_IFV( tiofifo_ , 64, [3:0] );        
    wire [3:0] tiofifo_tlast;
    generate
        genvar i;
        for (i=0;i<4;i=i+1) begin : TL
            reg masked_turfio_valid = 0;
            reg [1:0] masked_turfio_counter = {2{1'b0}};
            wire masked_turfio_tlast = (masked_turfio_counter == 2'd3);            
            wire fifo_full;
            wire fifo_wren;
            wire fifo_last = (!tio_mask_i[i] && tio_tlast[i]) || masked_turfio_tlast;
            // we always just put the data in because we don't care                        
            wire [64:0] fifo_data = { fifo_last, tio_tdata[i] };
            assign tio_tready[i] = (!fifo_full || tio_mask_i[i]);
            assign fifo_wren = (tio_tvalid[i] || masked_turfio_valid) && !fifo_full;
            always @(posedge aclk) begin 
                if (!tio_mask_i[i]) masked_turfio_valid <= 0;
                else if (start_masked_turfio_aclk) masked_turfio_valid <= 1;
                else if (masked_turfio_counter == 2'd3) masked_turfio_valid <= 0;
                
                if (!tio_mask_i[i])
                    masked_turfio_counter <= {2{1'b0}};
                else if (masked_turfio_valid && tio_tready[i])
                    masked_turfio_counter <= masked_turfio_counter + 1;
            end
            wire [64:0] fifo_data_out;
            wire        fifo_valid;
            wire        fifo_rden;
            assign tiofifo_tdata[i] = fifo_data_out[0 +: 64];
            assign tiofifo_tlast[i] = fifo_data_out[64];
            assign tiofifo_tvalid[i] = fifo_valid;
            assign fifo_rden = tiofifo_tvalid[i] && tiofifo_tready[i];
            turfio_hdr_fifo u_hdrfifo( .din(fifo_data),
                                       .wr_en(fifo_wren),
                                       .full(fifo_full),
                                       .wr_clk(aclk),
                                       .rd_clk(memclk),
                                       .srst(!aresetn),
                                       .rd_en(fifo_rden),
                                       .dout(fifo_data_out),
                                       .valid(fifo_valid));
        end
    endgenerate
    
    // ok: so now we have 5 streams all of which will generate
    // a tlast and will combine to 256 words when completed.
    // now use an AXI4-stream combiner and round-robin.
    `DEFINE_AXI4S_IF( tothdr_ , 64 );
    wire [0:0] tothdr_tuser;
    wire tothdr_tlast_raw;
    assign tothdr_tlast = tothdr_tlast_raw && tothdr_tuser[0];
    assign tothdr_tkeep = {8{1'b1}};
    
    `DEFINE_AXI4S_MIN_IF( cmd_ , 72);
    `DEFINE_AXI4S_MIN_IF( stat_ , 8);

    // everyone has data        
    wire everyone_ready = tiofifo_tvalid[0] &&
                          tiofifo_tvalid[1] &&
                          tiofifo_tvalid[2] &&
                          tiofifo_tvalid[3] &&
                          thdrfifo_tvalid;
    
    // data buildup:
    localparam [22:0] HDR_SIZE_BTT = 22'd256;
    wire [31:0] dm_full_address = { s_done_tdata[12:0], BASE_ADDR };
    wire [31:0] dm_lower_command = 
        {   1'b0,   // no realignment
            1'b1,   // EOF = 1
            6'b000000, // DSA = 000000 (unused)
            1'b1,   // type = 1 = incrementing address
            HDR_SIZE_BTT };

    // we can use 4 of these bits for the address to feed out the completions
    // that way we only need a 9 bit distfifo
    // maybe redo this in the turfio req gen
    wire [7:0] dm_upper_byte = { {4{1'b0}}, s_done_tdata[0 +: 4] };
    assign cmd_tdata = { dm_upper_byte, dm_full_address, dm_lower_command };
        
    // just use an axis_mux since we don't need an arbitrator
    reg [2:0] stream_select = {3{1'b0}};
    wire [4:0] stream_last_beat = { 
        tiofifo_tvalid[3] && tiofifo_tready[3] && tiofifo_tlast[3],        
        tiofifo_tvalid[2] && tiofifo_tready[2] && tiofifo_tlast[2],        
        tiofifo_tvalid[1] && tiofifo_tready[1] && tiofifo_tlast[1],        
        tiofifo_tvalid[0] && tiofifo_tready[0] && tiofifo_tlast[0],        
        thdrfifo_tvalid && thdrfifo_tready && thdrfifo_tlast };

    // ok. now the best way to handle this is still an FSM
    // otherwise it just gets too complicated.
    
    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] ISSUE_COMMAND = 1;
    localparam [FSM_BITS-1:0] RUN_MUX = 2;
    localparam [FSM_BITS-1:0] ACKNOWLEDGE_ADDR = 3;
    reg [FSM_BITS-1:0] state = IDLE;

    // state = 3
    // stream_select = 3
    // stream_last_beat = 5
    // tiofifo_tvalid = 4
    // thdr_tvalid = 1
    generate
        if (DEBUG == "TRUE") begin : ILA
            wire [3:0] tiofifo_tvalid_vec = { tiofifo_tvalid[3],
                                              tiofifo_tvalid[2],
                                              tiofifo_tvalid[1],
                                              tiofifo_tvalid[0] };
            hdr_accum_ila u_ila(.clk(memclk),
                                .probe0(state),
                                .probe1(stream_select),
                                .probe2(stream_last_beat),
                                .probe3(tiofifo_tvalid_vec),
                                .probe4(thdrfifo_tvalid));
            
        end
    endgenerate    
    

    wire mux_enable = (state == RUN_MUX);
    assign s_done_tready = (state == ACKNOWLEDGE_ADDR);
    assign cmd_tvalid = (state == ISSUE_COMMAND);    
            
    always @(posedge memclk) begin
        if (!memresetn) state <= IDLE;
        else begin
            case (state)
                IDLE: if (everyone_ready && s_done_tvalid) 
                    state <= ISSUE_COMMAND;
                ISSUE_COMMAND: if (cmd_tready) 
                    state <= RUN_MUX;
                RUN_MUX: if (stream_select == 3'd4 && stream_last_beat[4]) 
                    state <= ACKNOWLEDGE_ADDR;
                ACKNOWLEDGE_ADDR: state <= IDLE;
            endcase
        end                   
            
        // these should only advance in RUN_MUX state anyway
        if (state != RUN_MUX) stream_select <= {3{1'b0}};
        else begin
            if (stream_select == 3'd0 && stream_last_beat[0]) stream_select <= 3'd1;
            else if (stream_select == 3'd1 && stream_last_beat[1]) stream_select <= 3'd2;
            else if (stream_select == 3'd2 && stream_last_beat[2]) stream_select <= 3'd3;
            else if (stream_select == 3'd3 && stream_last_beat[3]) stream_select <= 3'd4;
            else if (stream_select == 3'd4 && stream_last_beat[4]) stream_select <= 3'd0;
        end
    end        

    // WE NEED TO ADD 1 BIT OF USER ENABLE TO INDICATE WHEN WE'RE THE LAST STREAM
    axis_mux #(.S_COUNT(5),
               .DATA_WIDTH(64),
               .KEEP_ENABLE("FALSE"),
               .ID_ENABLE(0),
               .DEST_ENABLE(0),
               .USER_ENABLE(1),
               .USER_WIDTH(1))
        u_hdrmux( .clk(memclk),
                  .rst(!memresetn),
                  .s_axis_tdata( { tiofifo_tdata[3],
                                   tiofifo_tdata[2],
                                   tiofifo_tdata[1],
                                   tiofifo_tdata[0],
                                   thdrfifo_tdata } ),
                  .s_axis_tvalid({  tiofifo_tvalid[3],
                                    tiofifo_tvalid[2],
                                    tiofifo_tvalid[1],
                                    tiofifo_tvalid[0],
                                    thdrfifo_tvalid }),
                  .s_axis_tready({  tiofifo_tready[3],
                                    tiofifo_tready[2],
                                    tiofifo_tready[1],
                                    tiofifo_tready[0],
                                    thdrfifo_tready }),
                  .s_axis_tlast({   tiofifo_tlast[3],
                                    tiofifo_tlast[2],
                                    tiofifo_tlast[1],
                                    tiofifo_tlast[0],
                                    thdrfifo_tlast }),
                   .s_axis_tuser( { 1'b1,
                                    1'b0,
                                    1'b0,
                                    1'b0,
                                    1'b0 } ),                                      
                  `CONNECT_AXI4S_MIN_IF( m_axis_ , tothdr_ ),
                  .m_axis_tlast(tothdr_tlast_raw),
                  .m_axis_tuser(tothdr_tuser),
                  .enable(mux_enable),
                  .select(stream_select));                                    

    // ok, now for the datamover:
    // data stream is tothdr_
    // command stream is cmd_
    // status stream is stat_    
    hdr_datamover u_mover( .m_axi_s2mm_aclk(memclk),
                           .m_axi_s2mm_aresetn(memresetn),
                           .m_axis_s2mm_cmdsts_awclk(memclk),
                           .m_axis_s2mm_cmdsts_aresetn(memresetn),
                           `CONNECT_AXI4S_IF( s_axis_s2mm_ , tothdr_ ),
                           `CONNECT_AXI4S_MIN_IF( s_axis_s2mm_cmd_ , cmd_ ),
                           `CONNECT_AXI4S_MIN_IF( m_axis_s2mm_sts_ , stat_ ),
                           `CONNECT_AXIM_W_DW( m_axi_s2mm_ , m_axi_ , 64));
    `AXIM_NO_READS(m_axi_);

    // we pass through 4 bits of the memaddr in the tag:
    // so we need another FIFO to store 9 bits here.
    
    // FIFO inputs
    wire [8:0] addrfifo_in = s_done_tdata[4 +: 9];
    wire       addrfifo_write = (cmd_tvalid && cmd_tready);
    wire       addrfifo_overflow;
    // this feeds into the completion output along with stat.
    `DEFINE_AXI4S_MIN_IF( addrfifo_ , 9 );
    
    hdr_addrfifo u_addrfifo( .din(addrfifo_in),
                             .wr_en(addrfifo_write),
                             .overflow(addrfifo_overflow),
                             .dout(addrfifo_tdata),
                             .valid(addrfifo_tvalid),
                             .rd_en(addrfifo_tvalid && addrfifo_tready),
                             .srst(!memresetn),
                             .clk(memclk));

    // pull the address out of addrfifo and stat...
    wire [12:0] completion_addr = { addrfifo_tdata[8:0], stat_tdata[3:0] };
    // recreate the error status
    wire [3:0] completion_err = { !stat_tdata[7], stat_tdata[6:4] };

    // ready can wait on valid, not reverse
    assign addrfifo_tready = m_cmpl_tready && m_cmpl_tvalid;
    // ready can wait on valid, not reverse
    assign stat_tready = m_cmpl_tready && m_cmpl_tvalid;
    // valid has no condition on ready
    assign m_cmpl_tvalid = stat_tvalid && addrfifo_tvalid;    
    // cmpl_tdata is 24 bits. upper 16 are the address (padded by 3)
    // lower 8 are the error stats padded by 4.
    assign m_cmpl_tdata = { {3{1'b0}}, completion_addr, {4{1'b0}}, completion_err };
endmodule

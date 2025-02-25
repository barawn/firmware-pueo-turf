`timescale 1ns / 1ps
`include "interfaces.vh"

// TURF UDP port read/write.

// This module handles the read/write control port.
// We buffer the incoming data so we don't block anything.
// tuser is used to indicate that it's a header word.
// For the header, the 64 bits are
// bits [63:32] = source IP
// bits [31:16] = source port
// bits [15:0]  = length
// and tuser[1] is set.
// tuser[3:2] indicate if the [high:low] 32 bits are valid
// tuser[0] indicates a read port match (when tuser[1] is set) or all-zero low 32-bits (when not)
//
// The data path matches the TURF ICD v0.2
// reads [31:0] tag/addr
// writes[31:0] tag/addr
// writes[63:32] data
//
// DEAR GOD WHAT IN THE HELL AM I DOING
// OK: HERE'S THE TRICK. READ/WRITE DETERMINATION COMES FROM THE *DEST PORT* AND IS MERGED 
//     INTO s_hdr_tuser[0]
//
// INSIDE THIS MODULE BOTH s_hdr_ and s_payload_ ARE MUXED AND PUSHED INTO A FIFO
//
// IN ADDITION TO THE 64 BITS, WE ALSO HAVE 4 BITS GOING THROUGH THE FIFO RESULTING FROM
// THE MUX
// tuser[1:0] == 00 (payload)
//               01 (payload + low 32 bits are zero)
//               10 (header for write port)
//               11 (header for read port)
// tuser[2] => low 32 bits valid
// tuser[3] => high 32 bits valid
//
// The reason for the "payload + low 32 bits are zero" option is that this SPECIFIC
// value will ALWAYS be executed.
//
// NOTE: I need to convert this into a V2. This one sucks. There's zero reason the
// interface side needs to run in Ethernet land.


// OK THIS IS V2: V2 ALSO TAKES IN THE WISHBONE CLOCK AND THE FIFOs ARE BOG-STANDARD
// SLEAZE FIFOs. LET'S SEE IF THIS WORKS!!
//
// OK: so ONE reason that we wanted things in the same domain is it saved us a CC FIFO
// on the header side.
//
// Whatever. We don't need a CC FIFO there: we just flag entry to the RESP_HEADER stage
// and reregister the payload on the other side, sending an ack flag back.
module turf_udp_rdwr_v2(
        input aclk,
        input aresetn,

        // ports get merged externally
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr_ , 64 ),
        // tuser here indicates a read
        input [0:0] s_hdr_tuser,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_payload_ , 64),
        input [7:0] s_payload_tkeep,
        input s_payload_tlast,
        
        // now our output. 
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_hdr_ , 64 ),
        output [0:0] m_hdr_tuser,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_payload_ , 64),
        output [7:0] m_payload_tkeep,
        output m_payload_tlast,
        
        // v2 properly merges this into a WISHBONE interface
        // All the CC $#!+ should be handled via the FIFO CC
        input wb_clk_i,
        `HOST_NAMED_PORTS_WB_IF( wb_ , 28, 32 )
    );
    
    parameter DEBUG = "TRUE";
    parameter ACLKTYPE = "ETH";
    parameter WBCLKTYPE = "NONE";
    //////////////////////////////////////////////////////////////////////////////////////////////
    //                              ACLK SIDE OF THE FIFOS                                      //
    //////////////////////////////////////////////////////////////////////////////////////////////
        
    // First we need to combine the headers and payloads.
    wire [3:0] hdr_tuser = { 3'b111, s_hdr_tuser[0] };
    wire [3:0] payload_tuser = { &s_payload_tkeep[7:4], &s_payload_tkeep[3:0], 1'b0, |s_payload_tdata[31:0] };

    // This is the response header stuff.
    reg         response_header_valid = 0;
    (* CUSTOM_CC_DEST = ACLKTYPE *)
    reg [63:0]  response_header_data_aclk = {64{1'b0}};
    wire [63:0] response_header_data_wbclk;
    wire        response_header_complete_aclk = m_hdr_tvalid && m_hdr_tready;
    wire        response_header_complete_wbclk;
    wire        response_header_ready_aclk;
    wire        response_header_ready_wbclk;
    wire        response_header_path_wbclk;
    (* CUSTOM_CC_DST = ACLKTYPE *)
    reg         response_header_path_aclk = 0;
    
    assign m_hdr_tdata = response_header_data_aclk;
    assign m_hdr_tvalid = response_header_valid;
    assign m_hdr_tuser = response_header_path_aclk;
    
    flag_sync u_hdr_rdy_sync(.in_clkA(response_header_ready_wbclk),
                             .out_clkB(response_header_ready_aclk),
                             .clkA(wb_clk_i),
                             .clkB(aclk));

    flag_sync u_hdr_complete_sync(.in_clkA(response_header_complete_aclk),
                                  .out_clkB(response_header_complete_wbclk),
                                  .clkA(aclk),
                                  .clkB(wb_clk_i));
             
    reg select_payload = 0;
    always @(posedge aclk) begin
        if (!aresetn || (s_payload_tvalid && s_payload_tready && s_payload_tlast)) select_payload <= 0;
        else if (s_hdr_tvalid && s_hdr_tready) select_payload <= 1;
        
        if (response_header_ready_aclk) begin
            response_header_valid <= 1;
            response_header_data_aclk <= response_header_data_wbclk;
            response_header_path_aclk <= response_header_path_wbclk;
        end else if ((m_hdr_tready && m_hdr_tvalid) || !aresetn)
            response_header_valid <= 0;
    end
    
    `DEFINE_AXI4S_MIN_IF( fifo_in_ , 64 );
    wire [3:0] fifo_in_tuser;
    wire fifo_in_tlast;
    `DEFINE_AXI4S_MIN_IF( fifo_out_ , 64 );
    wire [3:0] fifo_out_tuser;
    wire fifo_out_tlast;
    reg fifo_out_tready_r;
    assign fifo_out_tready = fifo_out_tready_r;
    
    `DEFINE_AXI4S_MIN_IF( payload_out_ , 64 );
    wire payload_out_tlast;
        
    // the axis_mux basically works by:
    // if a frame is not flowing, the stream output is the one in 'select'
    // once a frame starts flowing, the output will stay the same until tlast.
    // plus there's an enable
    axis_mux #(.S_COUNT(2),
               .DATA_WIDTH(64),
               .KEEP_ENABLE(0),
               .ID_ENABLE(0),
               .DEST_ENABLE(0),
               .USER_ENABLE(1),
               .USER_WIDTH(4))
            u_combine( .clk(aclk), .rst(!aresetn),
                       .s_axis_tdata( { s_payload_tdata, s_hdr_tdata } ),
                       .s_axis_tvalid({ s_payload_tvalid, s_hdr_tvalid } ),
                       .s_axis_tready({ s_payload_tready, s_hdr_tready } ),
                       .s_axis_tuser( { payload_tuser, hdr_tuser } ),
                       .s_axis_tlast( { s_payload_tlast, 1'b1 } ),
                       `CONNECT_AXI4S_MIN_IF( m_axis_ , fifo_in_ ),
                       .m_axis_tuser( fifo_in_tuser ),
                       .m_axis_tlast( fifo_in_tlast ),
                       .enable(1'b1),
                       .select( select_payload ));

    //////////////////////////////////////////////////////////////////////////////////////////////
    //                              END ALL ACLK LOGIC                                          //
    //////////////////////////////////////////////////////////////////////////////////////////////


    //////////////////////////////////////////////////////////////////////////////////////////////
    //                              FIFOS GO HERE                                               //
    //////////////////////////////////////////////////////////////////////////////////////////////

    // screw the AXI FIFOs, we'll just use the straight up guys
    // the inbound FIFO needs 69 bits: data, tuser, tlast
    // the outbound FIFO needs 65 bits: data, tlast
    
    wire fifo_in_full;
    assign fifo_in_tready = !fifo_in_full;
    // this allows us to propagate aresetn to the WB side logic.    
    wire wb_fifo_reset;    
    ccfifo69 u_infifo(.wr_clk(aclk),
                      .din( { fifo_in_tlast, fifo_in_tuser, fifo_in_tdata } ),
                      .wr_en( fifo_in_tready && fifo_in_tvalid ),
                      .full(fifo_in_full),
                      .rd_clk(wb_clk_i),
                      .dout( { fifo_out_tlast, fifo_out_tuser, fifo_out_tdata } ),
                      .rd_en( fifo_out_tready && fifo_out_tvalid ),
                      .valid( fifo_out_tvalid ),
                      .srst( !aresetn ),
                      .rd_rst_busy( wb_fifo_reset ));   

    wire payload_out_full;
    wire payload_fifo_valid;
    assign payload_out_tready = !payload_out_full;
    wire out_fifo_reset_aclk;   // suppress tvalid when in reset
    wire out_fifo_reset_wbclk;  // this is the outbound fifo's reset busy     
    assign m_payload_tvalid = (!out_fifo_reset_aclk && payload_fifo_valid);
    // hold everything in reset until both FIFOs exit reset
    wire wb_rst_full = (wb_fifo_reset || out_fifo_reset_wbclk);
    ccfifo65 u_outfifo(.wr_clk(wb_clk_i),
                       .din( { payload_out_tlast, payload_out_tdata } ),
                       .wr_en( payload_out_tready && payload_out_tvalid ),
                       .full( payload_out_full ),
                       .rd_clk( aclk ),
                       .dout( { m_payload_tlast, m_payload_tdata } ),
                       .rd_en(  m_payload_tvalid && m_payload_tready ),
                       .valid(  payload_fifo_valid ),
                       .srst( wb_fifo_reset ),
                       .wr_rst_busy( out_fifo_reset_wbclk ),
                       .rd_rst_busy( out_fifo_reset_aclk )
                       );
    // we ONLY write 8-byte chunks
    assign m_payload_tkeep = 8'hFF;    

    //////////////////////////////////////////////////////////////////////////////////////////////
    //                              END FIFOS                                                   //
    //////////////////////////////////////////////////////////////////////////////////////////////


    //////////////////////////////////////////////////////////////////////////////////////////////
    //                              EVERYTHING PAST HERE IS WBCLK SIDE LOGIC                    //
    //////////////////////////////////////////////////////////////////////////////////////////////

    // this is the statemachine's version of payload_out_tlast
    reg user_last = 0;
        
    // First read from the last packet
    reg [31:0] last_first_read = {32{1'b0}};

    // Holds the address and tag.
    reg [31:0] adr_tag_reg = {32{1'b0}};    
    // This is a temp register for the 64-bit response (and holding for the address)
    reg [31:0] read_data = {32{1'b0}};
    // This is the write response as well as the packet loss check.
    reg [31:0] write_response = {32{1'b0}};

    reg last_read_valid = 0;
    reg last_write_valid = 0;
    

    // these are all CC sources now
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] response_length = 16'd8;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [47:0] response_ipport = {48{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg read_path = 0;

    // this just simplifies things
    reg en_reg = 0;    
    // this creates the flag to go to aclk on resp
    reg resp_waiting = 0;
        
    // ok, now we state machine the thing
    localparam FSM_BITS=4;
    // waiting for a header (we dump everything non-header in case there's some weird reset $#!+)
    localparam [FSM_BITS-1:0] IDLE = 0;
    // read path, from the low (first) word, with check
    localparam [FSM_BITS-1:0] READ_0_CHECK = 1;
    // wait for ack
    localparam [FSM_BITS-1:0] READ_0_ACK = 2;
    // write into payload FIFO
    localparam [FSM_BITS-1:0] READ_0_RESP = 3;
    // wait for ack on second read if present
    localparam [FSM_BITS-1:0] READ_1_ACK = 4;
    // if second read was present and WAS NOT last, peek the next to see if it's OK
    localparam [FSM_BITS-1:0] READ_1_PEEK = 5;
    // write response into payload FIFO if second read present
    localparam [FSM_BITS-1:0] READ_1_RESP = 6;   
    // back to a read_0 but with no check
    localparam [FSM_BITS-1:0] READ_0 = 7;
    // skip state, in case we're repeating
    localparam [FSM_BITS-1:0] READ_SKIP = 8;
    // write
    localparam [FSM_BITS-1:0] WRITE_CHECK = 9;
    // wait for ack
    localparam [FSM_BITS-1:0] WRITE_ACK = 10;
    // write state, with no check
    localparam [FSM_BITS-1:0] WRITE = 11;
    // write into payload FIFO    
    localparam [FSM_BITS-1:0] WRITE_RESP = 12;
    // read (and first-time write) dump state, invalid packet or trailing bytes
    localparam [FSM_BITS-1:0] DUMP_CHECK_RESP = 13;
    // write dump state, invalid trailing bytes in packet
    localparam [FSM_BITS-1:0] DUMP_THEN_RESP = 14;
    // push header
    localparam [FSM_BITS-1:0] RESP_HEADER = 15;
    reg [FSM_BITS-1:0] state = IDLE;
    // tuser[0] = read path (when tuser[1] is set) and not-zero check (when tuser[1] is not)
    // tuser[1] = header
    // tuser[2] = low 32 bits are valid
    // tuser[3] = high 32 bits are valid    
    
    // Autoclear last write when we read address 0 with tag 0 (initialize).
    wire reset_write_valid = (state == READ_0_CHECK && fifo_out_tuser[1:0] == 2'b01 && fifo_out_tvalid);
    reg reset_write_valid_r = 0;
    
    always @(posedge wb_clk_i) begin
        reset_write_valid_r <= reset_write_valid;
    
        // we don't need to clear last_read_valid on a read of address 0, it's never checked
        if (wb_rst_full) last_read_valid <= 0;
        else if (state == READ_0_CHECK && fifo_out_tvalid && fifo_out_tuser[2]) last_read_valid <= 1;
        // we DO need to clear last_write_valid on a read 
        if (wb_rst_full || reset_write_valid_r) last_write_valid <= 0;
        else if (state == WRITE_CHECK && fifo_out_tvalid && fifo_out_tuser[3:2] == 2'b11) last_write_valid <= 1;
    
        if (state == IDLE && fifo_out_tvalid && fifo_out_tready && fifo_out_tuser[1])
            read_path <= fifo_out_tuser[0];

        if (fifo_out_tvalid && fifo_out_tready && fifo_out_tuser[1] && state == IDLE) begin
            response_ipport <= fifo_out_tdata[16 +: 48];
        end
        // This is the UDP length, which always starts at 8.
        if (state == IDLE) response_length <= 16'd8;
        else begin
            if (payload_out_tready && payload_out_tvalid) response_length <= response_length + 8;
        end

        // so user_last is (READ_1_ACK and ack_i and fifo_out_tlast) or (READ_1_PEEK and fifo_out_tvalid and not fifo_out_tuser[2])
        if (state == READ_1_ACK) user_last <= (wb_ack_i && fifo_out_tlast);
        else if (state == READ_1_PEEK) user_last <= fifo_out_tvalid && !fifo_out_tuser[2];
        else if (state == IDLE) user_last <= 1'b0;
        
        // WRITE_CHECK only occurs on the first one.
        if (state == WRITE_CHECK && fifo_out_tvalid && fifo_out_tuser[3:2] == 2'b11) write_response <= fifo_out_tdata[0 +: 32];
        // READ_0_CHECK only happens on the first one. We grab the low 32-bits because it's a 32-bit object.
        if (state == READ_0_CHECK && fifo_out_tvalid && fifo_out_tuser[2]) last_first_read <= fifo_out_tdata[0 +: 32];

        // Logic for grabbing the address.
        if (fifo_out_tvalid) begin
            if (state == READ_0 || state == READ_0_CHECK || state == WRITE_CHECK || state == WRITE) adr_tag_reg <= fifo_out_tdata[0 +: 32];
            else if (state == READ_0_RESP && fifo_out_tuser[3]) adr_tag_reg <= fifo_out_tdata[32 +: 32];
        end                
        
        // we super-cheat on the enable reg, we don't care about the extra clock delay
        if (wb_ack_i) en_reg <= 1'b0;
        else if (state == READ_0_ACK || state == READ_1_ACK || state == WRITE_ACK) en_reg <= 1'b1;        
        
        if ((state == READ_0_ACK || state == READ_1_ACK) && wb_ack_i) begin
//            read_response[32 +: 32] <= (state == READ_0_ACK) ? fifo_out_tdata[0 +: 32] :
//                                                               fifo_out_tdata[32 +: 32];
            read_data[0 +: 32] <= wb_dat_i;
        end                                                                  
        
        if (wb_rst_full) state <= IDLE;
        else begin
            case (state)
                // tready is set here
                IDLE: if (fifo_out_tvalid && fifo_out_tready && fifo_out_tuser[1]) begin
                    if (fifo_out_tuser[0]) state <= READ_0_CHECK;
                    else state <= WRITE_CHECK;
                end
                // tready is NEVER set here
                READ_0_CHECK: if (fifo_out_tvalid) begin
                    if (fifo_out_tuser[2]) begin
                        // packet loss guard
                        if (!fifo_out_tuser[0] && fifo_out_tdata[31:0] == last_first_read && last_read_valid) state <= READ_SKIP;
                        else state <= READ_0_ACK;
                    // DUMP just goes through all data until TLAST and then
                    // pushes out a response if there was any data written
                    end else state <= DUMP_CHECK_RESP;
                end
                // tready is NEVER set here
                READ_0: if (fifo_out_tvalid) begin
                    if (fifo_out_tuser[2]) state <= READ_0_ACK;
                    else state <= DUMP_CHECK_RESP;
                end
                // tready is NEVER set here
                READ_0_ACK: if (wb_ack_i) state <= READ_0_RESP;
                // Once we've finished writing payload in, if there's another
                // guy in our payload, we do that. Otherwise we jump to DUMP
                // to assert fifo_out_tready until fifo_out_tlast, then
                // go to RESP_HEADER.
                // tready is NEVER set here
                READ_0_RESP: if (payload_out_tready && payload_out_tvalid) begin
                    if (fifo_out_tuser[3]) state <= READ_1_ACK;
                    else state <= DUMP_CHECK_RESP;
                end
                // OK, this is a bit tougher.
                // If we're the last one, we jump to READ_1_RESP automatically
                // and set user_last. If we're NOT the last one, we need
                // to peek ahead to see if there's another valid one next.
                // So we go to READ_1_PEEK.
                // Either way, we're setting tready if ack_i.
                
                // tready is set here IF ack_i
                READ_1_ACK: if (wb_ack_i) begin
                    if (fifo_out_tlast) state <= READ_1_RESP; // plus set user_last
                    else state <= READ_1_PEEK;
                end
                // tready is set here IF fifo_out_tvalid AND NOT fifo_out_tuser[2].
                READ_1_PEEK: if (fifo_out_tvalid) begin
                    if (fifo_out_tuser[2]) state <= READ_1_RESP; // and do NOT set user_last
                    else state <= READ_1_RESP; // and set user_last
                end
                // payload_out_tlast here is user_last
                // tready is NEVER set here
                READ_1_RESP: if (payload_out_tready && payload_out_tvalid) begin
                    if (user_last) state <= RESP_HEADER;
                    else state <= READ_0;
                end
                // tready is set here if payload_out_tready
                READ_SKIP: if (payload_out_tready) state <= RESP_HEADER;
                // We go to DUMP_CHECK_RESP here because if there aren't enough bytes,
                // this is the first write and no response should be given.
                // tready is never set here
                WRITE_CHECK: begin
                    if (fifo_out_tvalid) begin
                        if (fifo_out_tuser[3:2] == 2'b11) begin
                            if (fifo_out_tdata[0 +: 32] == write_response && last_write_valid) state <= WRITE_RESP;
                            else state <= WRITE_ACK;
                        end else state <= DUMP_CHECK_RESP;
                    end
                end
                // tready is set here when ack_i
                WRITE_ACK: if (wb_ack_i) begin
                            if (fifo_out_tlast) state <= WRITE_RESP;
                            else state <= WRITE;
                           end
                // here we go to DUMP_THEN_RESP because we need to assert tready to dump this,
                // then go to WRITE_RESP to finish up the packet.
                // tready is never set here
                WRITE: if (fifo_out_tvalid) begin
                    if (fifo_out_tuser[3:2] == 2'b11) state <= WRITE_ACK;
                    else state <= DUMP_THEN_RESP;
                end
                // tready is never set here
                WRITE_RESP: if (payload_out_tready && payload_out_tvalid) state <= RESP_HEADER;
                // these 2 guard against partial writes.
                // if say less than 8 bytes is written to 'Tw', then WRITE_CHECK
                // just bounces to WRITE_DUMP, which holds fifo_out_tready (and fifo_out_tlast
                // is set), bouncing to IDLE immediately.
                // if instead 11 bytes is written to 'Tw', it goes
                // WRITE_CHECK, WRITE_ACK, WRITE, WRITE_DUMP, WRITE
                // tready is always set here
                DUMP_CHECK_RESP: if (fifo_out_tvalid && fifo_out_tlast) begin
                    if (response_length != 16'd8) state <= RESP_HEADER;
                    else state <= IDLE;
                end
                // tready is always set here
                DUMP_THEN_RESP: if (fifo_out_tvalid && fifo_out_tlast) state <= WRITE_RESP;
                RESP_HEADER: if (response_header_complete_wbclk) state <= IDLE;
            endcase
        end
    end
    // this enumerates all 16 states
    always @(*) begin
        case (state)
            // IDLE consumes stream data until a header word
            // DUMP_CHECK_RESP, DUMP_THEN_RESP consume data until tlast
            IDLE, DUMP_CHECK_RESP, DUMP_THEN_RESP: fifo_out_tready_r <= 1;
            // these never consume data
            READ_0_CHECK, READ_0, READ_0_ACK, READ_0_RESP, READ_1_RESP, WRITE_CHECK, WRITE, WRITE_RESP, RESP_HEADER: fifo_out_tready_r <= 0;
            // these consume data when the transaction completes
            READ_1_ACK, WRITE_ACK: fifo_out_tready_r <= wb_ack_i;
            // this consumes data when the response has been echoed
            READ_SKIP: fifo_out_tready_r <= payload_out_tready;
            // this consumes data if it's not valid
            READ_1_PEEK: fifo_out_tready_r <= fifo_out_tvalid && !fifo_out_tuser[2];
        endcase
    end

    // outbound payload. user_tlast happens when we have to peek ahead.
    // read_response 
    assign payload_out_tlast = user_last || (state == READ_SKIP) || (state == WRITE_RESP) || (state == READ_0_RESP && !fifo_out_tuser[3]);
    // When we're in READ_SKIP, this needs to be the last read. Otherwise it's ALWAYS the adr_tag register.
    // Even if we do a write skip, the adr_tag_reg gets updated (to the exact same thing).
    assign payload_out_tdata[0 +: 32] = (state == READ_SKIP) ? last_first_read : adr_tag_reg;
    assign payload_out_tdata[32 +: 32] = read_data[31:0];
    assign payload_out_tvalid = (state == READ_0_RESP || state == READ_1_RESP || state == WRITE_RESP || state == READ_SKIP);
    
    // outbound header
//    (* CUSTOM_CC_DEST = ACLKTYPE *)
//    reg [63:0]  response_header_data_aclk = {64{1'b0}};
//    wire [63:0] response_header_data_wbclk;
//    wire        response_header_complete_aclk = m_hdr_tvalid && m_hdr_tready;
//    wire        response_header_complete_wbclk;
//    wire        response_header_ready_aclk;
//    wire        response_header_ready_wbclk;
    assign response_header_ready_wbclk = (state == RESP_HEADER && !resp_waiting);
    assign response_header_data_wbclk = { response_ipport, response_length };
    assign response_header_path_wbclk = read_path;

    // outbound interface
    assign wb_cyc_o = en_reg;
    assign wb_stb_o = en_reg;
    assign wb_adr_o = adr_tag_reg[0 +: 28];
    assign wb_we_o = (state == WRITE_ACK);
    assign wb_sel_o = {4{1'b1}};
    // data output is always the high bits
    assign wb_dat_o = fifo_out_tdata[32 +: 32];

    generate
        if (DEBUG == "TRUE") begin : ILA
            udp_rdwr_ila u_ila(.clk(wb_clk_i),
                               .probe0( fifo_out_tdata ),
                               .probe1( fifo_out_tuser ),
                               .probe2( fifo_out_tready ),
                               .probe3( fifo_out_tvalid ),
                               .probe4( fifo_out_tlast ),
                               .probe5( state ));
        end
    endgenerate
    
endmodule

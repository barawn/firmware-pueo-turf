`timescale 1ns / 1ps
`include "interfaces.vh"
// Handles the ack AND nack path!
// This gets sleazed with a mask that deterministically ignores
// portions of the input.
// Then the output (acknack) is remapped as well outside.
// We can do this because the logic's exactly the same.
// Note that bit [62] is ALWAYS ignored because it's the
// OPEN bit in response.
// The top constant in the data response always has both 63 and 62
// set so to check you can just do
// fragment header & checkmask == value returned
module turf_acknack_port #(
        // this is ACK, NACK would be
        // 000000FF_FFFFFFFF
        parameter [63:0] CHECK_BITS = 64'h800000FF_FFF00000
    )(
        input aclk,
        input aresetn,
        input event_open_i,
        // this is only used for nacks
        input [9:0] nfragment_count_i,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_udphdr_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_IF( s_udpdata_ , 64 ),
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_udphdr_ , 64),
        `HOST_NAMED_PORTS_AXI4S_IF( m_udpdata_ , 64),
        // generate ack/nacks.
        // OK: I have no idea WTF this was doing before.
        // Now instead this is:
        // low 32 bits = low 32 bits of s_udpdata (12-bit upper addr + frag offset or all 1s)
        // bits 32 +: 11 = number of fragment qwords (bytes to transfer if not full nack)
        // bits 45:43 = reserved
        // bit  46 = full event nack
        // bit  47 = allow
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_acknack_ , 48 )       
    );
    
    // kill bit 62, always ignored (used for OPEN)
    localparam OPEN_BIT = 62;
    localparam [63:0] MY_CHECK_BITS =
        { CHECK_BITS[63:OPEN_BIT+1],1'b0,CHECK_BITS[OPEN_BIT-1:0] };

    reg full_event_nack = 0;
    reg event_was_open = 0;
    reg [10:0] nack_fragment_count = {11{1'b0}};
        
    reg [31:0] this_ip = {32{1'b0}};
    reg [15:0] this_port = {32{1'b0}};
    // the LENGTH of our reply is always 16.
    wire [15:0] this_length = 16'd16;
        
    reg [63:0] last_store = {64{1'b0}};
    reg last_valid = 0;
    
    localparam FSM_BITS=3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] CHECK_DATA_0 = 1;
    localparam [FSM_BITS-1:0] WRITE_DATA = 2;
    localparam [FSM_BITS-1:0] READ_DATA_N = 3;
    localparam [FSM_BITS-1:0] READ_SKIP = 4;
    localparam [FSM_BITS-1:0] DUMP = 5;
    localparam [FSM_BITS-1:0] WRITE_HEADER = 6;
    localparam [FSM_BITS-1:0] WRITE_RESPONSE = 7;
    reg [FSM_BITS-1:0] state = IDLE;

    // the udpdata ready logic is hard
    reg s_udpdata_tready_r;    
    
    always @(posedge aclk) begin    
        if (!aresetn || !event_open_i) last_valid <= 0;
        else if (state == WRITE_DATA && s_udpdata_tvalid && s_udpdata_tready) last_valid <= 1;
    
        if ((state == CHECK_DATA_0 || state == READ_DATA_N) && s_udpdata_tvalid) begin
            // do full event nack check
            full_event_nack <= (s_udpdata_tdata[19:0] == {20{1'b1}});
        end
    
        event_was_open <= event_open_i;
        if (event_open_i && !event_was_open) begin
            nack_fragment_count <= nfragment_count_i + 1;
        end
    
        if (state == WRITE_DATA && s_udpdata_tvalid && s_udpdata_tready) begin
            last_store <= s_udpdata_tdata & MY_CHECK_BITS;
        end
    
        if (s_udphdr_tready && s_udphdr_tvalid) begin
            this_ip <= s_udphdr_tdata[32 +: 32];
            this_port <= s_udphdr_tdata[16 +: 16];
        end
        
        if (!aresetn) state <= IDLE;
        else begin
            case (state)
                // s_udphdr_tready is always 1 here
                IDLE: if (s_udphdr_tvalid && s_udphdr_tready) state <= CHECK_DATA_0;
                // DUMP is EXCLUSIVELY for when we receive less than 8 bytes and DON'T respond
                // s_udpdata_tready is always 0 here
                CHECK_DATA_0: if (s_udpdata_tvalid) begin
                    if (s_udpdata_tkeep != 8'hFF) state <= DUMP;
                    else if (!event_open_i) state <= READ_SKIP;
                    else if (last_valid) begin
                        // this should optimize away
                        if (s_udpdata_tdata & MY_CHECK_BITS == last_store) state <= READ_SKIP;
                        else state <= WRITE_DATA;
                    end else state <= WRITE_DATA;
                end
                // s_udpdata_tready is m_acknack_tready here
                WRITE_DATA: 
                    if (m_acknack_tready) begin
                        // single valid ack
                        if (s_udpdata_tlast) state <= WRITE_HEADER;
                        // more than 1
                        else state <= READ_DATA_N;
                    end
                // s_udpdata_tready is always 0 here    
                READ_DATA_N:
                    if (s_udpdata_tvalid) begin
                        if (s_udpdata_tkeep != 8'hFF) state <= READ_SKIP;
                        else state <= WRITE_DATA;
                    end
                // s_udpdata_tready is always 1 here
                READ_SKIP:
                    if (s_udpdata_tvalid && s_udpdata_tlast) state <= WRITE_HEADER;
                // no response, we didn't get anything valid
                // s_udpdata_tready is always 1 here
                DUMP:
                    if (s_udpdata_tvalid && s_udpdata_tlast) state <= IDLE;
                WRITE_HEADER:
                    if (m_udphdr_tvalid && m_udphdr_tready) state <= WRITE_RESPONSE;
                WRITE_RESPONSE:
                    if (m_udpdata_tvalid && m_udpdata_tready) state <= IDLE;
            endcase
        end
    end
    
    always @(*) begin
        case (state)
            IDLE, CHECK_DATA_0, READ_DATA_N, WRITE_HEADER, WRITE_RESPONSE: s_udpdata_tready_r <= 1'b0;
            READ_SKIP, DUMP: s_udpdata_tready_r <= 1'b1;
            WRITE_DATA: s_udpdata_tready_r <= m_acknack_tready;
        endcase
    end
    
    // s_udpdata_ handling...
    assign s_udpdata_tready = s_udpdata_tready_r;
        
    // s_udphdr_ handling...
    assign s_udphdr_tready = (state == IDLE);
    // m_udphdr_ handling...
    assign m_udphdr_tvalid = (state == WRITE_HEADER);
    assign m_udphdr_tdata = { this_ip, this_port, this_length };
    // m_udpdata_ handling...
    assign m_udpdata_tvalid = (state == WRITE_RESPONSE);
    assign m_udpdata_tkeep = 8'hFF;
    assign m_udpdata_tlast = 1'b1;
    // plug in the open bit, so you'll know why it had no effect.
    assign m_udpdata_tdata = (last_store & MY_CHECK_BITS) | (event_open_i << OPEN_BIT);

    // wtf, why is this effed up???
    // m_acknack_ handling
    assign m_acknack_tvalid = (state == WRITE_DATA);            
    // acknack structure:
    assign m_acknack_tdata = {
        s_udpdata_tdata[63],        // 1
        full_event_nack,            // 1
        3'b0000,                    // 3
        nack_fragment_count,        // 11
        s_udpdata_tdata[31:0]};     // 32

endmodule

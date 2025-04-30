`timescale 1ns / 1ps
`include "interfaces.vh"
// UDP fragment generator. This takes a tagged input stream
// and breaks it up into a number of UDP fragments of programmable
// size. You pass the tag and length (in bytes) into the control
// stream, and then the data through the s_data_ port.
// The tag and length are present in the first 8 bytes along
// with a constant and the fragment number.
module turf_fragment_gen(
        input aclk,
        input aresetn,
        // Payload uint64_ts in a fragment.
        input [9:0] nfragment_count_i,   
        // Mask of source port
        input [15:0] fragsrc_mask_i,
        // Event path is open
        input event_open_i,
        // Destination IP
        input [31:0] event_ip_i,
        // Destination port
        input [15:0] event_port_i,
        // control interface
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_ctrl_ , 32 ),
        // data interface
        `TARGET_NAMED_PORTS_AXI4S_IF( s_data_ , 64 ),
        
        // UDP header interface (63:32=IP, 31:16=port, 15:0=length)
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_hdr_ , 64),
        // source port.
        output [15:0] m_hdr_tuser,
        // UDP payload interface, I don't know what tuser does
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_payload_ , 64 ),
        output [7:0] m_payload_tkeep,
        output       m_payload_tuser,
        output       m_payload_tlast                
    );
    // This parameter determines if we actually use the TLAST provided to us
    // by m_payload. There are some advantages to this but not a lot. For now
    // we're actually just ignoring it.
    parameter USE_TLAST = "FALSE";
    parameter DEBUG = "TRUE";
    parameter [15:0] BASE_PORT = "T0";

    // this constant needs its top bit set
    localparam [15:0] CONSTANT_0 = 16'hDA7A;
    localparam [5:0] CONSTANT_1 = 6'h00;
    
    // This takes an AXI-Stream input and splits it into UDP fragments.
    // States are IDLE, HEADER, TAG, and STREAM
    // We receive an AXI4-Stream for the event generation which consists
    // of the address + length (status output of the S2MM data mover
    // after going through control logic).
    // This is functionally 32-bit (and generates our header).

    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] HEADER = 1;
    localparam [FSM_BITS-1:0] TAG = 2;
    localparam [FSM_BITS-1:0] STREAM = 3;
    reg [FSM_BITS-1:0] state = IDLE;
    
    // number of beats that have transferred (starts at 0)
    reg [9:0] fragment_beats = {10{1'b0}};
    reg [9:0] fragment_number = {10{1'b0}};
    reg [11:0] address = {12{1'b0}};
    reg [19:0] length = {20{1'b0}};
    // This is the remaining length in the entire transaction. Loaded at start
    // of new transaction, and updated at HEADER
    reg [19:0] remaining_length = {20{1'b0}};
    // Fragment length. Calculated at IDLE for first fragment, and at TAG for next
    reg [15:0] fragment_length = {16{1'b0}};

    // This is either the remaining length in this *entire* transaction
    // (if not IDLE) *or* it's the total length of the transaction when
    // a new transaction occurs in IDLE.
    wire [19:0] current_length_remaining = (state == IDLE) ? 
        s_ctrl_tdata[0 +: 20] : remaining_length;
    // round current length remaining
    wire [16:0] current_length_remaining64 =
        (current_length_remaining[2:0] != 3'b000) ?
        current_length_remaining[ 3 +: 16] + 1 :
        current_length_remaining[ 3 +: 16];

    wire [63:0] tag = { CONSTANT_0, CONSTANT_1, fragment_number, address, length };

    // captured IP address
    reg [31:0] event_ip = {32{1'b0}};
    // captured port
    reg [15:0] event_port = {16{1'b0}};
    // reregistered event open, to look for a rising edge
    reg event_was_open = 0;
    // set high if we EVER get a valid IP
    reg event_was_ever_open = 0;

    // max number of beats we want to send (so min is 1)
    reg [12:0] max_fragment_beats = {13{1'b0}};

    // this is the last payload beat
    wire last_payload = (max_fragment_beats[9:0] == fragment_beats + 1);
    // this is the last payload beat of the entire stream
    wire tlast_internal = last_payload && (remaining_length == 20'h0);
    // I dunno if it ever makes sense to use the external tlast, maybe just check it and
    // flag if it doesn't match.
    wire tlast = (USE_TLAST == "TRUE") ? s_data_tlast : tlast_internal;

    always @(posedge aclk) begin
        if (!aresetn) event_was_ever_open <= 1'b0;
        else if (event_open_i) event_was_ever_open <= 1'b1;
        event_was_open <= event_open_i;
        if (event_open_i && !event_was_open) begin
            event_ip <= event_ip_i;
            event_port <= event_port_i;
        end

        if (!aresetn) state <= IDLE;
        else begin
            case (state)
                IDLE: if (s_ctrl_tvalid && s_ctrl_tready && event_was_ever_open) state <= HEADER;
                HEADER: if (m_hdr_tvalid && m_hdr_tready) state <= TAG;
                TAG: if (m_payload_tvalid && m_payload_tready) state <= STREAM;
                STREAM: if (m_payload_tvalid && m_payload_tready) begin
                    // The benefit of using tlast_internal here (USE_TLAST = "FALSE")
                    // is that no matter what we're not going to break the UDP stream.
                    if (last_payload) begin
                        if (tlast) state <= IDLE;
                        else state <= HEADER;
                    end
                end
            endcase
        end
        
        // Calculate the fragment length.
        // We have to do this for the first fragment and then after each new fragment
        if ((state == IDLE && s_ctrl_tvalid && s_ctrl_tready)|| 
            (state == TAG && m_payload_tvalid && m_payload_tready)) begin
            // fits in a single fragment. 
            // If for instance nfragment_count is 8, we can accept 72 bytes
            // so if current_length_remaining64 is 9 we need to be OK with that
            if (current_length_remaining64 <= nfragment_count_i + 1) begin
                // nfragment_count_i is 10 bits, so we only need to grab
                // 13 bits here and add 8, for the tag.
                fragment_length <= current_length_remaining[0 +: 13] + 8;
            end else begin
                // the 16 here is tag + the extra 8 because nfragment count
                // has a minus 1.
                fragment_length <= {nfragment_count_i,3'b000} + 16;
            end
        end
        
        if (state == HEADER && m_hdr_tvalid && m_hdr_tready) begin
            // This is the last fragment
            if (current_length_remaining64 <= nfragment_count_i + 1) begin
                max_fragment_beats <= (current_length_remaining64[0 +: 13]);
            end else begin // this is a middle fragment
                max_fragment_beats <= nfragment_count_i + 1; // so dumb
            end                
        end
        
        
        // Calculate the remaining length
        if (state == IDLE && s_ctrl_tvalid && s_ctrl_tready)
           remaining_length <= s_ctrl_tdata[0 +: 20];
        else if (state == HEADER && m_hdr_tvalid && m_hdr_tready)
            remaining_length <= remaining_length - (fragment_length - 8);
        
        if (state == HEADER) fragment_beats <= {10{1'b0}};
        else if (state == STREAM && m_payload_tvalid && m_payload_tready)
            fragment_beats <= fragment_beats + 1;
        
        if (state == IDLE && s_ctrl_tvalid && s_ctrl_tready) begin
            address <= s_ctrl_tdata[20 +: 12];
            length <= s_ctrl_tdata[0 +: 20];
        end
        
        if (state == IDLE) fragment_number <= {10{1'b0}};
        else if (state == TAG && m_payload_tvalid && m_payload_tready) 
            fragment_number <= fragment_number + 1;                            
     end

    // state 2
    // fragment_beats 10
    // data 32
    // tlast 1
    // fragment number 10
    // m_payload_tready 1
    // s_data_tvalid 1
    // good enough, let's test it
    generate
        if (DEBUG == "TRUE") begin : ILA
            fragment_ila u_ila(.clk(aclk),
                               .probe0(state),              // 2
                               .probe1(fragment_beats),     // 10
                               .probe2(m_payload_tdata),     // 64
                               .probe3(m_payload_tready),   // 1
                               .probe4(m_payload_tvalid),   // 1
                               .probe5(m_payload_tlast),    // 1
                               .probe6(fragment_number),    // 10
                               .probe7(m_hdr_tready),       // 1
                               .probe8(remaining_length));  // 20
        end
    endgenerate
    
    assign m_hdr_tvalid = (state == HEADER);
    assign m_payload_tvalid = (state == TAG || (state == STREAM && s_data_tvalid));
    assign s_data_tready = (state == STREAM && m_payload_tready);
    assign s_ctrl_tready = (state == IDLE && event_was_ever_open);
    assign m_hdr_tdata = { event_ip, event_port, fragment_length };
    assign m_hdr_tuser = (BASE_PORT & ~fragsrc_mask_i) | (fragment_number & fragsrc_mask_i);
    assign m_payload_tdata = (state == TAG) ? tag : s_data_tdata;
    assign m_payload_tlast = (state == STREAM && last_payload);
    assign m_payload_tkeep = (state == STREAM) ? s_data_tkeep : 8'hFF;
endmodule

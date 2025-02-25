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
        // control interface
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_ctrl_ , 32 ),
        // data interface
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_data_ , 64 ),
        input [7:0] s_data_tkeep,
        input       s_data_tlast,
        
        // UDP header interface, without the global statics
        // (dscp/ecn/ttl/source port/dest ip/dest port)
        // Checksum is pointless, Ethernet does a CRC, so it's static
        // So tdata here is just length
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_hdr_ , 16),
        // source port.
        output [15:0] m_hdr_tuser,
        // UDP payload interface, I don't know what tuser does
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_payload_ , 64 ),
        output [7:0] m_payload_tkeep,
        output       m_payload_tuser,
        output       m_payload_tlast                
    );

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
    
    reg [9:0] fragment_beats = {10{1'b0}};
    reg [9:0] fragment_number = {10{1'b0}};
    reg [11:0] address = {12{1'b0}};
    reg [19:0] length = {20{1'b0}};
    reg [19:0] remaining_length = {20{1'b0}};
    reg [15:0] fragment_length = {16{1'b0}};

    wire [19:0] current_length_remaining = (state == IDLE) ? 
        s_ctrl_tdata[0 +: 20] : remaining_length;
    // round current length remaining
    wire [16:0] current_length_remaining64 =
        (current_length_remaining[2:0] != 3'b000) ?
        current_length_remaining[ 3 +: 16] + 1 :
        current_length_remaining[ 3 +: 16];

    wire [63:0] tag = { CONSTANT_0, CONSTANT_1, fragment_number, address, length };

    always @(posedge aclk) begin
        if (!aresetn) state <= IDLE;
        else begin
            case (state)
                IDLE: if (s_ctrl_tvalid && s_ctrl_tready) state <= HEADER;
                HEADER: if (m_hdr_tvalid && m_hdr_tready) state <= TAG;
                TAG: if (m_payload_tvalid && m_payload_tready) state <= STREAM;
                STREAM: if (m_payload_tvalid && m_payload_tready) begin
                    if (m_payload_tlast) state <= IDLE;
                    else if (fragment_beats == nfragment_count_i) state <= HEADER;
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

    assign m_hdr_tvalid = (state == HEADER);
    assign m_payload_tvalid = (state == TAG || (state == STREAM && s_data_tvalid));
    assign s_data_tready = (state == STREAM && m_payload_tready);
    assign s_ctrl_tready = (state == IDLE);
    assign m_hdr_tdata = fragment_length;
    assign m_hdr_tuser = (BASE_PORT & ~fragsrc_mask_i) | (fragment_number & fragsrc_mask_i);
    assign m_payload_tdata = (state == TAG) ? tag : s_data_tdata;
    assign m_payload_tlast = (state == STREAM && s_data_tlast);
    assign m_payload_tkeep = (state == STREAM) ? s_data_tkeep : 8'hFF;
endmodule

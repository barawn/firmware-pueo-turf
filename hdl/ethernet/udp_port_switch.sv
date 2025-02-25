`timescale 1ns / 1ps
`include "interfaces.vh"
// the UDP port switch uses a pair of axis_demuxes
// The first one takes the header info and switches it based on tdest
// (converting tdest into a select signal)
// the instant it's accepted it enables the second switch with the
// same select and passes a frame through there.
//
// PORT_MASK allows you to ignore certain bits in the port match
// BE DAMN CAREFUL these select INDEPENDENT ports!!
module udp_port_switch #(parameter NUM_PORT = 1,
                         parameter [16*NUM_PORT-1:0] PORTS = {16{1'b0}},
                         parameter [16*NUM_PORT-1:0] PORT_MASK = {16{1'b0}},
                         parameter PAYLOAD_WIDTH=64)(
                         
                         input aclk,
                         input aresetn,
                         
                         `TARGET_NAMED_PORTS_AXI4S_MIN_IF(s_udphdr_ , 64),
                         input [15:0] s_udphdr_tdest,
                         `TARGET_NAMED_PORTS_AXI4S_IF(s_udpdata_ , PAYLOAD_WIDTH),
                         
                         // these can't be macro'd, I need a multiplier macro, sigh
                         output [NUM_PORT*64-1:0] m_udphdr_tdata,
                         output [NUM_PORT-1:0] m_udphdr_tvalid,
                         input  [NUM_PORT-1:0] m_udphdr_tready,
                         output [16*NUM_PORT-1:0] m_udphdr_tdest,
                         // see above
                         output [NUM_PORT*PAYLOAD_WIDTH-1:0] m_udpdata_tdata,
                         output [NUM_PORT-1:0] m_udpdata_tvalid,
                         input [NUM_PORT-1:0] m_udpdata_tready,
                         output [NUM_PORT*(PAYLOAD_WIDTH/8)-1:0] m_udpdata_tkeep,
                         output [NUM_PORT-1:0] m_udpdata_tlast,
                         // these go high when a packet passes through a port
                         // helpful for statistics 
                         output [NUM_PORT-1:0] port_active                         
    );
    localparam [16*NUM_PORT-1:0] MATCH_VAL = PORTS & ~PORT_MASK;    
    localparam N_ENCODE_BITS = $clog2(NUM_PORT);
    reg [N_ENCODE_BITS-1:0] encode;    
    // one-hot encode first
    wire [15:0] masked_dest[NUM_PORT-1:0];
    wire [NUM_PORT-1:0] onehot_select;
    reg [NUM_PORT-1:0] port_active_reg = {NUM_PORT{1'b0}};
    wire drop_hdr;
    generate
        genvar i;        
        for (i=0;i<NUM_PORT;i=i+1) begin : MATCH
            assign masked_dest[i] = s_udphdr_tdest & ~PORT_MASK[16*i +: 16];
            assign onehot_select[i] = masked_dest[i] == MATCH_VAL[16*i +: 16];            
        end
    endgenerate
    assign drop_hdr = !(|onehot_select);

    integer j;
    always @(*) begin
        encode = {N_ENCODE_BITS{1'b0}};
        for (j=0;j<NUM_PORT;j=j+1) begin
            if (onehot_select[j]) encode = encode | j;
        end
    end
    
    reg enable_payload = 0;
    reg drop_payload = 0;
    reg [N_ENCODE_BITS-1:0] encode_payload = {N_ENCODE_BITS{1'b0}};
        
    // we map TDEST onto TUSER for the multiport guys
    axis_demux #(.M_COUNT(NUM_PORT),
                 .DATA_WIDTH(64),
                 .KEEP_ENABLE(0),
                 .USER_ENABLE(1),
                 .USER_WIDTH(16))
                 u_hdr_demux( .clk(aclk),.rst(!aresetn),
                    `CONNECT_AXI4S_MIN_IF( s_axis_ , s_udphdr_ ),
                    .s_axis_tuser( s_udphdr_tdest ),
                    .s_axis_tlast( 1'b1 ),
                    `CONNECT_AXI4S_MIN_IF( m_axis_ , m_udphdr_ ),
                    .m_axis_tuser( m_udphdr_tdest ),
                    .select(encode),
                    .drop(drop_hdr),
                    .enable(1'b1));

    always @(posedge aclk) begin
        if (s_udpdata_tvalid && s_udpdata_tready && s_udpdata_tlast)
            enable_payload <= 0;
        else if (s_udphdr_tvalid && s_udphdr_tready)
            enable_payload <= 1;
        
        if (s_udpdata_tvalid && s_udpdata_tready && s_udpdata_tlast) drop_payload <= 1'b0;
        else if (s_udphdr_tvalid && s_udphdr_tready) drop_payload <= drop_hdr;

        if (s_udphdr_tvalid && s_udphdr_tready) encode_payload <= encode;
        
        if (s_udphdr_tvalid && s_udphdr_tready)
            port_active_reg <= onehot_select;        
        else
            port_active_reg <= {NUM_PORT{1'b0}};
    end
    
    axis_demux #(.M_COUNT(NUM_PORT),
                 .DATA_WIDTH(PAYLOAD_WIDTH),
                 //keep/tlast are automatic
                 .USER_ENABLE(0))
                 u_data_demux( .clk(aclk),.rst(!aresetn),
                    `CONNECT_AXI4S_IF( s_axis_ , s_udpdata_ ),
                    `CONNECT_AXI4S_IF( m_axis_ , m_udpdata_ ),
                    .select(encode_payload),
                    .enable(enable_payload),
                    .drop(drop_payload));
                    
    assign port_active = port_active_reg;
    
endmodule

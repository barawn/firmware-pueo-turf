`timescale 1ns / 1ps
`include "interfaces.vh"
// UDP mux. This uses a single axis_arb_mux on the headers,
// and then an axis_mux on the data.

// You might ask, why don't we use the muxes in the verilog-ethernet path?
// They store WAAAY too much information for what we care about. These are heavily stripped down
// and much easier to deal with.
module udp_port_mux #(parameter NUM_PORT=1, parameter PAYLOAD_WIDTH=64)(
                        input aclk, 
                        input aresetn,
                        input [NUM_PORT*64-1:0] s_udphdr_tdata,
                        input [NUM_PORT-1:0] s_udphdr_tvalid,
                        output [NUM_PORT-1:0] s_udphdr_tready,
                        input [16*NUM_PORT-1:0] s_udphdr_tuser,
                        
                        input [NUM_PORT*PAYLOAD_WIDTH-1:0] s_udpdata_tdata,
                        input [NUM_PORT-1:0] s_udpdata_tvalid,
                        output [NUM_PORT-1:0] s_udpdata_tready,
                        input [NUM_PORT*(PAYLOAD_WIDTH/8)-1:0] s_udpdata_tkeep,
                        input [NUM_PORT-1:0] s_udpdata_tlast,
                        
                        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_udphdr_ , 64),
                        output [15:0] m_udphdr_tuser,
                        
                        `HOST_NAMED_PORTS_AXI4S_IF( m_udpdata_ , PAYLOAD_WIDTH),
                        
                        output [NUM_PORT-1:0] port_active
                        );

    localparam SELECT_BITS = $clog2(NUM_PORT);
    reg [NUM_PORT-1:0] port_active_reg = {NUM_PORT{1'b0}};
    reg [SELECT_BITS-1:0] data_select = {SELECT_BITS{1'b0}};
    reg data_enable = 0;
    wire last_committed = |(s_udpdata_tvalid & s_udpdata_tready & s_udpdata_tlast);
    
    wire [SELECT_BITS-1:0] selected_header;

    // I don't know if this is necessary. If the UDP core doesn't buffer headers,
    // it won't matter. But if it does, I would need to buffer the selects, and
    // I'm not going to bother doing that unless I need to. So I'll force this
    // to be one frame at a time.
    //
    // As in:
    // A UDP header comes in and goes through the mux
    // data_enable goes high, captures the selected header. Further UDP headers will not be allowed through.
    // Once the payload goes through, data_enable goes low and the next header can propagate.
    wire udphdr_tready_int;
    wire udphdr_tvalid_int;
    assign udphdr_tready_int = !data_enable && m_udphdr_tready;
    assign m_udphdr_tvalid = udphdr_tvalid_int && !data_enable;
    axis_arb_mux #(.S_COUNT(NUM_PORT),
                   .DATA_WIDTH(64),
                   .KEEP_ENABLE(0),
                   .ID_ENABLE(1),
                   .S_ID_WIDTH(0),
                   .USER_ENABLE(1),
                   .USER_WIDTH(16),
                   .LAST_ENABLE(0),
                   .UPDATE_TID(1))
                   u_hdr_mux( .clk(aclk), .rst(!aresetn),
                              `CONNECT_AXI4S_MIN_IF( s_axis_ , s_udphdr_ ),
                              .s_axis_tuser( s_udphdr_tuser ),
                              // can't macro this because we screw with the valid/ready
                              .m_axis_tdata( m_udphdr_tdata ),
                              .m_axis_tready(udphdr_tready_int),
                              .m_axis_tvalid(udphdr_tvalid_int),
                              .m_axis_tuser( m_udphdr_tuser ),
                              .m_axis_tid( selected_header ));
    integer i;
    always @(posedge aclk) begin
        if (m_udphdr_tvalid && m_udphdr_tready) begin
            for (i=0;i<NUM_PORT;i=i+1) if (selected_header == i) port_active_reg[i] <= 1'b1;
                                       else port_active_reg[i] <= 1'b0;
        end else port_active_reg <= {NUM_PORT{1'b0}};

        if (m_udphdr_tvalid && m_udphdr_tready) data_select <= selected_header;
        if (last_committed) data_enable <= 0;
        else if (m_udphdr_tvalid && m_udphdr_tready) data_enable <= 1;
    end
    
    axis_mux #(.S_COUNT(NUM_PORT),
               .DATA_WIDTH(PAYLOAD_WIDTH),
               .ID_ENABLE(0),
               .USER_ENABLE(0))
               u_data_mux( .clk(aclk),.rst(!aresetn),
                            `CONNECT_AXI4S_IF( s_axis_ , s_udpdata_ ),
                            `CONNECT_AXI4S_IF( m_axis_ , m_udpdata_ ),
                            .enable(data_enable),
                            .select(data_select));   
    assign port_active = port_active_reg;
                                  
endmodule

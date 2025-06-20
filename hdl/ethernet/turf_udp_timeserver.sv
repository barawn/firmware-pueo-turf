`timescale 1ns / 1ps
// make Cosmin happy
`include "interfaces.vh"
module turf_udp_timeserver #(parameter ACLKTYPE="NONE")(
        input aclk,
        input aresetn,
        // IP/port/length
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_udphdr_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_IF( s_udpdata_ , 64 ),
        // IP/port/length
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_udphdr_ , 64 ),
        `HOST_NAMED_PORTS_AXI4S_IF( m_udpdata_ , 64 ),
        input sysclk_i,
        // sysclk flag
        input pps_i,
        // this is in sysclk
        input [31:0] cur_sec_i        
    );
    
//            this_ip <= s_udphdr_tdata[32 +: 32];
//           this_port <= s_udphdr_tdata[16 +: 16];

    // I ignore you
    assign s_udpdata_tready = 1'b1;
    // We ALWAYS accept packets, even if we throw them away!!
    assign s_udphdr_tready = 1'b1;

    // ok: so we sit in IDLE and when there's any valid request,
    // we jump to WAIT_PPS to wait for the next one. We ALSO
    // toggle a FF so we know the boundary between ones that
    // came in BEFORE we started sending and ones that came in AFTER.
    // The ones that come in AFTER have to wait for the NEXT pps.
    // Because we change it at the PPS we read until there are no more
    // valid OR fifo_dout[48] == pps_toggle.
    (* CUSTOM_CC_DST = ACLKTYPE *)
    reg [31:0] cur_sec_holding = {32{1'b0}};

    reg pps_toggle = 0;
    // delay PPS by one second so that the new second has arrived
    reg pps_rereg = 0;
    always @(posedge sysclk_i) pps_rereg <= pps_i;
    // flag in our domain
    wire pps_flag_aclk;
    flag_sync u_pps_sync(.in_clkA(pps_rereg),.out_clkB(pps_flag_aclk),
                         .clkA(sysclk_i),.clkB(aclk));

    wire [48:0] fifo_din = { pps_toggle, s_udphdr_tdata[16 +: 48] };
    wire        fifo_prog_full;
    wire        fifo_write = s_udphdr_tvalid && !fifo_prog_full;
    
    wire [48:0] fifo_dout;
    wire        fifo_valid;
    wire        fifo_read = m_udphdr_tvalid && m_udphdr_tready;
    
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WAIT_FIRST_HDR = 1;
    localparam [FSM_BITS-1:0] WAIT_DATA = 2;
    localparam [FSM_BITS-1:0] WAIT_HDR = 3;
    reg [FSM_BITS-1:0] state = IDLE;

    always @(posedge aclk) begin
        // buy time for the data to cross
        if (state == WAIT_FIRST_HDR && m_udphdr_tvalid && m_udphdr_tready) 
            cur_sec_holding <= cur_sec_i;
            
        // The pps toggle acts to separate requests between
        // seconds.
        if (fifo_valid && pps_flag_aclk && state == IDLE)
            pps_toggle <= ~pps_toggle;

        // We always process events if there are any pending
        // near the second. There is exactly a 1 clock window
        // where a request could come in near the PPS and still
        // sneak in along with a different request. I don't care.
        // It's good enough. At that point it'll be fine anyway.
        case (state)
            IDLE: if (fifo_valid && pps_flag_aclk) state <= WAIT_FIRST_HDR;
            WAIT_FIRST_HDR: if (m_udphdr_tvalid && m_udphdr_tready) state <= WAIT_DATA;
            WAIT_DATA: if (m_udpdata_tvalid && m_udpdata_tready && m_udpdata_tlast) begin
                if (fifo_valid && (fifo_dout[48] != pps_toggle)) state <= WAIT_HDR;
                else state <= IDLE;                
            end
            WAIT_HDR: if (m_udphdr_tvalid && m_udphdr_tready) state <= WAIT_DATA;
        endcase
    end

    udp_timeserver_fifo u_fifo(.clk(aclk),
                               .srst(!aresetn),
                               .din(fifo_din),
                               .wr_en(fifo_write),
                               .prog_full(fifo_prog_full),
                               .dout(fifo_dout),
                               .valid(fifo_valid),
                               .rd_en(fifo_read));

    wire [31:0] cur_sec_nbo = { cur_sec_holding[7:0], 
                                cur_sec_holding[15:8],
                                cur_sec_holding[23:16],
                                cur_sec_holding[31:24] }; 
    assign m_udpdata_tdata = { {32{1'b0}}, cur_sec_nbo };
    assign m_udpdata_tkeep = { {4{1'b0}}, {4{1'b1}} };
    assign m_udpdata_tlast = 1'b1;
    assign m_udpdata_tvalid = (state == WAIT_DATA);
    
    assign m_udphdr_tdata = { fifo_dout[0 +: 48], 16'd4 };
    assign m_udphdr_tvalid = (state == WAIT_HDR || state == WAIT_FIRST_HDR);
    
endmodule

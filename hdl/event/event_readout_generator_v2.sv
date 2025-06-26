`timescale 1ns / 1ps
`include "interfaces.vh"
`include "mem_axi.vh"
// readout generator
// this is the super-simple readout generator for now:
// we take in all the completion streams, wait for them to become
// valid along with the datamover command input being ready.
// Once they're all ready we then check to issue an s_ev_ctrl
// to the fragment generator.
//
// The datamover's MM2S output stream is passed through a
// resizer and a 64-bit FIFO heading to the fragment generator.
//
// The readout generator ALSO needs to take in the nack stream:
// if a nack is received, it has priority and gets pushed out.
//
// We don't handle the ack stream directly - it's broadcast
// to the req gens and header accumulator - but we DO take in
// an allow flag which increments a counter indicating how many
// in flight events we can run with. When all the completions are
// ready, we wait until this counter is positive and then issue
// a command, which decrements the counter.
//
// Nacks either tell us to generate a missing fragment or possibly
// the whole event.
//
// FFS IDIOT THESE NEED TO ACCEPT TIO MASKS

// Goddamnit, we need to *buffer* the completions!
// And they're huge! And we need to buffer 4096 of them!
// Let's look to see how we do this.
// We ALWAYS just compress each of the inputs into an error.
// So we don't even need giant ones there, we can compress
// before even going into a "little" FIFO.
module event_readout_generator_v2(
        input memclk,
        input memresetn,
        // THESE ARE COMPLETIONS: WE NEED A TIO MASK TOO
        input [3:0] tio_mask_i,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr_ , 24 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t0_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t1_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t2_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t3_ , 64 ),
        
        `M_AXIM_PORT( m_axi_ , 1 ),
        // THIS HAS TO BE CROSSED OVER TO MEMCLK
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_nack_ , 48 ),
        // FLAG IN MEMCLK
        input allow_i,
        // FOR MONITORING
        output [12:0] allow_count_o,
        // THIS IS ETHCLK NOT AURORA CLOCK
        input aclk,
        input aresetn,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_ctrl_ , 32 ),
        `HOST_NAMED_PORTS_AXI4S_IF( m_data_ , 64 ),
        output any_err_o,
        output [12:0] cmpl_count_o  
    );
    
    parameter MEMCLKTYPE = "NONE";
    parameter ACLKTYPE = "NONE";
    parameter DEBUG = "TRUE";
    
    // I seriously need to make these both *calculable*
    parameter [18:0] START_OFFSET = 19'h03F00;
    parameter [18:0] BTT = 19'd459008;
    // decode nack structure
    // allow is ignored (bit 47), it comes from the done broadcaster.
    wire full_event = s_nack_tdata[46] || !s_nack_tvalid;
    // nack_tdata is in qwords, so upshift it by 3, leaving 5 top bits
    wire [18:0] nack_btt = { {5{1'b0}}, s_nack_tdata[32 +: 11], 3'b000 };
    wire [18:0] nack_offset = s_nack_tdata[0 +: 19];
    wire [11:0] nack_upper_addr = s_nack_tdata[20 +: 12];
    // either BTT or nack_btt
    (* CUSTOM_CC_SRC = MEMCLKTYPE *)
    reg [18:0] event_bytes = {19{1'b0}};
    // in aclk domain
    (* CUSTOM_CC_DST = ACLKTYPE *)
    reg [18:0] event_bytes_aclk = {19{1'b0}};
    
    // this is the event_bytes field filled out to what the DataMover wants
    wire [22:0] cmd_btt = { {4{1'b0}}, event_bytes };
    // either s_hdr_tdata[8 +: 13], {19{1'b0}} + START_OFFSET
    // or     nack_upper_addr, nack_offset[18:0] & {19{!full_event_nack}} + START_OFFSET
    // = { (s_nack_tvalid ? nack_upper_addr : upper_addr), (full_event ? {19{1'b0}}, nack_offset }} + START_OFFSET
    reg [18:0] event_lower_addr = {19{1'b0}};
    // we can handle as many events in flight as possible
    reg [12:0] allow_counter = {13{1'b0}};
    assign allow_count_o = allow_counter;
    
    
    // pipeline the comparison. there's no race here because we can't *decrease*
    // until we pass the gate, and once we pass the gate it will take much longer than 1 clock
    // to recheck it.
    reg is_allowed = 0;        
    // this is a nack readout
    reg nack_readout = 0;

    `DEFINE_AXI4S_MIN_IF( cmpl_ , 16 );
    
    event_completion_collector #(.MEMCLKTYPE(MEMCLKTYPE)) 
            u_cmpl_collector(.memclk(memclk),
                             .memresetn(memresetn),
                             .err_any_o(any_err_o),
                             .cmpl_count_o(cmpl_count_o),
                             .tio_mask_i(tio_mask_i),
                             `CONNECT_AXI4S_MIN_IF( s_hdr_ , s_hdr_ ),
                             `CONNECT_AXI4S_MIN_IF( s_t0_ , s_t0_ ),
                             `CONNECT_AXI4S_MIN_IF( s_t1_ , s_t1_ ),
                             `CONNECT_AXI4S_MIN_IF( s_t2_ , s_t2_ ),
                             `CONNECT_AXI4S_MIN_IF( s_t3_ , s_t3_ ),
                             `CONNECT_AXI4S_MIN_IF( m_cmpl_ , cmpl_ ));

    `DEFINE_AXI4S_MIN_IF( cmd_ , 72 );    
    `DEFINE_AXI4S_MIN_IF( stat_ , 8);
    
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] ISSUE_CMD = 1;
    localparam [FSM_BITS-1:0] ISSUE_CONTROL = 2;
    localparam [FSM_BITS-1:0] DONE = 3;
    reg [FSM_BITS-1:0] state = IDLE;

    // stat_tready is whenever we're in done
    assign stat_tready = (state == DONE);

    // cmpl_tready 
    reg cmpl_tready_reg = 0;    
    assign cmpl_tready = cmpl_tready_reg;
    reg nack_tready = 0;
    
    // note that the top bit of the upper addr never gets
    // sent along due to stupidity, and it never gets pulled
    // back in from acks either.

    // = { upper_addr, (full_event ? {19{1'b0}}, nack_offset }} + START_OFFSET
    // when (state == IDLE) if s_nack_tvalid = nack_upper_addr else from completion 
    (* CUSTOM_CC_SRC = MEMCLKTYPE *)
    reg [12:0] upper_addr = {13{1'b0}};
    (* CUSTOM_CC_DST = ACLKTYPE *)
    reg [12:0] upper_addr_aclk = {13{1'b0}};    

    wire [31:0] cmd_full_addr = { upper_addr , event_lower_addr };
    wire [7:0] cmd_upper_byte = {8{1'b0}};
    wire [31:0] cmd_lower_command = 
        {
            1'b0,   // no drr
            1'b1,   // yes tlast
            6'b000000, // no dre
            1'b1,   // incrementing
            cmd_btt };  // 23-bit bytes to transfer
    assign cmd_tvalid = (state == ISSUE_CMD);
    assign cmd_tdata = { cmd_upper_byte, cmd_full_addr, cmd_lower_command };

    reg    control_issued = 0;
    wire   issue_control_memclk = (state == ISSUE_CONTROL && !control_issued);
    wire   issue_control_aclk;
    reg    control_valid_aclk = 0;
    reg    control_complete_aclk = 0;
    wire   control_complete_memclk;    

    // ffs this is NOT static. 12 bits at top, + 1 spare, + 19 bits bottom
    // 19 bits bottom is event_bytes.
    
    // DUMBASS THIS IS IN ETHCLK DOMAIN, BOTH NEED TO BE ETHCLK!!!
    assign m_ctrl_tdata = { upper_addr_aclk[11:0], 1'b0, event_bytes_aclk };
    assign m_ctrl_tvalid = control_valid_aclk;

    always @(posedge memclk) begin
        if (!memresetn) begin
            allow_counter <= {13{1'b0}};
        end else begin
            if (allow_i && !(cmd_tready && cmd_tvalid && !nack_readout))
                allow_counter <= allow_counter + 1;
            else if (!allow_i && cmd_tready && cmd_tvalid && !nack_readout)     
                allow_counter <= allow_counter - 1;
        end
        // this could _probably_ be merged into something
        // but WHATEVER
        if (!memresetn) is_allowed <= 0;
        else is_allowed <= (allow_counter != {13{1'b0}});
            
        // how did this get screwed up again??!?
        // we don't need to ack cmpl_tready in IDLE. We can just ack when
        // we issue the command if it's not a nack command.
        cmpl_tready_reg <= memresetn && cmd_tvalid && cmd_tready && !nack_readout;
        nack_tready <= memresetn && cmd_tvalid && cmd_tready && nack_readout;
        
        // I don't need a memresetn clause here it should happen automatically.
        if (state == IDLE) begin
            // upper addr stays static through the transfer, so just capture it
            // when idle. It'll get pushed out in aclk in issue_control.
            // force top bit to zero here due to stupidity
            if (s_nack_tvalid) upper_addr <= {1'b0, nack_upper_addr};
            else upper_addr <= {1'b0, cmpl_tdata[0 +: 12]};
            
            // nack readout stays static through transfer
            nack_readout <= s_nack_tvalid;
            // determine readout length.
            if (full_event)
                event_bytes <= BTT;
            else
                event_bytes <= nack_btt;
            // determine start address (except top addr)
            if (full_event)
                event_lower_addr <= START_OFFSET;
            else
                event_lower_addr <= nack_offset + START_OFFSET;                                        
        end
        
        if (!memresetn) state <= IDLE;
        else begin
            case(state)
                IDLE: if (s_nack_tvalid || (cmpl_tvalid && is_allowed))
                    state <= ISSUE_CMD;
                ISSUE_CMD: if (cmd_tready) state <= ISSUE_CONTROL;
                ISSUE_CONTROL: if (control_complete_memclk) state <= DONE;
                DONE: if (stat_tvalid) state <= IDLE;
            endcase
        end

        // ffs you have to make sure this stays high to generate a flag idiot
        control_issued <= (state == ISSUE_CONTROL);
    end
    
    always @(posedge aclk) begin
        if (issue_control_aclk) upper_addr_aclk <= upper_addr;
        if (issue_control_aclk) event_bytes_aclk <= event_bytes;
        
        if (!aresetn) control_valid_aclk <= 1'b0;
        else begin
            if (issue_control_aclk) control_valid_aclk <= 1;
            else if (m_ctrl_tready) control_valid_aclk <= 0;
        end

        control_complete_aclk <= m_ctrl_tvalid && m_ctrl_tready;
    end

    flag_sync u_issue_sync(.in_clkA(issue_control_memclk),.out_clkB(issue_control_aclk),
                           .clkA(memclk),.clkB(aclk));
    flag_sync u_complete_sync(.in_clkA(control_complete_aclk),.out_clkB(control_complete_memclk),
                           .clkA(aclk),.clkB(memclk));
    
    // to our fifo. we only use 65 bits because tkeep should always be high.
    `DEFINE_AXI4S_IF( evin_ , 64 );

    wire [64:0] evfifo_din = { evin_tlast, evin_tdata };
    wire        evfifo_write = (evin_tready && evin_tvalid);
    wire        evfifo_full;
    assign      evin_tready = !evfifo_full;

    wire [64:0] evfifo_dout;
    wire        evfifo_read = (m_data_tvalid && m_data_tready);
    wire        evfifo_valid;
    assign      m_data_tvalid = evfifo_valid;
    assign      m_data_tkeep = {8{1'b1}};
    assign      m_data_tdata = evfifo_dout[63:0];
    assign      m_data_tlast = evfifo_dout[64];

    assign      s_nack_tready = nack_tready;
    
    // debug:
    // state (2)
    // tfio_tvalid (4)
    // hdr_tvalid (1)
    // m_ctrl_tvalid
    // m_ctrl_tready
    // m_data_tvalid
    // m_data_tready
    wire mm2s_err;
    generate
        if (DEBUG == "TRUE") begin : ILA
            wire [3:0] tfio_tvalid_vec = { s_t3_tvalid,
                                           s_t2_tvalid,
                                           s_t1_tvalid,
                                           s_t0_tvalid };                                           
            event_readout_ila u_ila(.clk(memclk),
                                    .probe0(state),
                                    .probe1(tfio_tvalid_vec),
                                    .probe2(s_hdr_tvalid),
                                    .probe3(issue_control_memclk),
                                    .probe4(control_complete_memclk),
                                    .probe5(evin_tvalid),
                                    .probe6(evin_tready),
                                    .probe7(stat_tdata),
                                    .probe8(stat_tvalid),
                                    .probe9(stat_tready),
                                    .probe10(upper_addr[11:0]),
                                    .probe11(full_event),
                                    .probe12(s_nack_tvalid),
                                    .probe13(mm2s_err),
                                    .probe14(m_axi_arvalid),
                                    .probe15(m_axi_arready),
                                    .probe16(m_axi_rvalid),
                                    .probe17(m_axi_rready),
                                    .probe18(allow_counter),
                                    .probe19(allow_i),
                                    .probe20(cmpl_count_o));
        end
    endgenerate
      
    event_datamover u_datamover( .m_axi_mm2s_aclk( memclk ),
                                 .m_axi_mm2s_aresetn( memresetn ),
                                 .m_axis_mm2s_cmdsts_aclk( memclk ),
                                 .m_axis_mm2s_cmdsts_aresetn( memresetn ),
                                 `CONNECT_AXI4S_MIN_IF( s_axis_mm2s_cmd_ , cmd_ ),
                                 `CONNECT_AXI4S_MIN_IF( m_axis_mm2s_sts_ , stat_ ),
                                 `CONNECT_AXI4S_IF( m_axis_mm2s_ , evin_ ),
                                 `CONNECT_AXIM_R( m_axi_mm2s_ , m_axi_ ),
                                 .mm2s_err(mm2s_err));

    `AXIM_NO_WRITES( m_axi_ );
    
    event_out_fifo u_outfifo( .wr_clk(memclk),
                              .srst(!memresetn),
                              .din(evfifo_din),
                              .wr_en(evfifo_write),
                              .full(evfifo_full),
                              .rd_clk(aclk),
                              .dout(evfifo_dout),
                              .rd_en(evfifo_read),
                              .valid(evfifo_valid));
                
    
endmodule

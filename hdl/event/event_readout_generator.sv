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
module event_readout_generator(
        input memclk,
        input memresetn,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr_ , 24 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t0_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t1_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t2_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t3_ , 64 ),
        
        `M_AXIM_PORT( m_axi_ , 1 ),
        
        // THIS IS ETHCLK NOT AURORA CLOCK
        input aclk,
        input aresetn,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_ctrl_ , 32 ),
        `HOST_NAMED_PORTS_AXI4S_IF( m_data_ , 64 ),
        
        output any_err_o       
    );
    
    parameter MEMCLKTYPE = "NONE";
    parameter ACLKTYPE = "NONE";
    
    localparam [18:0] START_OFFSET = 19'h03E00;
    localparam [18:0] BTT = 19'd459008;
    localparam [22:0] CMD_BTT = { {4{1'b0}}, BTT };
    
    wire all_valid = (s_hdr_tvalid && 
                      s_t0_tvalid &&
                      s_t1_tvalid &&
                      s_t2_tvalid &&
                      s_t3_tvalid );
    `DEFINE_AXI4S_MIN_IF( cmd_ , 72 );
    
    `DEFINE_AXI4S_MIN_IF( stat_ , 8);
    
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] ISSUE_CMD = 1;
    localparam [FSM_BITS-1:0] ISSUE_CONTROL = 2;
    localparam [FSM_BITS-1:0] DONE = 3;
    reg [FSM_BITS-1:0] state = IDLE;

    reg cmpl_tready = 0;
    assign s_hdr_tready = cmpl_tready;
    assign s_t0_tready = cmpl_tready;
    assign s_t1_tready = cmpl_tready;
    assign s_t2_tready = cmpl_tready;
    assign s_t3_tready = cmpl_tready;
    
    // note that the top bit of the upper addr never gets
    // sent along due to stupidity, and it never gets pulled
    // back in from acks either.
    (* CUSTOM_CC_SRC = MEMCLKTYPE *)
    reg [12:0] upper_addr = {13{1'b0}};
    (* CUSTOM_CC_DST = ACLKTYPE *)
    reg [12:0] upper_addr_aclk = {13{1'b0}};    

    wire [31:0] cmd_full_addr = { upper_addr, START_OFFSET };
    wire [7:0] cmd_upper_byte = {8{1'b0}};
    wire [31:0] cmd_lower_command = 
        {
            1'b0,   // no drr
            1'b1,   // yes tlast
            6'b000000, // no dre
            1'b1,   // incrementing
            CMD_BTT };  // 23-bit bytes to transfer
    assign cmd_tvalid = (state == ISSUE_CMD);

    reg    control_issued = 0;
    wire   issue_control_memclk = (state == ISSUE_CONTROL && !control_issued);
    wire   issue_control_aclk;
    reg    control_valid_aclk = 0;
    reg    control_complete_aclk = 0;
    wire   control_complete_memclk;    


    assign m_ctrl_data = { upper_addr_aclk[11:0], 1'b0, BTT };
    assign m_ctrl_tvalid = control_valid_aclk;
    
    reg any_error_seen = 0;
    assign any_err_o = any_error_seen;
    // TURFIO completion indicators are awkward so pipeline it
    wire t0_error = (|s_t0_tdata[31:0]) && s_t0_tvalid && s_t0_tready;
    wire t1_error = (|s_t1_tdata[31:0]) && s_t1_tvalid && s_t1_tready;
    wire t2_error = (|s_t2_tdata[31:0]) && s_t2_tvalid && s_t2_tready;
    wire t3_error = (|s_t3_tdata[31:0]) && s_t3_tvalid && s_t3_tready;
    wire thdr_error = (|s_hdr_tdata[7:0]) && s_hdr_tvalid && s_hdr_tready;
    
    reg t0_error_reg = 0;
    reg t1_error_reg = 0;
    reg t2_error_reg = 0;
    reg t3_error_reg = 0;
    reg thdr_error_reg = 0;

    always @(posedge memclk) begin
        if (!memresetn) begin
            any_error_seen <= 0;
            t0_error_reg <= 0;
            t1_error_reg <= 0;
            t2_error_reg <= 0;
            t3_error_reg <= 0;
            thdr_error_reg <= 0;
        end begin
            if (t0_error) t0_error_reg <= 1;
            if (t1_error) t1_error_reg <= 1;
            if (t2_error) t2_error_reg <= 1;
            if (t3_error) t3_error_reg <= 1;
            if (thdr_error) thdr_error_reg <= 1;
            any_error_seen <= (t0_error_reg || t1_error_reg || 
                               t2_error_reg || t3_error_reg || thdr_error_reg);
        end
    
        cmpl_tready <= memresetn && all_valid && (state == IDLE);
    
        if (!memresetn) state <= IDLE;
        else begin
            case(state)
                IDLE: if (all_valid) state <= ISSUE_CMD;
                ISSUE_CMD: if (cmd_tready) state <= ISSUE_CONTROL;
                ISSUE_CONTROL: if (control_complete_memclk) state <= DONE;
                DONE: if (stat_tvalid) state <= IDLE;
            endcase
        end
        if (state == IDLE && all_valid)
            upper_addr <= s_hdr_tdata[8 +: 13];

        control_issued <= issue_control_memclk;
    end
    
    always @(posedge aclk) begin
        if (issue_control_aclk) upper_addr_aclk <= upper_addr;
    
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
    assign      evfifo_tready = !evfifo_full;

    wire [64:0] evfifo_dout;
    wire        evfifo_read = (m_data_tvalid && m_data_tready);
    wire        evfifo_tvalid;
    assign      m_data_tvalid = evfifo_tvalid;
    assign      m_data_tkeep = {8{1'b1}};
    assign      m_data_tdata = evfifo_dout[63:0];
    assign      m_data_tlast = evfifo_dout[64];
    
    event_datamover u_datamover( .m_axi_mm2s_aclk( memclk ),
                                 .m_axi_mm2s_aresetn( memresetn ),
                                 .m_axis_mm2s_cmdsts_aclk( memclk ),
                                 .m_axis_mm2s_cmdsts_aresetn( memresetn ),
                                 `CONNECT_AXI4S_MIN_IF( s_axis_mm2s_cmd_ , cmd_ ),
                                 `CONNECT_AXI4S_MIN_IF( m_axis_mm2s_sts_ , stat_ ),
                                 `CONNECT_AXI4S_IF( m_axis_mm2s_ , evin_ ),
                                 `CONNECT_AXIM_R( m_axi_mm2s_ , m_axi_ ));

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

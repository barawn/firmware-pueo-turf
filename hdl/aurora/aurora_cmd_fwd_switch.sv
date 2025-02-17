`timescale 1ns / 1ps
`include "interfaces.vh"
// UFC message forward-and-switch.
//
// Outbound interface has two paths: a "UFC" path and a "data" path.
// We cannot assert UFC valid until all the data arrives: when
// we get all the data, we assert the first data beat along with m_ufc_tvalid,
// and upon receiving tready we present all remaining data beats.
// We only accept 1 beat and 2 beat transactions. If a user sends more,
// everything between the first beat and last beat will be dropped.
module aurora_cmd_fwd_switch(
        input aclk,
        input aresetn,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_axis_ , 32 ),
        input [1:0] s_axis_tdest,
        input s_axis_tlast,
        
        // data path. This has funky rules.
        output [32*4-1:0] cmd_tdata,
        // This is a proper AXI4-Stream (vector) path. It indicates the
        // length.
        output [8*4-1:0] m_axis_tdata,
        output [3:0] m_axis_tvalid,
        input [3:0] m_axis_tready
    );
    
    // okay, is there an easier way to do this?
    // maybe? We only really need 3 states and one auxiliary bit
    // in the first state, we don't have to assert tready:
    // we can assign tready = tvalid && !tlast
    // then have that set stored_data_valid
    // then have a single UFC_TX state
    // which looks for (!stored_data_valid) to jump back to DATA_BEAT
    // and have stored_data_valid clear in UFC_TX, meaning the
    // state flow would be
    // state        s_axis_tvalid   s_axis_tlast    ufc_tvalid  ufc_tready  stored_data_valid s_axis_tready s_axis_tdata cmd_tdata
    // DATA_BEAT    1               0               0           x           0                 1             A            x
    // DATA_BEAT    1               1               0           x           1                 0             B            x
    // UFC_REQUEST  1               1               1           0           1                 0             B            x
    // UFC_REQUEST  1               1               1           1           1                 0             B            x
    // UFC_TX       1               1               0           x           1                 0             B            A
    // UFC_TX       1               1               0           x           0                 1             B            B
    // and then the single-beat state flow is
    // state        s_axis_tvalid   s_axis_tlast    ufc_tvalid  ufc_tready  stored_data_valid s_axis_tready s_axis_tdata cmd_tdata
    // DATA_BEAT    1               1               0           x           0                 0             A            x
    // UFC_REQUEST  1               1               1           0           0                 0             A            x
    // UFC_REQUEST  1               1               1           1           0                 0             A            x
    // UFC_TX       1               1               0           x           0                 1             A            A
    //
    // Logic-wise, the output data then works out to be
    // wire [31:0] out_data = (stored_data_valid) ? stored_data : s_axis_tdata
    // and the only other complicated one is s_axis_tready, which is
    // assign s_axis_tready = (state == DATA_BEAT) && !s_axis_tlast) ||
    //                        (state == UFC_TX && !stored_data_valid);
    // and then the out_size is just 1'b0, stored_data_valid, 1'b1.

    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] DATA_BEAT = 0;
    localparam [FSM_BITS-1:0] UFC_REQUEST = 1;
    localparam [FSM_BITS-1:0] UFC_TX = 2;
    reg [FSM_BITS-1:0] state = DATA_BEAT;
    
    reg [31:0] stored_data = {32{1'b0}};
    reg        stored_data_valid = 1'b0;    
    reg [1:0]  destination = 2'b00;
    
    wire ufc_tready = m_axis_tready[destination];

    wire [31:0] out_data = (stored_data_valid) ? stored_data : s_axis_tdata;
    // out_valid only goes high during the UFC transaction state.
    wire out_valid = (state == UFC_REQUEST);
    // this is the UFC transaction output data
    wire [7:0] out_size = (stored_data_valid) ? 8'd3 : 8'd1;
    
    always @(posedge aclk) begin
        if (!aresetn) state <= DATA_BEAT;
        else case (state)
            // we only move on from data_beat when tlast is asserted.
            // that can either happen after we've pre-stored data or right away.
            // This means only the *last two* inputs will be presented.
            DATA_BEAT: if (s_axis_tvalid && s_axis_tlast) state <= UFC_REQUEST;
            UFC_REQUEST: if (ufc_tready) state <= UFC_TX;
            UFC_TX: if (!stored_data_valid) state <= DATA_BEAT;
        endcase
        
        if (state == DATA_BEAT && s_axis_tvalid && s_axis_tready)
            stored_data <= s_axis_tdata;
    
        if (!aresetn) stored_data_valid <= 1'b0;
        else if (state == DATA_BEAT && s_axis_tvalid && s_axis_tready)
            stored_data_valid <= 1'b1;
        else if (state == UFC_TX)
            stored_data_valid <= 1'b0;
        
        if (state == DATA_BEAT && s_axis_tvalid)
            destination <= s_axis_tdest;                    
    end

    assign s_axis_tready = (state == DATA_BEAT && !s_axis_tlast) || (state == UFC_TX && !stored_data_valid);

    assign cmd_tdata = {4{out_data}};
    assign m_axis_tvalid[0] = (destination == 2'd0) && out_valid;
    assign m_axis_tvalid[1] = (destination == 2'd1) && out_valid;
    assign m_axis_tvalid[2] = (destination == 2'd2) && out_valid;
    assign m_axis_tvalid[3] = (destination == 2'd3) && out_valid;
    assign m_axis_tdata = {4{out_size}};
endmodule

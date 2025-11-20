`timescale 1ns / 1ps
module notch_remote_control #(parameter CLKTYPE = "NONE")(
        input clk_i,
        input [23:0] notch0_state_i,
        input [23:0] notch1_state_i,
        input do_notch_i,
        output notch_complete_o,

        input [31:0] cur_time_i,
        output [31:0] notch_time_o,
        
        output notch_pending_o,
        output [31:0] notch_dat_o,
        input notch_ack_i        
    );
    (* CUSTOM_CC_DST = CLKTYPE *)
    reg [31:0] notch_data = {32{1'b0}};

    // OK - so we're not even worrying about the
    // cross-clock nature here, because this data
    // *will be static* every time it's read.
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg [31:0] notch_cur_time = {32{1'b0}};

    localparam FSM_BITS=3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] NOTCH0_PENDING = 1;
    localparam [FSM_BITS-1:0] NOTCH0_ACK = 2;
    localparam [FSM_BITS-1:0] NOTCH1_PENDING = 3;
    localparam [FSM_BITS-1:0] NOTCH1_ACK = 4;
    localparam [FSM_BITS-1:0] NOTCH_UPDATE_PENDING = 5;
    localparam [FSM_BITS-1:0] NOTCH_UPDATE_ACK = 6;
    reg [FSM_BITS-1:0] state = IDLE;
    
    always @(posedge clk_i) begin
        case (state)
            IDLE: if (do_notch_i) state <= NOTCH0_PENDING;
            NOTCH0_PENDING: if (notch_ack_i) state <= NOTCH0_ACK;
            NOTCH0_ACK: state <= NOTCH1_PENDING;
            NOTCH1_PENDING: if (notch_ack_i) state <= NOTCH1_ACK;
            NOTCH1_ACK: state <= NOTCH_UPDATE_PENDING;
            NOTCH_UPDATE_PENDING: if (notch_ack_i) state <= NOTCH_UPDATE_ACK;
            NOTCH_UPDATE_ACK: state <= IDLE;
        endcase

        if (state == NOTCH_UPDATE_ACK) notch_cur_time <= cur_time_i;
        
        if (state == IDLE && do_notch_i) begin
            // TURFIO 0 gets bits [5:0]
            notch_data[00 +: 8] <= { 1'b1, 1'b0, notch0_state_i[0 +: 6] };
            // TURFIO 1 gets bits [11:6]
            notch_data[08 +: 8] <= { 1'b1, 1'b0, notch0_state_i[6 +: 6] };
            // TURFIO 2 gets bits [27:22]
            notch_data[16 +: 8] <= { 1'b1, 1'b0, notch0_state_i[18 +: 6] };
            // TURFIO 3 gets bits [21:12]
            notch_data[24 +: 8] <= { 1'b1, 1'b0, notch0_state_i[12 +: 6] };
        end else if (state == NOTCH0_ACK) begin
            // TURFIO 0 gets bits [5:0]
            notch_data[00 +: 8] <= { 1'b1, 1'b1, notch1_state_i[0 +: 6] };
            // TURFIO 1 gets bits [11:6]
            notch_data[08 +: 8] <= { 1'b1, 1'b1, notch1_state_i[6 +: 6] };
            // TURFIO 2 gets bits [27:22]
            notch_data[16 +: 8] <= { 1'b1, 1'b1, notch1_state_i[18 +: 6] };
            // TURFIO 3 gets bits [21:12]
            notch_data[24 +: 8] <= { 1'b1, 1'b1, notch1_state_i[12 +: 6] };
        end else if (state == NOTCH1_ACK) begin
            notch_data[00 +: 8] <= 8'h04;
            notch_data[08 +: 8] <= 8'h04;
            notch_data[16 +: 8] <= 8'h04;
            notch_data[24 +: 8] <= 8'h04;
        end                  
    end
        
    assign notch_pending_o = (state == NOTCH0_PENDING ||
                              state == NOTCH1_PENDING ||
                              state == NOTCH_UPDATE_PENDING);

    assign notch_complete_o = (state == NOTCH_UPDATE_ACK);
    assign notch_dat_o = notch_data;
    assign notch_time_o = notch_cur_time;
endmodule

`timescale 1ns / 1ps
`include "interfaces.vh"
// This is literally called v1 bc it's a total placeholder right now
module turf_header_generator_v1(
        input memclk,
        input memresetn,
        // trigger to generate the headers.
        // because we're fake we're going to just generate them
        // programmatically with no fifo
        input event_i,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_thdr_ , 64 ),
        output m_thdr_tlast
    );
    
    parameter NBEATS = 16;
    // we use clog2(NBEATS) because we need to count from 0 to NBEATS-1
    // and to express x (= NBEATS -1 ) we use $clog2(x+1) so
    // yeah, nbeats
    localparam BC_WIDTH = $clog2(NBEATS);
    reg [BC_WIDTH-1:0] beat_counter = {BC_WIDTH{1'b0}};
    reg first_beat = 0;
    reg last_beat = 0;
    reg valid = 0;

    always @(posedge memclk) begin
        if (!memresetn) beat_counter <= {BC_WIDTH{1'b0}};
        else if (m_thdr_tvalid && m_thdr_tready) begin
            if (m_thdr_tlast) beat_counter <= {BC_WIDTH{1'b0}};
            else beat_counter <= beat_counter + 1;
        end

        if (!memresetn) first_beat <= 0;
        else begin
            if (m_thdr_tvalid && m_thdr_tready) first_beat <= 0;
            else if (event_i && !valid) first_beat <= 1;
        end

        if (!memresetn) last_beat <= 0;
        else begin
            if (m_thdr_tvalid && m_thdr_tready) begin
                if (beat_counter == NBEATS-2) last_beat <= 1;
                else last_beat <= 0;
            end
        end
        
        if (!memresetn) valid <= 0;
        else begin
            if (event_i) valid <= 1;
            else if (m_thdr_tvalid && m_thdr_tready && m_thdr_tlast) valid <= 0;
        end
    end

    assign m_thdr_tvalid = valid;
    assign m_thdr_tlast = last_beat;
    // lolstupidity
    assign m_thdr_tdata[31:0] =  (first_beat) ? 32'h4530007C : 32'h00000000;
    assign m_thdr_tdata[63:32] = (last_beat) ? 32'h00000081 : 32'h00000000;
endmodule

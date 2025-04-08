`timescale 1ns / 1ps
`include "interfaces.vh"
// headers come in way earlier than everything else so we don't need
// to buffer much. We DO need to buffer the actual trigger data
// but that'll come later.
module hdr_accumulator(
        // aclk-land
        input aclk,
        input aresetn,
        // if set, fake the stream from the specified 
        // TURFIO. this is so much harder than it needs to be
        // lives in ACLK land
        input [3:0] tio_mask_i,
        // turf header input, this needs more buffering
        // god I hope we have enough
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_thdr_ , 64 ),        
        input s_thdr_tlast,
        // these end up being 128 bytes total, we put them
        // at 0x80-0xFF.        
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr0_ , 64 ),
        input s_hdr0_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr1_ , 64 ),
        input s_hdr1_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr2_ , 64 ),
        input s_hdr2_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr3_ , 64 ),
        input s_hdr3_tlast,
        // ADD OTHER CRAP LATER
        input memclk,
        input memresetn
    );
    
    // each of the TURFIOs needs to go in a FIFO.
    // we also need to have a fake stream generator, which
    // just generates 4 beats high whenever a TURF header
    // beat is seen.
    generate
        genvar i;
        for (i=0;i<4;i=i+1) begin : TL
            reg masked_turfio_valid = 0;
            reg [1:0] masked_turfio_counter = {2{1'b0}};
            always @(posedge aclk) begin 

            end
        end
    endgenerate
    
        
endmodule

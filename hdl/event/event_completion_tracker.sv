`timescale 1ns / 1ps
// The completion tracker works in aclk land:
// it watches for tlasts from unmasked TURFIOs
// and when that matches the expected, it flags
// that the event has been received to the
// buffer track. It also throws an error if
// a SECOND tlast is received from any of the
// ones that have already received a tlast before
// all the completions come in, because there is
// no way that can be possible.
module event_completion_tracker #(parameter ACLKTYPE = "NONE")(
        input aclk,
        input aresetn,
        input enable_i,
        input turf_complete_i,
        input [3:0] s_axis_tlast,
        input [3:0] s_axis_tvalid,
        input [3:0] s_axis_tready,
        input [3:0] tio_mask_i,
        
        output complete_o,
        output [3:0] err_o
    );

    (* CUSTOM_CC_DST = ACLKTYPE, ASYNC_REG = "TRUE" *)
    reg [2:0] enable_rereg = {3{1'b0}};    

    // we only use the TURF if zero turfios are enabled.
    
    reg [3:0] complete_seen = 4'h0;
    reg [3:0] active_turfio = 4'h0;
    reg       any_turfio = 0;
        
    reg complete = 0;
    
    wire [3:0] err_in;
    // giant bitwise op
    assign err_in = (complete_seen & s_axis_tlast & s_axis_tvalid & s_axis_tready & active_turfio);
    wire err_any = |err_in;
    
    // the way the error works is that it only stores the first error,
    // and what it stores is the INVERSE of complete_seen anded with active_turfio
    // Because the assumption is that those TURFIOs DID NOT send the data they were
    // supposed to.
    //
    // So e.g. if active_turfio = 0111 and complete seen is 0001 and another
    // completes through 0, we get 1110 & 0111 = 0110.
    reg err_has_been_seen = 0;
    (* CUSTOM_CC_SRC = ACLKTYPE *)
    reg [3:0] err = 4'h0;
        
    integer i;
    always @(posedge aclk) begin
        // we don't need to condition this anymore
        active_turfio <= ~tio_mask_i;
        any_turfio <= tio_mask_i != 4'hF;
        enable_rereg <= { enable_rereg[1:0], enable_i };
        
        complete <= enable_rereg[2] && (any_turfio ? active_turfio == complete_seen : turf_complete_i);
    
        if (!aresetn) err_has_been_seen <= 0;
        else if (err_any) err_has_been_seen <= 1;
        
        if (!aresetn) err <= 4'h0;
        else if (err_any && !err_has_been_seen) begin
            err <= ~complete_seen & active_turfio;
        end
        
        for (i=0;i<4;i=i+1) begin
            if (!aresetn) complete_seen[i] <= 1'b0;
            else begin
                if (s_axis_tlast[i] && s_axis_tready[i] && s_axis_tvalid[i] && active_turfio[i])
                    complete_seen[i] <= 1;
                else if (complete)
                    complete_seen[i] <= 0;
            end
        end        
    end
    
    assign complete_o = complete;
    assign err_o = err;
endmodule

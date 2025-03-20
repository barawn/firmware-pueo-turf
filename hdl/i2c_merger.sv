`timescale 1ns / 1ps
// fans out an i2c master to two busses, no clock stretching
// note that this will look a little weird on the unused bus,
// but it doesn't matter. Still legal I2C transactions.
module i2c_merger(
        // clock is just for debugging
        input clk,

        input scl_in,
        output sda_in_o,
        input sda_in_t,
        
        output scl0_out,
        inout sda0_out,
        
        output scl1_out,
        inout sda1_out
    );
    
    parameter DEBUG = "FALSE";
    
    wire enable_A;
    wire enable_B;    
    
    generate
        if (DEBUG == "TRUE") begin : DBG
            i2c_merge_vio u_vio(.clk(clk),
                                 .probe_in0( { scl1_out, scl0_out, scl_in } ),
                                 .probe_in1( { sda1_out, sda0_out, sda_in_o } ),
                                 .probe_out0(enable_A),
                                 .probe_out1(enable_B));
            i2c_merge_ila u_ila(.clk(clk),
                                .probe0(scl_in),
                                .probe1(sda_in_t),                        
                                .probe2(sda_in_o));                                         
        end else begin
            assign enable_A = 1'b1;
            assign enable_B = 1'b1;
        end
    endgenerate
    
    assign scl0_out = scl_in || !enable_A;
    assign scl1_out = scl_in || !enable_B;
    
    assign sda0_out = (!sda_in_t && enable_A) ? 1'b0 : 1'bZ;
    assign sda1_out = (!sda_in_t && enable_B) ? 1'b0 : 1'bZ;

    // if these are true, the source is driving low
    wire sda0_is_driven = (!sda0_out && enable_A);
    wire sda1_is_driven = (!sda1_out && enable_B);
    wire sdain_is_driven = !sda_in_t;

    // combine the drives            
    assign sda_in_o = (sda0_is_driven || sda1_is_driven || sdain_is_driven) ? 1'b0 : 1'b1;
    
endmodule

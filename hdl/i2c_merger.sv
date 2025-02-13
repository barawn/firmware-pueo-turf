`timescale 1ns / 1ps
// fans out an i2c master to two busses, no clock stretching
// note that this will look a little weird on the unused bus,
// but it doesn't matter. Still legal I2C transactions.
module i2c_merger(
        input scl_in,
        output sda_in_o,
        input sda_in_t,
        
        output scl0_out,
        inout sda0_out,
        
        output scl1_out,
        inout sda1_out
    );
    
    assign scl0_out = scl_in;
    assign scl1_out = scl_in;
    
    assign sda0_out = (sda_in_t) ? 1'bZ : 1'b0;
    assign sda1_out = (sda_in_t) ? 1'bZ : 1'b0;
    
    // the merged SDA is 0 if either !sda_in_t or !sda0_out or !sda1_out
    assign sda_in_o = !sda_in_t || !sda0_out || !sda1_out;
    
endmodule

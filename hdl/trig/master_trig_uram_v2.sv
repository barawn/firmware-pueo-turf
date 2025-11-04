`timescale 1ns / 1ps
// This is the URAM only portion of the master trigger process.
// Because it can't be cascaded at all, it can be separated off to its own module.
//
// v2 allows fully using all 8 bits of the metadata by partnering the parity
// bits with the write enable. The master trigger process needs to change for this,
// obviously - we now need to apply the masking at the L2 input (readout).
module master_trig_uram_v2(
        input clk_i,
        // b side inputs. We only need we_i now.
        input wr_en_i,
        input [11:0] waddr_i,
        input [63:0] metadata_i,
        input [7:0] we_i,
        // a side inputs/outputs
        input [11:0] raddr_i,
        input rd_en_i,
        input rd_phase_i,
        output [63:0] metadata_o,
        output [7:0] trigger_o        
    );

    // in v2, we need to use parity interleaved mode, so set ALL the top bits.
    // They only get written when the byte-write is set.    
    wire [71:0] din_a = { 8'hFF, metadata_i };
    // Since we are in PARITY_INTERLEAVED mode now bit 8 is unused
    wire [8:0]  bwe_a = { 1'b0, we_i };
    wire [22:0] addr_a = { {11{1'b0}}, waddr_i };
    wire        en_a = wr_en_i;
    // a-side always writes
    wire        wr_a = 1'b1;
    
    // b-side flips between reading and then clearing.
    wire [71:0] din_b = {72{1'b0}};
    wire [8:0]  bwe_b = {9{1'b1}};
    wire        en_b  = rd_en_i;
    wire        wr_b = rd_phase_i;
    wire [22:0] addr_b = raddr_i;
    wire [71:0] dout_b;
    assign metadata_o = dout_b[0 +: 64];
    assign trigger_o = dout_b[64 +: 8];
    
    URAM288_BASE #(.BWE_MODE_A("PARITY_INTERLEAVED"),
                   .BWE_MODE_B("PARITY_INTERLEAVED"))
        u_uram( .DIN_A( din_a ),
                .BWE_A( bwe_a ),
                .ADDR_A( addr_a ),
                .EN_A( en_a ),
                .RDB_WR_A( wr_a ),
                
                .DIN_B( din_b ),
                .BWE_B( bwe_b ),
                .EN_B( rd_en_i ),
                .RDB_WR_B( wr_b ),
                .ADDR_B( addr_b ),
                .DOUT_B( dout_b ),
                
                .CLK(clk_i),
                .SLEEP(1'b0),
                .RST_A(1'b0),
                .RST_B(1'b0));                                      
endmodule

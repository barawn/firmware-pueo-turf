`timescale 1ns / 1ps
// This is the URAM only portion of the master trigger process.
// Because it can't be cascaded at all, it can be separated off to its own module.
module master_trig_uram(
        input clk_i,
        // b side inputs
        input wr_en_i,
        input [11:0] waddr_i,
        input [63:0] metadata_i,
        input [7:0] we_i,
        input trigger_i,
        // a side inputs/outputs
        input [11:0] raddr_i,
        input rd_en_i,
        input rd_phase_i,
        output [63:0] metadata_o,
        output trigger_o        
    );
    
    wire [71:0] din_a = { 8'h01, metadata_i };
    wire [8:0]  bwe_a = { trigger_i, we_i };
    wire [22:0] addr_a = { {11{1'b0}}, waddr_i };
    wire        en_a = wr_en_i;
    wire        wr_a = trigger_i;
    
    wire [71:0] din_b = {72{1'b0}};
    wire [8:0]  bwe_b = {9{1'b1}};
    wire        en_b  = rd_en_i;
    wire        wr_b = rd_phase_i;
    wire [22:0] addr_b = raddr_i;
    wire [71:0] dout_b;
    assign metadata_o = dout_b[0 +: 64];
    assign trigger_o = dout_b[64];
    
    URAM288_BASE #(.BWE_MODE_A("PARITY_INDEPENDENT"),
                   .BWE_MODE_B("PARITY_INDEPENDENT"))
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

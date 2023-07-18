`timescale 1ns / 1ps
// dear god can we please get this shit working
module turfio_testing(
        input RXCLK_P,
        input RXCLK_N,
        output TXCLK_P,
        output TXCLK_N,
        input CINTIO_P,
        input CINTIO_N,
        output COUT_P,
        output COUT_N,
        
        input init_clk,
        input sys_clk
    );
    
    // There are so so so many extra signals that are just NOWHERE defined
    // WTF you're supposed to do with them
    
    // RIU clk
    wire [2:0] dly_rdy;
    // RIU clk
    wire [2:0] vtc_rdy;
    // RIU clk
    reg [2:0] en_vtc = {3{1'b0}};
    // See fig 4-2: after RST, assert START_BITSLIP, then when RX_BITSLIP_SYNC_DONE
    // deassert.
    reg start_bitslip = 0;
    // Sync to fifo_rd_clk (phy_clk?)
    wire bitslip_done;
    // data valid from FIFO
    wire fifo_data_valid;
    
    wire rst_seq_done;
    // RIU clock
    reg rst = 0;        
    
    // PLL output clk (shifted version of sysclk)
    wire phy_clk;
    wire [7:0] data_to_fabric;
    wire [7:0] data_from_fabric;
    
    
    native_rxtx u_phy();
    
endmodule

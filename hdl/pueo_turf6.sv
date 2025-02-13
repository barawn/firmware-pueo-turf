`timescale 1ns / 1ps
/////////////////////////////////////////////
// NEW TURF FIRMWARE: Now using PetaLinux  //
// and a bunch of stock cores for serial   //
// crap.                                   //
/////////////////////////////////////////////
module pueo_turf6(
        output TTXA,
        input TRXA,
        
        output TTXB,
        input TRXB,
        
        output TTXC,
        input TRXC,
        
        output TTXD,
        input TRXD,
        
        output GPS_TX,
        input GPS_RX,
        
        output CLK_SCL,
        inout CLK_SDA,
        
        output CAL_SCL,
        inout CAL_SDA        
    );
    
    wire ps_clk;
    
    wire emio_scl;
    wire emio_sda_i;
    wire emio_sda_t;
    
    wire spi0_sclk;
    wire spi0_mosi;
    wire spi0_miso = 1'b0;
    wire spi0_cs_b;
    
    // NOTE: we might add in the optional TURFIO I2C controls
    // at some point. If we do that, we need to disconnect the
    // UART. We can only do one of those at a time because their
    // addresses will clash.
    // Our local addresses are only 0x62/0x6A and whatever's
    // on the cal board (will need to check that to not clash!!)
    // on the turfio we pick up 48/10/40/44/11/41/45/46 and 70.
    // that's a busy I2C bus!
    i2c_merger u_i2c_merger(.scl_in(emio_scl),
                            .sda_in_o(emio_sda_i),
                            .sda_in_t(emio_sda_t),
                            .scl0_out(CLK_SCL),
                            .sda0_out(CLK_SDA),
                            .scl1_out(CAL_SCL),
                            .sda1_out(CAL_SDA));
    
    zynq_bd_wrapper u_zynq( .IIC_scl_o(emio_scl),
                            .IIC_sda_i(emio_sda_i),
                            .IIC_sda_t(emio_sda_t),
                            
                            .spi0_sclk(spi0_sclk),
                            .spi0_mosi(spi0_mosi),
                            .spi0_miso(spi0_miso),
                            .spi0_cs_b(spi0_cs_b),
    
                            .GPS_rxd(GPS_RX),
                            .GPS_txd(GPS_TX),
                            
                            .TFIO_A_rxd(TRXA),
                            .TFIO_A_txd(TTXA),
                            
                            .TFIO_B_rxd(TRXB),
                            .TFIO_B_txd(TTXB),
                            
                            .TFIO_C_rxd(TRXC),
                            .TFIO_C_txd(TTXC),
                            
                            .TFIO_D_rxd(TRXD),
                            .TFIO_D_txd(TTXD),
                            
                            .pl_clk0(ps_clk));
    
endmodule

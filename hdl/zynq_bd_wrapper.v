//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
//Date        : Wed Feb 12 15:54:36 2025
//Host        : ASCPHY-NC196428 running 64-bit major release  (build 9200)
//Command     : generate_target zynq_bd_wrapper.bd
//Design      : zynq_bd_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

`include "interfaces.vh"

// modified b/c wtf are you pushing I/Os through
// the AXI4L interface pulls through
// araddr/arready/arvalid
// awaddr/awready/awvalid
//  bresp/bready/bvalid
//  rdata/rready/rvalid/rresp
//  wdata/wready/wvalid/wstrb
// - in other words, our bog standard AXI4L interfaces
//   m_axi_ps_ interface
//
// this means we also alter the idiot split-declaration style too
module zynq_bd_wrapper
   (input [15:0] EMIO_tri_i,
    output [15:0] EMIO_tri_o,
    output [15:0] EMIO_tri_t,
    
    input GPS_rxd,
    output GPS_txd,
    
    // AXI4L interface
    `HOST_NAMED_PORTS_AXI4L_IF( m_axi_ps_ , 28, 32 ),
    
    // we force I2C
    output IIC_scl_o,
    input IIC_sda_i,
    output IIC_sda_t,

    // we force SPI directionality
    output spi0_sclk,
    output spi0_mosi,
    input spi0_miso,
    output spi0_cs_b,
    
    // housekeeping SPI
    output spi1_sclk,
    output spi1_mosi,
    input spi1_miso,
    output [1:0] spi1_cs_b,
        
    input TFIO_A_rxd,
    output TFIO_A_txd,

    input TFIO_B_rxd,
    output TFIO_B_txd,
    
    input TFIO_C_rxd,
    output TFIO_C_txd,
    
    input TFIO_D_rxd,
    output TFIO_D_txd,
    
    output pl_clk0);
  
  wire IIC_scl_t;
  wire IIC_scl;
  wire IIC_scl_i = (IIC_scl_t) ? 1'b1 : IIC_scl;
  assign IIC_scl_o = IIC_scl_i;
  
    // IO0 => MOSI
    // IO1 => MISO
  wire SPI0_io0_i;
  wire SPI0_io0_o;
  wire SPI0_io0_t;
  wire SPI0_io1_i;
  wire SPI0_io1_o;
  wire SPI0_io1_t;
  wire SPI0_sck_i;
  wire SPI0_sck_o;
  wire SPI0_sck_t;
  wire SPI0_ss1_o;
  wire SPI0_ss_i;
  wire SPI0_ss_o;
  wire SPI0_ss_t;
  
  assign spi0_sclk = (SPI0_sck_t) ? 1'b0 : SPI0_sck_o;
  assign spi0_cs_b = (SPI0_ss_t) ? 1'b1 : SPI0_ss_o;
  assign spi0_mosi = (SPI0_io0_t) ? 1'b0 : SPI0_io0_o;
  assign SPI0_io1_i = spi0_miso;

  wire SPI1_io0_i;
  wire SPI1_io0_o;
  wire SPI1_io0_t;
  wire SPI1_io1_i;
  wire SPI1_io1_o;
  wire SPI1_io1_t;
  wire SPI1_sck_i;
  wire SPI1_sck_o;
  wire SPI1_sck_t;
  wire SPI1_ss1_o;
  wire SPI1_ss_i;
  wire SPI1_ss_o;
  wire SPI1_ss_t;
  assign spi1_sclk = (SPI1_sck_t) ? 1'b0 : SPI1_sck_o;
  assign spi1_cs_b[0] = (SPI1_ss_t) ? 1'b1 : SPI1_ss_o;
  assign spi1_cs_b[1] = (SPI1_ss1_o);
  assign spi1_mosi = (SPI1_io0_t) ? 1'b0 : SPI1_io0_o;
  assign SPI1_io1_i = spi1_miso;
    
  zynq_bd zynq_bd_i
       (.EMIO_tri_i(EMIO_tri_i),
        .EMIO_tri_o(EMIO_tri_o),
        .EMIO_tri_t(EMIO_tri_t),
        .GPS_rxd(GPS_rxd),
        .GPS_txd(GPS_txd),
        
        .IIC_scl_i(IIC_scl_i),
        .IIC_scl_o(IIC_scl),
        .IIC_scl_t(IIC_scl_t),
        
        .IIC_sda_i(IIC_sda_i),
        .IIC_sda_o(IIC_sda_o),
        .IIC_sda_t(IIC_sda_t),

        // IO0 => out, IO1 => in,        
        .SPI0_io0_i(SPI0_io0_i),
        .SPI0_io0_o(SPI0_io0_o),
        .SPI0_io0_t(SPI0_io0_t),
        .SPI0_io1_i(SPI0_io1_i),
        .SPI0_io1_o(SPI0_io1_o),
        .SPI0_io1_t(SPI0_io1_t),
        .SPI0_sck_i(SPI0_sck_i),
        .SPI0_sck_o(SPI0_sck_o),
        .SPI0_sck_t(SPI0_sck_t),
        .SPI0_ss_i(SPI0_ss_i),
        .SPI0_ss_o(SPI0_ss_o),
        .SPI0_ss_t(SPI0_ss_t),

        .SPI1_io0_i(SPI1_io0_i),
        .SPI1_io0_o(SPI1_io0_o),
        .SPI1_io0_t(SPI1_io0_t),
        .SPI1_io1_i(SPI1_io1_i),
        .SPI1_io1_o(SPI1_io1_o),
        .SPI1_io1_t(SPI1_io1_t),
        .SPI1_sck_i(SPI1_sck_i),
        .SPI1_sck_o(SPI1_sck_o),
        .SPI1_sck_t(SPI1_sck_t),
        .SPI1_ss1_o(SPI1_ss1_o),        
        .SPI1_ss_i(SPI1_ss_i),
        .SPI1_ss_o(SPI1_ss_o),
        .SPI1_ss_t(SPI1_ss_t),


        .TFIO_A_rxd(TFIO_A_rxd),
        .TFIO_A_txd(TFIO_A_txd),
        .TFIO_B_rxd(TFIO_B_rxd),
        .TFIO_B_txd(TFIO_B_txd),
        .TFIO_C_rxd(TFIO_C_rxd),
        .TFIO_C_txd(TFIO_C_txd),
        .TFIO_D_rxd(TFIO_D_rxd),
        .TFIO_D_txd(TFIO_D_txd),
        
        `CONNECT_AXI4L_IF( M_AXI_ , m_axi_ps_ ),
        
        .pl_clk0(pl_clk0));
endmodule

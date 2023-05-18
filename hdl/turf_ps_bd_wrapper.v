//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
//Date        : Sun Apr 30 17:14:36 2023
//Host        : ASCPHY-NC196428 running 64-bit major release  (build 9200)
//Command     : generate_target turf_ps_bd_wrapper.bd
//Design      : turf_ps_bd_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module turf_ps_bd_wrapper
   (ACLK,
    CLK_IIC_scl_io,
    CLK_IIC_sda_io,
    HSK_UART_rxd,
    HSK_UART_txd,
    HSK2_UART_rxd,
    HSK2_UART_txd,
    PL_CLK,
    PS_ARESET,
    PS_RESET_N);
  input ACLK;
  inout CLK_IIC_scl_io;
  inout CLK_IIC_sda_io;
  input HSK_UART_rxd;
  output HSK_UART_txd;
  input HSK2_UART_rxd;
  output HSK2_UART_txd;

  input  PS_ARESET;
  output PL_CLK;
  output PS_RESET_N;

  wire ACLK;
  wire CLK_IIC_scl_i;
  wire CLK_IIC_scl_io;
  wire CLK_IIC_scl_o;
  wire CLK_IIC_scl_t;
  wire CLK_IIC_sda_i;
  wire CLK_IIC_sda_io;
  wire CLK_IIC_sda_o;
  wire CLK_IIC_sda_t;
  wire HSK_UART_rxd;
  wire HSK_UART_txd;
  wire PL_CLK;
  wire PS_RESET_N;

  IOBUF CLK_IIC_scl_iobuf
       (.I(CLK_IIC_scl_o),
        .IO(CLK_IIC_scl_io),
        .O(CLK_IIC_scl_i),
        .T(CLK_IIC_scl_t));
  IOBUF CLK_IIC_sda_iobuf
       (.I(CLK_IIC_sda_o),
        .IO(CLK_IIC_sda_io),
        .O(CLK_IIC_sda_i),
        .T(CLK_IIC_sda_t));
  turf_ps_bd turf_ps_bd_i
       (.ACLK(ACLK),
        .CLK_IIC_scl_i(CLK_IIC_scl_i),
        .CLK_IIC_scl_o(CLK_IIC_scl_o),
        .CLK_IIC_scl_t(CLK_IIC_scl_t),
        .CLK_IIC_sda_i(CLK_IIC_sda_i),
        .CLK_IIC_sda_o(CLK_IIC_sda_o),
        .CLK_IIC_sda_t(CLK_IIC_sda_t),
        .HSK_UART_rxd(HSK_UART_rxd),
        .HSK_UART_txd(HSK_UART_txd),
        .PL_CLK(PL_CLK),
        .PS_RESET_N(PS_RESET_N));
endmodule

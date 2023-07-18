//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
//Date        : Thu Jun 29 11:43:14 2023
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
    HSK2_UART_rxd,
    HSK2_UART_txd,
    HSK_UART_rxd,
    HSK_UART_txd,
    PL_CLK,
    PS_ARESET,
    PS_RESET_N,
    m_axi_ps_araddr,
    m_axi_ps_arready,
    m_axi_ps_arvalid,
    m_axi_ps_awaddr,
    m_axi_ps_awready,
    m_axi_ps_awvalid,
    m_axi_ps_bready,
    m_axi_ps_bresp,
    m_axi_ps_bvalid,
    m_axi_ps_rdata,
    m_axi_ps_rready,
    m_axi_ps_rresp,
    m_axi_ps_rvalid,
    m_axi_ps_wdata,
    m_axi_ps_wready,
    m_axi_ps_wvalid,
    m_axi_ps_wstrb);
  input ACLK;
  inout CLK_IIC_scl_io;
  inout CLK_IIC_sda_io;
  input HSK2_UART_rxd;
  output HSK2_UART_txd;
  input HSK_UART_rxd;
  output HSK_UART_txd;
  output PL_CLK;
  input PS_ARESET;
  output PS_RESET_N;
  output [27:0]m_axi_ps_araddr;
  input m_axi_ps_arready;
  output m_axi_ps_arvalid;
  output [27:0]m_axi_ps_awaddr;
  input m_axi_ps_awready;
  output m_axi_ps_awvalid;
  output m_axi_ps_bready;
  input [1:0]m_axi_ps_bresp;
  input m_axi_ps_bvalid;
  input [31:0]m_axi_ps_rdata;
  output m_axi_ps_rready;
  input [1:0]m_axi_ps_rresp;
  input m_axi_ps_rvalid;
  output [31:0]m_axi_ps_wdata;
  input m_axi_ps_wready;
  output m_axi_ps_wvalid;
  output [3:0] m_axi_ps_wstrb;
  
  wire ACLK;
  wire CLK_IIC_scl_i;
  wire CLK_IIC_scl_io;
  wire CLK_IIC_scl_o;
  wire CLK_IIC_scl_t;
  wire CLK_IIC_sda_i;
  wire CLK_IIC_sda_io;
  wire CLK_IIC_sda_o;
  wire CLK_IIC_sda_t;
  wire HSK2_UART_rxd;
  wire HSK2_UART_txd;
  wire HSK_UART_rxd;
  wire HSK_UART_txd;
  wire PL_CLK;
  wire PS_ARESET;
  wire PS_RESET_N;
  wire [27:0]m_axi_ps_araddr;
  wire m_axi_ps_arready;
  wire m_axi_ps_arvalid;
  wire [27:0]m_axi_ps_awaddr;
  wire m_axi_ps_awready;
  wire m_axi_ps_awvalid;
  wire m_axi_ps_bready;
  wire [1:0]m_axi_ps_bresp;
  wire m_axi_ps_bvalid;
  wire [31:0]m_axi_ps_rdata;
  wire m_axi_ps_rready;
  wire [1:0]m_axi_ps_rresp;
  wire m_axi_ps_rvalid;
  wire [31:0]m_axi_ps_wdata;
  wire m_axi_ps_wready;
  wire m_axi_ps_wvalid;
  wire [3:0] m_axi_ps_wstrb;
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
        .HSK2_UART_rxd(HSK2_UART_rxd),
        .HSK2_UART_txd(HSK2_UART_txd),
        .HSK_UART_rxd(HSK_UART_rxd),
        .HSK_UART_txd(HSK_UART_txd),
        .PL_CLK(PL_CLK),
        .PS_ARESET(PS_ARESET),
        .PS_RESET_N(PS_RESET_N),
        .m_axi_ps_araddr(m_axi_ps_araddr),
        .m_axi_ps_arready(m_axi_ps_arready),
        .m_axi_ps_arvalid(m_axi_ps_arvalid),
        .m_axi_ps_awaddr(m_axi_ps_awaddr),
        .m_axi_ps_awready(m_axi_ps_awready),
        .m_axi_ps_awvalid(m_axi_ps_awvalid),
        .m_axi_ps_bready(m_axi_ps_bready),
        .m_axi_ps_bresp(m_axi_ps_bresp),
        .m_axi_ps_bvalid(m_axi_ps_bvalid),
        .m_axi_ps_rdata(m_axi_ps_rdata),
        .m_axi_ps_rready(m_axi_ps_rready),
        .m_axi_ps_rresp(m_axi_ps_rresp),
        .m_axi_ps_rvalid(m_axi_ps_rvalid),
        .m_axi_ps_wdata(m_axi_ps_wdata),
        .m_axi_ps_wready(m_axi_ps_wready),
        .m_axi_ps_wvalid(m_axi_ps_wvalid),
        .m_axi_ps_wstrb(m_axi_ps_wstrb));
endmodule

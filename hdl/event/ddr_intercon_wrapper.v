`timescale 1 ps / 1 ps
`include "mem_axi.vh"

module ddr_intercon_wrapper(
    input aclk,
    input aresetn,
    `S_AXIM_PORT( s_axi_in_ , 5 ),
    `S_AXIM_PORT( s_axi_out_ , 1 ),
    `M_AXIM_PORT( m_axi_ , 1 ),
    wire [2:0] m_axi_arid,
    wire [2:0] m_axi_awid,
    wire [2:0] m_axi_bid,
    wire [2:0] m_axi_rid
    );

  parameter DEBUG = "TRUE";

  // we need to expand out the port vector
  `AXIM_DECLARE( hdr_ , 1 );
  `AXIM_DECLARE( t0_ , 1 );
  `AXIM_DECLARE( t1_ , 1 );
  `AXIM_DECLARE( t2_ , 1 );
  `AXIM_DECLARE( t3_ , 1 );
  // we do that by replacing the build macros:
  // this turns something like assign `AXIM_BUILD_FROM(from, arready) = `AXIM_BUILD_TO( to, arready)
  // into assign s_axi_in_arready = { t3_arready, t2_arready, t1_arread, t0_arready, hdr_arready };
  // and assign `AXIM_BUILD_TO( to, araddr ) = `AXIM_BUILD_FROM(from, araddr)
  // into assign { t3_araddr, t2_araddr, t1_araddr, t0_araddr, hdr_araddr } = s_axi_in_araddr;
  //
  // The axim ports DO NOT USE qos/lock/region! disable them in the block diagram!
  `undef AXIM_BUILD_FROM
  `undef AXIM_BUILD_TO
  `define AXIM_BUILD_TO( x, y ) { t3_``y , t2_``y , t1_``y , t0_``y , hdr_``y }
  `define AXIM_BUILD_FROM( x, y ) s_axi_in_``y 

  // n.b. the arguments here don't actually do anything, all the magic is above
  // in the redeclaration of build to/build from. Just for readability.
  `ASSIGN_AXIM( { t3_ , t2_ , t1_ , t0_ , hdr_ } , s_axi_in );

  generate
    if (DEBUG == "TRUE") begin : DBG
          ddr_intercon ddr_intercon_i
               (.ACLK_0(aclk),
                .ARESETN_0(aresetn),
                `CONNECT_AXIM( M00_AXI_0_ , m_axi_ ),
                .M00_AXI_0_awid( m_axi_awid ),
                .M00_AXI_0_arid( m_axi_arid ),
                .M00_AXI_0_bid( m_axi_bid ),
                .M00_AXI_0_rid( m_axi_rid ),                
                `CONNECT_AXIM( S00_AXI_0_ , hdr_ ),
                `CONNECT_AXIM( S01_AXI_0_ , t0_ ),
                `CONNECT_AXIM( S02_AXI_0_ , t1_ ),
                `CONNECT_AXIM( S03_AXI_0_ , t2_ ),
                `CONNECT_AXIM( S04_AXI_0_ , t3_ ),
                `CONNECT_AXIM( S05_AXI_0_ , s_axi_out_ ));
    end else begin : NODBG
          ddr_intercon_nodebug ddr_intercon_i
               (.ACLK_0(aclk),
                .ARESETN_0(aresetn),
                `CONNECT_AXIM( M00_AXI_0_ , m_axi_ ),
                .M00_AXI_0_awid( m_axi_awid ),
                .M00_AXI_0_arid( m_axi_arid ),
                .M00_AXI_0_bid( m_axi_bid ),
                .M00_AXI_0_rid( m_axi_rid ),
                `CONNECT_AXIM( S00_AXI_0_ , hdr_ ),
                `CONNECT_AXIM( S01_AXI_0_ , t0_ ),
                `CONNECT_AXIM( S02_AXI_0_ , t1_ ),
                `CONNECT_AXIM( S03_AXI_0_ , t2_ ),
                `CONNECT_AXIM( S04_AXI_0_ , t3_ ),
                `CONNECT_AXIM( S05_AXI_0_ , s_axi_out_ ));    
    end
  endgenerate            
endmodule

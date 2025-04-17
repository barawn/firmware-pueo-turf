`timescale 1ns / 1ps
`include "interfaces.vh"
`include "mem_axi.vh"

//`define PHY_IF_NAMED_PORTS( pfx , dq, dqs, dm, adr, ba, bg, cs, ck, cke, odt ) \
//define PHY_IF_NAMED_PORTS( pfx , ndq, ndqs, ndm, nadr, nba, nbg, ncs, nck, ncke, nodt ) \
// `PHY_IF_NAMED_PORTS (c0_ddr4_ ,  64,    8,   8,   17,   2,   1,   1,   1,    1,    1 )
module event_pueo_wrap(
        input DDR_CLK_P,
        input DDR_CLK_N,
        
        output ddr4_clk_o,
        
        `PHY_IF_NAMED_PORTS( c0_ddr4_ , 64, 8, 8, 17, 2, 1, 1, 1, 1, 1 ),
        
        input wb_clk_i,        
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 15, 32 ),
        
        input aclk,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_aurora0_ , 32 ),
        input s_aurora0_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_aurora1_ , 32 ),
        input s_aurora1_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_aurora2_ , 32 ),
        input s_aurora2_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_aurora3_ , 32 ),
        input s_aurora3_tlast,
        
        input ethclk,
        // acking path
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_ack_ , 48),
        // nacking path
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_nack_ , 48),
        // event open interface
        // uuuhhhh what to do here
        input event_open_o,        
        // event control input
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_ev_ctrl_ , 32),
        // event data input
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_ev_data_ , 64),            
        output [7:0] m_ev_data_tkeep,
        output m_ev_data_tlast
        
    );
    
    parameter WBCLKTYPE = "NONE";
    parameter ACLKTYPE = "NONE";
    parameter MEMCLKTYPE = "NONE";
    parameter ETHCLKTYPE = "NONE";

    wire init_calib_complete;
    wire memclk;
    
    //////////////
    // THIS CRAP NEEDS TO MOVE TO A REGISTER CORE
    //////////////
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg event_reset = 0;
    (* ASYNC_REG = "TRUE", CUSTOM_CC_DST = ACLKTYPE *)
    reg [1:0] event_reset_aclk = {2{1'b0}};
    (* ASYNC_REG = "TRUE", CUSTOM_CC_DST = MEMCLKTYPE *)
    reg [1:0] event_reset_memclk = {2{1'b0}};
    (* ASYNC_REG = "TRUE", CUSTOM_CC_DST = ETHCLKTYPE *)
    reg [1:0] event_reset_ethclk = {2{1'b0}};    

    wire aresetn = !event_reset_aclk[1];
    wire memresetn = !event_reset_memclk[1];
    wire ethresetn = !event_reset_ethclk[1];

    // AAUUUGH
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [3:0] tio_mask = {4{1'b0}};
    (* CUSTOM_CC_DST = ACLKTYPE *)
    reg [3:0] tio_mask_aclk = {4{1'b0}};
    reg update_tio_mask = 0;
    wire update_tio_mask_aclk;
    reg ack = 0;
    assign wb_ack_o = ack && !wb_cyc_i;
    assign wb_dat_o = { {31{1'b0}}, event_reset };
    always @(posedge wb_clk_i) begin
        ack <= wb_cyc_i && wb_stb_i;
        if (wb_cyc_i && wb_stb_i && wb_ack_o && wb_we_i) begin
            // just grab all the addresses
            if (wb_sel_i[0]) event_reset <= wb_dat_i[0];
            if (wb_sel_i[1]) tio_mask <= wb_dat_i[8 +: 4];
        end
        update_tio_mask <= (wb_cyc_i && wb_stb_i && wb_ack_o && wb_we_i && wb_sel_i[1]);
    end
    flag_sync u_update_mask(.in_clkA(update_tio_mask),.out_clkB(update_tio_mask_aclk),
                            .clkA(wb_clk_i),.clkB(aclk));
    always @(posedge aclk) begin
        if (update_tio_mask_aclk) tio_mask_aclk <= tio_mask;                       
    end
        
    always @(posedge aclk) event_reset_aclk <= { event_reset_aclk[0], event_reset };
    always @(posedge ddr4_clk_o) event_reset_memclk <= { event_reset_memclk[0], event_reset };
    always @(posedge ethclk) event_reset_ethclk <= { event_reset_ethclk[0], event_reset };
    
    // OK OK OK HERE WE GO
    `DEFINE_AXI4S_MIN_IF( nack_mem_ , 48 ); // nack path in memclk
    `DEFINE_AXI4S_MIN_IFV( addr_ , 12, [4:0] ); // done paths in memclk
    wire incr_allow;    // increment the allow counter
    `DEFINE_AXI4S_MIN_IFV( hdr_ , 64, [3:0] ); // header path
    wire [3:0] hdr_tlast;
    `DEFINE_AXI4S_MIN_IFV( cmpl_ , 64, [3:0] ); // completions
    `DEFINE_AXI4S_MIN_IF( hdrcmpl_ , 24 ); // header completion
    `DEFINE_AXI4S_MIN_IF( thdr_ , 64 ); // TURF headers. Dumb for now since just testing.

    // vectorize the aurora links
    `DEFINE_AXI4S_MIN_IFV( aur_ , 32, [3:0] );
    wire [3:0] aur_tlast;
    `define HOOK_AURORA( to , tosuffix, from ) \
        assign to``tdata``tosuffix = from``tdata;    \
        assign to``tvalid``tosuffix = from``tvalid;  \
        assign from``tready = to``tready``tosuffix;  \
        assign to``tlast``tosuffix = from``tlast
    
    `HOOK_AURORA( aur_ , [0] , s_aurora0_ );
    `HOOK_AURORA( aur_ , [1] , s_aurora1_ );
    `HOOK_AURORA( aur_ , [2] , s_aurora2_ );
    `HOOK_AURORA( aur_ , [3] , s_aurora3_ );

    // create the AXIM links
    `AXIM_DECLARE( tioaxi_ , 4 );
    `AXIM_DECLARE_DW( hdraxi_ , 1, 64 );
    `AXIM_DECLARE( outaxi_ , 1 );
    `AXIM_DECLARE( memaxi_ , 1 );
    // IDs for memaxi
    wire [2:0] memaxi_arid;
    wire [2:0] memaxi_awid;
    wire [2:0] memaxi_bid;
    wire [2:0] memaxi_rid;
    // qos/locks - kill them
    wire [3:0] memaxi_arqos = {4{1'b0}};
    wire [3:0] memaxi_awqos = {4{1'b0}};
    wire memaxi_arlock = 1'b0;
    wire memaxi_awlock = 1'b0;
    
    // whatever, do something eventually with these
    localparam ACLK_ERR_SIZE = 2;
    localparam MEMCLK_ERR_SIZE = 5;
    wire [4*ACLK_ERR_SIZE-1:0] tio_errdet_aclk;
    wire [4*MEMCLK_ERR_SIZE-1:0] tio_errdet_memclk;    
    wire readout_err;
    
    // first let's put the ack_done_generator.
    ack_done_generator
        u_donegen( .aclk( ethclk ),
                   .aresetn( ethresetn ),
                   `CONNECT_AXI4S_MIN_IF( s_ack_ , s_ack_ ),
                   `CONNECT_AXI4S_MIN_IF( s_nack_ , s_nack_ ),
                   .memclk(memclk),
                   .memresetn(memresetn),
                   `CONNECT_AXI4S_MIN_IF( m_nack_ , nack_mem_ ),
                   .allow_o( incr_allow ),
                   `CONNECT_AXI4S_MIN_IFV( m_t0addr_ , addr_ , [0] ),
                   `CONNECT_AXI4S_MIN_IFV( m_t1addr_ , addr_ , [1] ),
                   `CONNECT_AXI4S_MIN_IFV( m_t2addr_ , addr_ , [2] ),
                   `CONNECT_AXI4S_MIN_IFV( m_t3addr_ , addr_ , [3] ),
                   `CONNECT_AXI4S_MIN_IFV( m_hdraddr_ , addr_ , [4] ));
    // now the TURFIOs...
    generate
        genvar i;
        for (i=0;i<4;i=i+1) begin : TIO
            // we need an accumulator->reqgen path
            wire [63:0] payload;
            wire [4:0]  payload_ident;
            wire        payload_valid;
            wire        payload_last;
            wire        payload_has_space;
            // event accumulator. builds up chunks
            turfio_event_accumulator
                u_accum( .aclk( aclk ),
                         .aresetn( aresetn ),
                         `CONNECT_AXI4S_MIN_IFV( s_axis_ , aur_ , [i] ),
                         .s_axis_tlast( aur_tlast[i] ),
                         `CONNECT_AXI4S_MIN_IFV( m_hdr_ , hdr_ , [i] ),
                         .m_hdr_tlast( hdr_tlast[i] ),
                         .payload_o(payload),
                         .payload_ident_o(payload_ident),
                         .payload_valid_o(payload_valid),
                         .payload_last_o(payload_last),
                         .payload_has_space_i(payload_has_space),
                         .errdet_aclk_o( tio_errdet_aclk[ ACLK_ERR_SIZE*i +: ACLK_ERR_SIZE ] ),
                         .errdet_memclk_o(tio_errdet_memclk[ MEMCLK_ERR_SIZE*i +: 1 ] ));
            // now the req gen. transfers chunks to memory
            pueo_turfio_event_req_gen #(.BASE_ADDRESS_4KB(4 + 28*i))
                u_reqgen( .memclk(memclk),
                          .memresetn(memresetn),
                          .payload_i( payload ),
                          .payload_ident_i(payload_ident),
                          .payload_valid_i(payload_valid),
                          .payload_last_i(payload_last),
                          .payload_has_space_o(payload_has_space),
                          `CONNECT_AXIM_VEC( m_axi_ , tioaxi_ , i ),
                          `CONNECT_AXI4S_MIN_IFV( s_done_ , addr_ , [i] ),
                          `CONNECT_AXI4S_MIN_IFV( m_cmpl_ , cmpl_ , [i] ),
                          .cmd_err_o( tio_errdet_memclk[ MEMCLK_ERR_SIZE*i + 1 +: 4 ] ));
        end
    endgenerate        
    
    // now the header accumulator
    hdr_accumulator u_headers( .aclk(aclk),
                               .aresetn(aresetn),
                               .tio_mask_i(tio_mask_aclk),
                               `CONNECT_AXI4S_MIN_IFV( s_done_ , addr_ , [4] ),
                               `CONNECT_AXI4S_MIN_IF( m_cmpl_ , hdrcmpl_ ),
                               `CONNECT_AXI4S_MIN_IF( s_thdr_ , thdr_ ),
                               `CONNECT_AXI4S_MIN_IFV( s_hdr0_ , hdr_ , [ 0 ] ),
                               .s_hdr0_tlast( hdr_tlast[0] ),
                               `CONNECT_AXI4S_MIN_IFV( s_hdr1_ , hdr_ , [ 1 ] ),
                               .s_hdr1_tlast( hdr_tlast[1] ),
                               `CONNECT_AXI4S_MIN_IFV( s_hdr2_ , hdr_ , [ 2 ] ),
                               .s_hdr2_tlast( hdr_tlast[2] ),
                               `CONNECT_AXI4S_MIN_IFV( s_hdr3_ , hdr_ , [ 3 ] ),
                               .s_hdr3_tlast( hdr_tlast[3] ),
                               .memclk(memclk),
                               .memresetn(memresetn),
                               `CONNECT_AXIM_DW( m_axi_ , hdraxi_ , 64 ));
    
    // and the readout generator
    event_readout_generator #(.MEMCLKTYPE(MEMCLKTYPE),
                              .ACLKTYPE(ETHCLKTYPE))
        u_readout( .memclk(memclk),
                   .memresetn(memresetn),
                   // completions
                   `CONNECT_AXI4S_MIN_IF( s_hdr_ , hdrcmpl_ ),
                   `CONNECT_AXI4S_MIN_IFV( s_t0_ , cmpl_ , [0] ),
                   `CONNECT_AXI4S_MIN_IFV( s_t1_ , cmpl_ , [1] ),
                   `CONNECT_AXI4S_MIN_IFV( s_t2_ , cmpl_ , [2] ),
                   `CONNECT_AXI4S_MIN_IFV( s_t3_ , cmpl_ , [3] ),
                   // nack path
                   `CONNECT_AXI4S_MIN_IF( s_nack_ , nack_mem_ ),
                   // axim
                   `CONNECT_AXIM( m_axi_ , outaxi_ ),
                   .allow_i(incr_allow),
                   // ethclk
                   .aclk(ethclk),
                   .aresetn(ethresetn),
                   `CONNECT_AXI4S_MIN_IF( m_ctrl_ , m_ev_ctrl_ ),
                   `CONNECT_AXI4S_MIN_IF( m_data_ , m_ev_data_ ),
                   .any_err_o( readout_err ));
    
    // and now the interconnect
    ddr_intercon_wrapper #(.DEBUG("FALSE"))
        u_intercon( .aclk(memclk),
                    .aresetn(memresetn),
                    `CONNECT_AXIM_DW( s_axi_hdr_ , hdraxi_ , 64 ),
                    `CONNECT_AXIM( s_axi_in_ , tioaxi_ ),
                    `CONNECT_AXIM( s_axi_out_ , outaxi_ ),
                    `CONNECT_AXIM( m_axi_ , memaxi_ ),
                    .m_axi_arid( memaxi_arid ),
                    .m_axi_awid( memaxi_awid ),
                    .m_axi_bid( memaxi_bid ),
                    .m_axi_rid( memaxi_rid ) );
    
        
    // no WID, xbars don't do write reording.
    ddr4_mig u_mig( .sys_rst(!memresetn),
                    .c0_sys_clk_p(DDR_CLK_P),
                    .c0_sys_clk_n(DDR_CLK_N),
                    .c0_init_calib_complete(init_calib_complete),
                    .c0_ddr4_aresetn(memresetn),
                    .c0_ddr4_ui_clk( memclk ),
      `CONNECT_AXIM( c0_ddr4_s_axi_ ,     memaxi_       ),
                    .c0_ddr4_s_axi_awqos( memaxi_awqos  ),
                    .c0_ddr4_s_axi_arqos( memaxi_arqos  ),
                    .c0_ddr4_s_axi_awlock(memaxi_awlock ),
                    .c0_ddr4_s_axi_arlock(memaxi_arlock ),
                    .c0_ddr4_s_axi_arid ( memaxi_arid   ),
                    .c0_ddr4_s_axi_awid ( memaxi_awid   ),
                    .c0_ddr4_s_axi_rid  ( memaxi_rid    ),
                    .c0_ddr4_s_axi_bid  (  memaxi_bid   ),
    `CONNECT_PHY_IF( c0_ddr4_ ,            c0_ddr4_     ));

    assign ddr4_clk_o = memclk;
        
endmodule

`timescale 1ns / 1ps
`include "interfaces.vh"
`include "mem_axi.vh"

//`define PHY_IF_NAMED_PORTS( pfx , dq, dqs, dm, adr, ba, bg, cs, ck, cke, odt ) \
//define PHY_IF_NAMED_PORTS( pfx , ndq, ndqs, ndm, nadr, nba, nbg, ncs, nck, ncke, nodt ) \
// `PHY_IF_NAMED_PORTS (c0_ddr4_ ,  64,    8,   8,   17,   2,   1,   1,   1,    1,    1 )
module event_pueo_wrap_v2(
        input DDR_CLK_P,
        input DDR_CLK_N,
        
        output ddr4_clk_o,
        
        `PHY_IF_NAMED_PORTS( c0_ddr4_ , 64, 8, 8, 17, 2, 1, 1, 1, 1, 1 ),
        
        input wb_clk_i,        
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 13, 32 ),
        
        input aclk,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_aurora0_ , 32 ),
        input s_aurora0_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_aurora1_ , 32 ),
        input s_aurora1_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_aurora2_ , 32 ),
        input s_aurora2_tlast,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_aurora3_ , 32 ),
        input s_aurora3_tlast,

        // TURF headers. In memclk already.
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_turfhdr_ , 64 ),
        input s_turfhdr_tlast,

        // this is data that gets included in the headers,
        // which is over in the trig module.
        output [3:0] tio_mask_o,
        output [11:0] runcfg_o,
        
        // indicates we should start watching for events
        input  track_events_i,
        // flag that an event has been fully received in aclk
        output evin_complete_o,
        
        input ethclk,
        input event_open_i,
        // acking path
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_ack_ , 48),
        // nacking path
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_nack_ , 48),
        // event control input
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_ev_ctrl_ , 32),
        // event data input
        `HOST_NAMED_PORTS_AXI4S_IF( m_ev_data_ , 64)        
    );
    
    parameter WBCLKTYPE = "NONE";
    parameter ACLKTYPE = "NONE";
    parameter MEMCLKTYPE = "NONE";
    parameter ETHCLKTYPE = "NONE";
    parameter DEBUG = "TRUE";

    // This is where the headers get written into and where the event readout starts
    // Put it here so it changes in both the hdr_accumulator and event_readout_generator
    // whenever it changes.
    // I should however make this _calculable_ from the TURF and SURF header sizes
    // so that when the TURF header sizes change everything changes automatically.
    localparam [18:0] EVENT_BASE_ADDR = 19'h03F00;

    
    wire init_calib_complete;
    wire memclk;
    
    wire [3:0] tio_mask_aclk;
    wire [3:0] tio_mask_memclk;
    
    (* CUSTOM_CC_SRC = ETHCLKTYPE *)
    reg event_open_ethclk = 0;
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0] event_open_wbclk = {2{1'b0}};

    always @(posedge ethclk) event_open_ethclk <= event_open_i;
    always @(posedge wb_clk_i) event_open_wbclk <= { event_open_wbclk[0], event_open_ethclk };
    
    wire event_reset_wbclk;
    wire event_reset_aclk;
    wire event_reset_memclk;
    wire event_reset_ethclk;
    
    wire aresetn = !event_reset_aclk;
    wire memresetn = !event_reset_memclk;
    wire ethresetn = !event_reset_ethclk;
    
    wire out_qword = m_ev_data_tvalid && m_ev_data_tready;
    wire out_event = out_qword && m_ev_data_tlast;


    wire [3:0] track_err;
    
    wire ddr_reset;
    
    wire turf_complete_memclk = s_turfhdr_tvalid && s_turfhdr_tready && s_turfhdr_tlast;
    wire turf_complete_aclk;
    flag_sync u_turf_complete_sync(.in_clkA(turf_complete_memclk),.out_clkB(turf_complete_aclk),
                                   .clkA(memclk),.clkB(aclk));
    
    event_register_core #(.WBCLKTYPE(WBCLKTYPE),
                          .ACLKTYPE(ACLKTYPE),
                          .MEMCLKTYPE(MEMCLKTYPE),
                          .ETHCLKTYPE(ETHCLKTYPE))
        u_registers(.wb_clk_i(wb_clk_i),
                    `CONNECT_WBS_IFS( wb_ , wb_ ),
                    .tio_mask_o(tio_mask_o),
                    .tio_mask_aclk_o(tio_mask_aclk),
                    .tio_mask_memclk_o(tio_mask_memclk),
                    .runcfg_o(runcfg_o),
                    
                    .track_err_i(track_err),
                    
                    .event_open_i(event_open_wbclk[1]),
                    
                    .event_reset_o(event_reset_wbclk),
                    .event_reset_aclk_o(event_reset_aclk),
                    .event_reset_memclk_o(event_reset_memclk),
                    .event_reset_ethclk_o(event_reset_ethclk),
                    
                    .ddr_reset_memclk_o(ddr_reset),
                    
                    .aclk(aclk),
                    .aurora_tvalid( { s_aurora3_tvalid,
                                      s_aurora2_tvalid,
                                      s_aurora1_tvalid,
                                      s_aurora0_tvalid } ),
                    .ethclk(ethclk),
                    .eth_tx_qword_i( out_qword ),
                    .eth_tx_event_i( out_event ),
                    
                    .memclk(memclk));                        
    
    
    // OK OK OK HERE WE GO
    `DEFINE_AXI4S_MIN_IF( nack_mem_ , 48 ); // nack path in memclk
    `DEFINE_AXI4S_MIN_IFV( addr_ , 16, [4:0] ); // done paths in memclk
    wire incr_allow;    // increment the allow counter
    `DEFINE_AXI4S_MIN_IFV( hdr_ , 64, [3:0] ); // header path
    wire [3:0] hdr_tlast;
    `DEFINE_AXI4S_MIN_IFV( cmpl_ , 64, [3:0] ); // completions
    `DEFINE_AXI4S_MIN_IF( hdrcmpl_ , 24 ); // header completion
    
    // transfer event open over to aclk
    (* CUSTOM_CC_DST = ACLKTYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] event_open_aclk_sync = {2{1'b0}};
    wire event_open_aclk = event_open_aclk_sync[1];
    
    always @(posedge aclk) begin
        event_open_aclk_sync <= { event_open_aclk_sync[0],event_open_ethclk };
    end                
    
    // Vectorize the Aurora links. This also integrates trashing
    // events when the interface isn't open. Just force tready high
    // and 
    `DEFINE_AXI4S_MIN_IFV( aur_ , 32, [3:0] );
    wire [3:0] aur_tlast;
    `define HOOK_AURORA( to , tosuffix, from ) \
        assign to``tdata``tosuffix = from``tdata;    \
        assign to``tvalid``tosuffix = from``tvalid && event_open_aclk;  \
        assign from``tready = to``tready``tosuffix || !event_open_aclk; \
        assign to``tlast``tosuffix = from``tlast

    generate
        if (DEBUG == "TRUE") begin : ILA
            raw_event_ila u_ila(.clk(aclk),
                                .probe0( s_aurora0_tdata ),
                                .probe1( s_aurora0_tvalid ),
                                .probe2( s_aurora0_tready ),
                                .probe3( s_aurora0_tlast ),
                                .probe4( s_aurora1_tdata ),
                                .probe5( s_aurora1_tvalid ),
                                .probe6( s_aurora1_tready ),
                                .probe7( s_aurora1_tlast ),
                                .probe8( s_aurora2_tdata ),
                                .probe9( s_aurora2_tvalid ),
                                .probe10( s_aurora2_tready ),
                                .probe11( s_aurora2_tlast ),
                                .probe12( s_aurora3_tdata ),
                                .probe13( s_aurora3_tvalid ),
                                .probe14( s_aurora3_tready ),
                                .probe15( s_aurora3_tlast ));
        end
    endgenerate
    
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
                   // needs the TIO mask to fake eat the addrs.
                   .tio_mask_i(tio_mask_memclk),
                   `CONNECT_AXI4S_MIN_IF( m_nack_ , nack_mem_ ),
                   .allow_o( incr_allow ),
                   `CONNECT_AXI4S_MIN_IFV( m_t0addr_ , addr_ , [0] ),
                   `CONNECT_AXI4S_MIN_IFV( m_t1addr_ , addr_ , [1] ),
                   `CONNECT_AXI4S_MIN_IFV( m_t2addr_ , addr_ , [2] ),
                   `CONNECT_AXI4S_MIN_IFV( m_t3addr_ , addr_ , [3] ),
                   `CONNECT_AXI4S_MIN_IFV( m_hdraddr_ , addr_ , [4] ));
    // next, the completion tracker. For this we need to revectorize the aurora inputs.
    // because they're vectors, not arrays (e.g. wire bit[3:0] not wire [3:0] bit)
    wire [3:0] track_tvalid = { aur_tvalid[3], aur_tvalid[2], aur_tvalid[1], aur_tvalid[0] };
    wire [3:0] track_tlast =  { aur_tlast[3],  aur_tlast[2],  aur_tlast[1],  aur_tlast[0]  };
    wire [3:0] track_tready = { aur_tready[3], aur_tready[2], aur_tready[1], aur_tready[0] };
    
    event_completion_tracker #(.ACLKTYPE(ACLKTYPE)) 
        u_tracker(.aclk(aclk),
                  .aresetn(aresetn),
                  .enable_i(track_events_i),
                  .turf_complete_i(turf_complete_aclk),
                  .s_axis_tlast(track_tlast),
                  .s_axis_tvalid(track_tvalid),
                  .s_axis_tready(track_tready),
                  .complete_o(evin_complete_o),
                  .tio_mask_i(tio_mask_aclk),
                  .err_o(track_err));
                  
    
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
            turfio_event_accumulator #(.DEBUG(i == 0 ? "TRUE" : "FALSE"))
                u_accum( .aclk( aclk ),
                         .aresetn( aresetn ),
                         `CONNECT_AXI4S_MIN_IFV( s_axis_ , aur_ , [i] ),
                         .s_axis_tlast( aur_tlast[i] ),
                         .memclk( memclk ),
                         .memresetn( memresetn ),
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
            pueo_turfio_event_req_gen #(.BASE_ADDRESS_4KB(4 + 28*i),.DEBUG(i==0 ? "TRUE" : "FALSE"))
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
    hdr_accumulator #(.BASE_ADDR(EVENT_BASE_ADDR)) u_headers( .aclk(aclk),
                               .aresetn(aresetn),
                               .tio_mask_i(tio_mask_aclk),
                               `CONNECT_AXI4S_MIN_IFV( s_done_ , addr_ , [4] ),
                               `CONNECT_AXI4S_MIN_IF( m_cmpl_ , hdrcmpl_ ),
                               `CONNECT_AXI4S_MIN_IF( s_thdr_ , s_turfhdr_ ),
                               .s_thdr_tlast( s_turfhdr_tlast ),
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
    
    // and the readout generator.
    event_readout_generator #(.MEMCLKTYPE(MEMCLKTYPE),
                              .ACLKTYPE(ETHCLKTYPE),
                              .START_OFFSET(EVENT_BASE_ADDR))
        u_readout( .memclk(memclk),
                   .memresetn(memresetn),
                   // completions
                   .tio_mask_i(tio_mask_memclk),
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
                   `CONNECT_AXI4S_IF( m_data_ , m_ev_data_ ),
                   .any_err_o( readout_err ));
    
    // and now the interconnect
    // NOW WITH TOTAL INSANITY    
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
    // the MIG *** cannot *** be put into reset like this!!
    // it needs to actually, y'know, RUN occasionally.
    // So we siphon off its reset.
    ddr4_mig u_mig( .sys_rst(ddr_reset),
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

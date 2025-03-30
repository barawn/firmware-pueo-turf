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
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_ack_ , 16),
        // nacking path
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_nack_ , 16),
        // event open interface
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

    reg ack = 0;
    assign wb_ack_o = ack && !wb_cyc_i;
    assign wb_dat_o = { {31{1'b0}}, event_reset };
    always @(posedge wb_clk_i) begin
        ack <= wb_cyc_i && wb_stb_i;
        if (wb_cyc_i && wb_stb_i && wb_ack_o && wb_we_i) begin
            // just grab all the addresses
            if (wb_sel_i[0]) event_reset <= wb_dat_i[0];
        end
    end
    always @(posedge aclk) event_reset_aclk <= { event_reset_aclk[0], event_reset };
    always @(posedge ddr4_clk_o) event_reset_memclk <= { event_reset_memclk[0], event_reset };
    always @(posedge ethclk) event_reset_ethclk <= { event_reset_ethclk[0], event_reset };
    
    // just terminate stuff for now
    assign s_aurora0_tready = 1'b1;
    assign s_aurora1_tready = 1'b1;
    assign s_aurora2_tready = 1'b1;
    assign s_aurora3_tready = 1'b1;
    assign s_ack_tready = 1'b1;
    assign s_nack_tready = 1'b1;
    assign m_ev_ctrl_tvalid = 0;
    assign m_ev_data_tvalid = 0;    

    // This is the AXI4 interface used for DDR.
    `AXIM_DECLARE( memaxi_ , 1 );
    wire [2:0] memaxi_arid;
    wire [2:0] memaxi_awid;
    wire [2:0] memaxi_bid;
    wire [2:0] memaxi_rid;
    
    // ok now terminate stuff
    assign memaxi_arid = {3{1'b0}};
    assign memaxi_awid = {3{1'b0}};
    assign memaxi_bid = {3{1'b0}};
    assign memaxi_rid = {3{1'b0}};
    `define KILL_AXI_ADDR( pfx )            \
        assign pfx``addr = {32{1'b0}};      \
        assign pfx``len = {8{1'b0}};        \
        assign pfx``size = {3{1'b0}};       \
        assign pfx``burst = {2{1'b0}};      \
        assign pfx``lock = 1'b0;            \
        assign pfx``cache = {4{1'b0}};      \
        assign pfx``prot = {3{1'b0}};       \
        assign pfx``qos = {4{1'b0}};        \
        assign pfx``valid = 1'b0;
    `KILL_AXI_ADDR( memaxi_aw );
    `KILL_AXI_ADDR( memaxi_ar );
    assign memaxi_wdata = {512{1'b0}};
    assign memaxi_wstrb = {64{1'b0}};
    assign memaxi_wvalid = 1'b0;
    assign memaxi_wlast = 1'b0;
    assign memaxi_rready = 1'b1;
    assign memaxi_bready = 1'b1;
    
    wire init_calib_complete;
    wire memclk;
    assign ddr4_clk_o = memclk;
    // no WID, xbars don't do write reording.
    ddr4_mig u_mig( .sys_rst(!memresetn),
                    .c0_sys_clk_p(DDR_CLK_P),
                    .c0_sys_clk_n(DDR_CLK_N),
                    .c0_init_calib_complete(init_calib_complete),
                    .c0_ddr4_aresetn(memresetn),
                    .c0_ddr4_ui_clk( memclk ),
      `CONNECT_AXIM( c0_ddr4_s_axi_ ,     memaxi_       ),
                    .c0_ddr4_s_axi_arid ( memaxi_arid   ),
                    .c0_ddr4_s_axi_awid ( memaxi_awid   ),
                    .c0_ddr4_s_axi_rid  ( memaxi_rid    ),
                    .c0_ddr4_s_axi_bid  (  memaxi_bid   ),
    `CONNECT_PHY_IF( c0_ddr4_ ,            c0_ddr4_     ));

        
endmodule

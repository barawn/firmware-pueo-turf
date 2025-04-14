`timescale 1ns / 1ps
`include "interfaces.vh"
`include "mem_axi.vh"
module turfio_event_accumulator_tb;
    wire aclk;
    wire ethclk;
    wire ddr4_clk_p;
    wire ddr4_clk_n = !ddr4_clk_p;
    tb_rclk #(.PERIOD(6.4)) u_aclk(.clk(aclk));
    tb_rclk #(.PERIOD(3.333)) u_refclk(.clk(ddr4_clk_p));
    tb_rclk #(.PERIOD(6.4)) u_ethclk(.clk(ethclk));
    reg start = 0;    
    reg run_indata = 0;
    // this ends up being 24,584: each SURF has (1536*8 + 4) = 12,292 words and it takes
    // 2 clocks to deliver all SURFs.
    reg [15:0] indata_counter = {16{1'b0}};
    reg [31:0] indata = {32{1'b0}};
    reg        indata_valid = 0;
    wire [31:0] indata_tdata = indata;
    wire       indata_tvalid = indata_valid || run_indata;
    reg        indata_tlast = 0;
    wire       indata_tready;
        
    always @(posedge aclk) begin
        if (start) run_indata <= 1;
        else if (indata_counter == 24582) run_indata <= 0;
        
        if (!run_indata) indata_counter <= {16{1'b0}};
        else indata_counter <= indata_counter + 1;

        indata_tlast <= (indata_counter == 24583);
        if (!run_indata) begin
            indata <= 32'hC0804000;
            indata_valid <= 1'b0;            
        end else begin
            // the way this works, the headers will contain
            // C1 81 41 01 C0 80 40 00
            // C3 83 43 03 C2 82 42 02
            // C5 85 45 05 C4 84 44 04
            // C7 87 47 07 C6 86 46 06
            // which should be interpreted as headers of
            // 00 02 04 06 (SURF0)
            // 40 42 44 46
            // ..
            // 81 83 85 87 (SURF6)
            // C1 C3 C5 C7 (TURFIO - ignored)
            //
            // the output data for SURF0 would then start off
            // 08 0A 0C 0E 10 12 14 16
            // etc. for SURF1/2/3/4/5/6
            indata[0 +: 8] <= indata[0 +: 8] + 1;
            indata[8 +: 8] <= indata[8 +: 8] + 1;
            indata[16 +: 8] <= indata[16 +: 8] + 1;
            indata[24 +: 8] <= indata[24 +: 8] + 1;
            indata_valid <= 1'b1;
        end
    end
    
    // AXI links
    `AXIM_DECLARE( dmaxi_ , 4);
    `AXIM_DECLARE_DW( hdraxi_ , 1, 64 );
    `AXIM_DECLARE( outaxi_ , 1);
    `AXIM_DECLARE( memaxi_ , 1);
    // kill the qos/lock for mem
    wire [3:0] memaxi_arqos = {4{1'b0}};
    wire [3:0] memaxi_awqos = {4{1'b0}};
    wire memaxi_arlock = 1'b0;
    wire memaxi_awlock = 1'b0;
    // now we have to define and hook up the IDs
    wire [2:0] memaxi_arid;
    wire [2:0] memaxi_awid;
    wire [2:0] memaxi_bid;
    wire [2:0] memaxi_rid;
    
    
    
    // tedious crap
    `define KILL_SAXI_ADDR( pfx )            \
        assign pfx``addr = {32{1'b0}};      \
        assign pfx``len = {8{1'b0}};        \
        assign pfx``size = {3{1'b0}};       \
        assign pfx``burst = {2{1'b0}};      \
        assign pfx``lock = 1'b0;            \
        assign pfx``cache = {4{1'b0}};      \
        assign pfx``prot = {3{1'b0}};       \
        assign pfx``qos = {4{1'b0}};        \
        assign pfx``valid = 1'b0

    `define KILL_SAXI_DATA( pfx )           \
        assign pfx``wdata = {512{1'b0}};    \
        assign pfx``wstrb = {64{1'b0}};     \
        assign pfx``wvalid = 1'b0;          \
        assign pfx``wlast = 1'b0;           \
        assign pfx``rready = 1'b1;          \
        assign pfx``bready = 1'b1
        
        
    `define KILL_AXI_VEC_ADDR( pfx, idx) \
        assign pfx``addr[32*idx +: 32] = {32{1'b0}}; \
        assign pfx``len[8*idx +: 8] = {8{1'b0}};    \
        assign pfx``size[3*idx +: 3] = {3{1'b0}};   \
        assign pfx``burst[2*idx +: 2] = {2{1'b0}};  \
        assign pfx``cache[4*idx +: 4] = {4{1'b0}};  \
        assign pfx``prot[3*idx +: 3] = {3{1'b0}};   \
        assign pfx``valid[idx] = 1'b0

    `define KILL_AXI_VEC_DATA( pfx , idx ) \
        assign pfx``wdata[512*idx +: 512] = {512{1'b0}};    \
        assign pfx``wstrb[64*idx +: 64] = {64{1'b0}};     \
        assign pfx``wvalid[idx] = 1'b0;          \
        assign pfx``wlast[idx] = 1'b0;           \
        assign pfx``rready[idx] = 1'b1;          \
        assign pfx``bready[idx] = 1'b1

    wire memclk;

    // req gen reset
    reg reset_reqgen = 0;
    reg run_doneaddr = 0;
    // ACTUALLY create completion links now
    wire [63:0] tfio_cmpl_tdata[3:0];
    wire [3:0] tfio_cmpl_tvalid;
    wire [3:0] tfio_cmpl_tready;
    // header completions
    wire [23:0] hdr_cmpl_tdata;
    wire hdr_cmpl_tvalid;
    wire hdr_cmpl_tready;
    
    // and the header links
    wire [63:0] tfio_hdr_tdata[3:0];
    wire [3:0] tfio_hdr_tvalid;
    wire [3:0] tfio_hdr_tready;
    wire [3:0] tfio_hdr_tlast;            
    generate
        genvar i;
        for (i=0;i<4;i=i+1) begin : TFIO
                // this is now internal in the loop
                wire [63:0] outdata;
                wire        outdata_valid;
                wire        outdata_last;
                wire [4:0]  outdata_ident;
                wire        outdata_has_space;
                    
                `DEFINE_AXI4S_MIN_IF( hdr_ , 64);
                wire hdr_tlast;
                
                assign tfio_hdr_tdata[i] = hdr_tdata;
                assign tfio_hdr_tvalid[i] = hdr_tvalid;
                assign tfio_hdr_tlast[i] = hdr_tlast;
                assign hdr_tready = tfio_hdr_tready[i];
            
                // ok now start with turfio event accumulator...    
                turfio_event_accumulator uut( .aclk(aclk),
                                              .aresetn(1'b1),
                                              .memclk(memclk),
                                              .memresetn(1'b1),
                                              .s_axis_tdata( indata_tdata ),
                                              .s_axis_tvalid(indata_tvalid),
                                              .s_axis_tready(indata_tready),
                                              .s_axis_tlast( indata_tlast),
                                              `CONNECT_AXI4S_MIN_IF( m_hdr_ , hdr_ ),
                                              .m_hdr_tlast( hdr_tlast ),
                                              .payload_o(outdata ),
                                              .payload_valid_o(outdata_valid),
                                              .payload_last_o(outdata_last),
                                              .payload_ident_o(outdata_ident),
                                              .payload_has_space_i(outdata_has_space));
                // and pass over to the req gen.
                // we need a done input...
                reg [15:0] done_tdata = {16{1'b0}};
                reg        done_tvalid = 0;
                wire       done_tready;
                always @(posedge memclk) begin
                    if (run_doneaddr) done_tvalid <= 1;
                    if (done_tready) done_tdata <= done_tdata + 1;
                end        
                `DEFINE_AXI4S_MIN_IF( mycmpl_ , 64 );
                assign tfio_cmpl_tdata[i] = mycmpl_tdata;
                assign tfio_cmpl_tvalid[i] = mycmpl_tvalid;
                assign mycmpl_tready = tfio_cmpl_tready[i];
                // you need base addresses now!
                // TIO0 = 0_4000
                // TIO1 = 2_0000
                // TIO2 = 3_C000
                // TIO3 = 5_8000
                // We pass the top 7 bits, which is the 3 top bits
                // plus next nybble, so 0x04, 0x20, 0x3C, 0x58
                // or 4, 32, 60, 88.
                // This also helps the write bandwidth:
                // the column sizes are 8 kB (8 x 1024) and so
                // if we order row, bank, column none of our
                // TURFIOs are in the same bank, so the data
                // can fly at the same time.
                pueo_turfio_event_req_gen #(.BASE_ADDRESS_4KB(4 + 28*i))
                                          u_reqgen(.memclk(memclk),
                                                   .memresetn(!reset_reqgen),
                                                   .payload_i(outdata),
                                                   .payload_valid_i(outdata_valid),
                                                   .payload_last_i(outdata_last),
                                                   .payload_ident_i(outdata_ident),
                                                   .payload_has_space_o(outdata_has_space),
                                                   `CONNECT_AXIM_VEC( m_axi_ , dmaxi_ , i),
                                                   `CONNECT_AXI4S_MIN_IF( s_done_ , done_ ),
                                                   `CONNECT_AXI4S_MIN_IF( m_cmpl_ , mycmpl_ ));
        end
    endgenerate        
    // now the header accumulator.
    // need turf data.
    // turf data needs to fill up 128 bytes = 16 beats
    reg [63:0] thdr_tdata = {64{1'b0}};
    reg thdr_tvalid = 0;
    wire thdr_tlast;
    wire thdr_tready;
    wire [3:0] tio_mask = {4{1'b0}};
    reg [15:0] hdone_tdata = {16{1'b0}};
    reg        hdone_tvalid = 0;
    wire       hdone_tready;
    always @(posedge memclk) begin
        if (run_doneaddr) hdone_tvalid <= 1;
        if (hdone_tready) hdone_tdata <= hdone_tdata + 1;
    end        
    hdr_accumulator u_hdr( .aclk(aclk),
                           .aresetn(1'b1),
                           .tio_mask_i(tio_mask),
                           `CONNECT_AXI4S_MIN_IF( s_done_ , hdone_ ),
                           `CONNECT_AXI4S_MIN_IF( m_cmpl_ , hdr_cmpl_ ),
                           `CONNECT_AXI4S_MIN_IF( s_thdr_ , thdr_ ),
                           .s_thdr_tlast(thdr_tlast),
                           .s_hdr0_tdata( tfio_hdr_tdata[0] ),
                           .s_hdr0_tvalid(tfio_hdr_tvalid[0]),
                           .s_hdr0_tready(tfio_hdr_tready[0]),
                           .s_hdr0_tlast( tfio_hdr_tlast[0] ),

                           .s_hdr1_tdata( tfio_hdr_tdata[1] ),
                           .s_hdr1_tvalid(tfio_hdr_tvalid[1]),
                           .s_hdr1_tready(tfio_hdr_tready[1]),
                           .s_hdr1_tlast( tfio_hdr_tlast[1] ),

                           .s_hdr2_tdata( tfio_hdr_tdata[2] ),
                           .s_hdr2_tvalid(tfio_hdr_tvalid[2]),
                           .s_hdr2_tready(tfio_hdr_tready[2]),
                           .s_hdr2_tlast( tfio_hdr_tlast[2] ),

                           .s_hdr3_tdata( tfio_hdr_tdata[3] ),
                           .s_hdr3_tvalid(tfio_hdr_tvalid[3]),
                           .s_hdr3_tready(tfio_hdr_tready[3]),
                           .s_hdr3_tlast( tfio_hdr_tlast[3] ),
                           
                           .memclk(memclk),
                           .memresetn(!reset_reqgen),
                           `CONNECT_AXIM_DW( m_axi_ , hdraxi_ , 64 ));
    // and now FINALLY the event generator
    reg intercon_reset = 1;

    `DEFINE_AXI4S_MIN_IF( ev_ctrl_ , 32 );
    `DEFINE_AXI4S_IF( ev_data_ , 64 );
    
    assign ev_ctrl_tready = 1'b1;
    assign ev_data_tready = 1'b1;
    wire any_err;
    event_readout_generator u_generator( .memclk(memclk),
                                         .memresetn(!intercon_reset),
                                         `CONNECT_AXI4S_MIN_IF( s_hdr_ , hdr_cmpl_ ),
                                         .s_t0_tdata( tfio_cmpl_tdata[0] ),
                                         .s_t1_tdata( tfio_cmpl_tdata[1] ),
                                         .s_t2_tdata( tfio_cmpl_tdata[2] ),
                                         .s_t3_tdata( tfio_cmpl_tdata[3] ),
                                         .s_t0_tready(tfio_cmpl_tready[0]),
                                         .s_t1_tready(tfio_cmpl_tready[1]),
                                         .s_t2_tready(tfio_cmpl_tready[2]),
                                         .s_t3_tready(tfio_cmpl_tready[3]),
                                         .s_t0_tvalid(tfio_cmpl_tvalid[0]),
                                         .s_t1_tvalid(tfio_cmpl_tvalid[1]),
                                         .s_t2_tvalid(tfio_cmpl_tvalid[2]),
                                         .s_t3_tvalid(tfio_cmpl_tvalid[3]),
                                         .aclk(ethclk),
                                         .aresetn(1'b1),
                                         `CONNECT_AXI4S_MIN_IF( m_ctrl_ , ev_ctrl_ ),
                                         `CONNECT_AXI4S_MIN_IF( m_data_ , ev_data_ ),
                                         `CONNECT_AXIM( m_axi_ , outaxi_ ),
                                         .any_err_o(any_err));


    // interconnect
    ddr_intercon_wrapper #(.DEBUG("FALSE"))
        u_intercon(.aclk(memclk),
                   .aresetn(!intercon_reset),
                   `CONNECT_AXIM_DW( s_axi_hdr_ , hdraxi_ , 64 ),
                   `CONNECT_AXIM( s_axi_in_ , dmaxi_ ),
                   `CONNECT_AXIM( s_axi_out_ , outaxi_ ),
                   `CONNECT_AXIM( m_axi_ , memaxi_ ),
                   .m_axi_arid( memaxi_arid ),
                   .m_axi_awid( memaxi_awid ),
                   .m_axi_bid(  memaxi_bid ),
                   .m_axi_rid(  memaxi_rid )
                   );

    // need connections for MIG->RAM...
    wire DDR4_ACT_N;
    wire [16:0] DDR4_A;
    wire [1:0] DDR4_BA;
    wire [0:0] DDR4_BG;
    wire [0:0] DDR4_CKE;
    wire [0:0] DDR4_ODT;
    wire [0:0] DDR4_CS_N;
    wire [0:0] DDR4_CK_T;
    wire [0:0] DDR4_CK_C;
    wire DDR4_RESET_N;
    wire [7:0] DDR4_DM_DBI_N;
    wire [63:0] DDR4_DQ;
    wire [7:0] DDR4_DQS_T;
    wire [7:0] DDR4_DQS_C;
    wire ddr4_ready;   
//        input c0_ddr4_act_n,
//        input [16:0] c0_ddr4_adr,
//        input [1:0] c0_ddr4_ba,
//        input [0:0] c0_ddr4_bg,
//        input [0:0] c0_ddr4_cke,
//        input [0:0] c0_ddr4_odt,
//        input [0:0] c0_ddr4_cs_n,
//        input [0:0] c0_ddr4_ck_t,
//        input [0:0] c0_ddr4_ck_c,
//        input c0_ddr4_reset_n,
//        inout [7:0] c0_ddr4_dm_dbi_n,
//        inout [63:0] c0_ddr4_dq,
//        inout [7:0] c0_ddr4_dqs_t,
//        inout [7:0] c0_ddr4_dqs_c 
wire ddr4_reset = 0;               
ddr4_mig u_memory( .c0_sys_clk_p(ddr4_clk_p),.c0_sys_clk_n(ddr4_clk_n),
         `CONNECT_AXIM( c0_ddr4_s_axi_      ,   memaxi_       ),
                       .c0_ddr4_s_axi_arid( memaxi_arid ),
                       .c0_ddr4_s_axi_awid( memaxi_awid ),
                       .c0_ddr4_s_axi_bid( memaxi_bid ),
                       .c0_ddr4_s_axi_rid( memaxi_rid ),                       
                       .c0_ddr4_aresetn( 1'b1 ),
                       .sys_rst( ddr4_reset ),
                       
                       .c0_ddr4_act_n( DDR4_ACT_N ),
                       .c0_ddr4_adr  ( DDR4_A ),
                       .c0_ddr4_ba   ( DDR4_BA ),
                       .c0_ddr4_bg   ( DDR4_BG ),
                       .c0_ddr4_ck_c ( DDR4_CK_C ),
                       .c0_ddr4_ck_t ( DDR4_CK_T ),
                       .c0_ddr4_cke  ( DDR4_CKE ),
                       .c0_ddr4_cs_n ( DDR4_CS_N ),
                       .c0_ddr4_dm_dbi_n ( DDR4_DM_DBI_N ),
                       .c0_ddr4_dq   ( DDR4_DQ ),
                       .c0_ddr4_dqs_c( DDR4_DQS_C ),
                       .c0_ddr4_dqs_t( DDR4_DQS_T ),
                       .c0_ddr4_odt  ( DDR4_ODT ),
                       .c0_ddr4_reset_n ( DDR4_RESET_N ),
                       .c0_init_calib_complete( ddr4_ready ),
                       .c0_ddr4_ui_clk( memclk ));
    // and the memory
sim_mem_wrapper u_mem(                     
                     .c0_ddr4_act_n            (DDR4_ACT_N),
                     .c0_ddr4_adr              (DDR4_A),
                     .c0_ddr4_ba               (DDR4_BA),
                     .c0_ddr4_bg               (DDR4_BG),
                     .c0_ddr4_ck_c             (DDR4_CK_C),
                     .c0_ddr4_ck_t             (DDR4_CK_T),
                     .c0_ddr4_cke              (DDR4_CKE),
                     .c0_ddr4_cs_n             (DDR4_CS_N),
                     .c0_ddr4_dm_dbi_n         (DDR4_DM_DBI_N),
                     .c0_ddr4_dq               (DDR4_DQ),
                     .c0_ddr4_dqs_c            (DDR4_DQS_C),
                     .c0_ddr4_dqs_t            (DDR4_DQS_T),
                     .c0_ddr4_odt              (DDR4_ODT),
                     .c0_ddr4_reset_n          (DDR4_RESET_N));                                                   

    reg [4:0] thdr_beats = {5{1'b0}};
    assign thdr_tlast = (thdr_beats == 5'd15);
    always @(posedge memclk) begin
        // when we hit 15 we've sent 
        if (thdr_tvalid && thdr_tready)
            thdr_beats <= #0.1 thdr_beats + 1;
        thdr_tvalid <= #0.1 (run_doneaddr && thdr_beats < 5'd15);        
    end
                                  
    initial begin
        #500;        
        @(posedge memclk);
        while (!ddr4_ready) #0.1 @(posedge memclk);
        #10;
        @(posedge memclk);
        #0.1 reset_reqgen = 1;
        intercon_reset = 0;
        @(posedge memclk);
        #0.1 reset_reqgen = 0;
        @(posedge aclk);
        #1 start = 1;
        @(posedge aclk);
        #1 start = 0;
        @(posedge memclk);
        #1 run_doneaddr = 1;
        #70000;
    end                                  

endmodule

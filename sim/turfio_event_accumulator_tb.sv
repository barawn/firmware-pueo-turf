`timescale 1ns / 1ps
module turfio_event_accumulator_tb;
    wire aclk;
    wire ddr4_clk_p;
    wire ddr4_clk_n = !ddr4_clk_p;
    tb_rclk #(.PERIOD(8)) u_aclk(.clk(aclk));
    tb_rclk #(.PERIOD(3.333)) u_refclk(.clk(ddr4_clk_p));

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
    
    wire [63:0] outdata;
    wire        outdata_valid;
    wire        outdata_last;
    wire [4:0]  outdata_ident;
    wire        outdata_has_space;
        
    wire [63:0] hdrdata;
    wire        hdrvalid;
    wire        hdrready = 1'b1;
    wire        hdrtlast;
    
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

    // ok now start with turfio event accumulator...    
    turfio_event_accumulator uut( .aclk(aclk),
                                  .aresetn(1'b1),
                                  .memclk(memclk),
                                  .memresetn(1'b1),
                                  .s_axis_tdata( indata_tdata ),
                                  .s_axis_tvalid(indata_tvalid),
                                  .s_axis_tready(indata_tready),
                                  .s_axis_tlast( indata_tlast),
                                  .m_hdr_tdata( hdrdata ),
                                  .m_hdr_tvalid(hdrvalid),
                                  .m_hdr_tready(hdrready),
                                  .m_hdr_tlast(hdrtlast),
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
    // and a completion output    
    wire [63:0] cmpl_tdata;
    wire        cmpl_tvalid;
    wire        cmpl_tready = 1;
    // and an AXI link
    `AXIM_DECLARE( dmaxi_ , 1);
    // need to kill the IDs to hook it up to the RAM
    wire [2:0] dmaxi_arid = {3{1'b0}};
    wire [2:0] dmaxi_awid = {3{1'b0}};
    wire [2:0] dmaxi_bid = {3{1'b0}};
    wire [2:0] dmaxi_rid = {3{1'b0}};
    // req gen
    pueo_turfio_event_req_gen u_reqgen(.memclk(memclk),
                                       .memresetn(1'b1),
                                       .payload_i(outdata),
                                       .payload_valid_i(outdata_valid),
                                       .payload_last_i(outdata_last),
                                       .payload_ident_i(outdata_ident),
                                       .payload_has_space_o(outdata_has_space),
                                       `CONNECT_AXIM( m_axi_ , dmaxi_ ),
                                       `CONNECT_AXI4S_MIN_IF( s_done_ , done_ ),
                                       `CONNECT_AXI4S_MIN_IF( m_cmpl_ , cmpl_ ));
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
         `CONNECT_AXIM( c0_ddr4_s_axi_      ,   dmaxi_       ),
                       .c0_ddr4_s_axi_arid  (   dmaxi_arid   ),
                       .c0_ddr4_s_axi_awid  (   dmaxi_awid   ),
                       .c0_ddr4_s_axi_rid   (   dmaxi_rid    ),
                       .c0_ddr4_s_axi_bid   (   dmaxi_bid    ),
                       
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

    reg run_doneaddr = 0;
    always @(posedge memclk) begin
        if (run_doneaddr) done_tvalid <= 1;
        if (done_tready) done_tdata <= done_tdata + 1;
    end        
                                  
    initial begin
        #500;        
        @(posedge memclk);
        while (!ddr4_ready) #0.1 @(posedge memclk);
        #10;
        @(posedge aclk);
        #1 start = 1;
        @(posedge aclk);
        #1 start = 0;
        @(posedge memclk);
        #1 run_doneaddr = 1;
        #70000;
    end                                  

endmodule

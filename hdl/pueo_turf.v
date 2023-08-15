`timescale 1ns / 1ps
`include "interfaces.vh"

// sigh, let's just special-case out the GBE stuff to avoid this crap.
//`define USE_GBE

module pueo_turf #(
            parameter [31:0] IDENT = "TURF",
            parameter [3:0] VER_MAJOR = 4'd0,
            parameter [3:0] VER_MINOR = 4'd0,
            parameter [7:0] VER_REV = 8'd7,
            parameter [15:0] FIRMWARE_DATE = {16{1'b0}},
            parameter PROTOTYPE = "TRUE"
        )(
        // B2B-1 32 PL_D9_LVDS93_L12P - D9  bank 93
        output HSK_UART_txd,
        // B2B-1 34 PL_C9_LVDS93_L12N - C9
        input HSK_UART_rxd,
        
        // B2B-1 31 PL_B7_LVDS93_L10P - B7
        input HSK2_UART_rxd,
        // B2B-1 33 PL_A7_LVDS93_L10N - A7
        output HSK2_UART_txd,
        
        // B2B-1 22 PL_C8_LVDS93_L8N_HDGC - C8
        inout CLK_IIC_scl_io,
        // B2B-1 24 PL_D8_LVDS93_L8P_HDGC - D8
        inout CLK_IIC_sda_io,
        
        // B2B-2 177 PL_AR12_LVDS67_L13N - AR12 (previously 117)
        input SYSCLK_P,
        // B2B-2 175 PL_AR13_LVDS67_L13P - AR13 (previously 118)
        input SYSCLK_N,
        
        // B2B-2 188 GTREFCLK0P_227 AD12
        input MGTCLK_N,
        // B2B-2 190 GTREFCLK0N_227 AD11
        input MGTCLK_P,
        
        // MGT links to TURFIOs. Polarity labelling on the board is unimportant, they figure it out.
        // bit 0 (A) link 1 : RX=199/201=AG2/AG1, TX=205/207=AF8/AF7  (X0Y13)
        // bit 1 (B) link 2 : RX=211/213=AF4/AF3, TX=217/219=AE6/AE5  (X0Y14)
        // bit 2 (C) link 3 : RX=194/196=AE2/AE1, TX=200/202=AD8/AD7  (X0Y15)
        // bit 3 (D) link 0 : RX=187/189=AH4/AH3, TX=193/195=AG6/AG5  (X0Y12)
        input [3:0] MGTRX_P,
        input [3:0] MGTRX_N,
        output [3:0] MGTTX_P,
        output [3:0] MGTTX_N,
        
        // bit 0 (A) link 1 : RX=109/111=AR2/AR1, TX=103/105=AP8/AP7
        // bit 1 (B) link 0 : RX=115/117=AT4/AT3, TX=97/99=AR6/AR5
        `ifdef USE_GBE
        input [1:0] GBE_RX_P,
        input [1:0] GBE_RX_N,
        output [1:0] GBE_TX_P,
        output [1:0] GBE_TX_N,
        `endif
        
        // B2B-1 98 GTREFCLK0P_225 AH12
        input GBE_CLK_P,
        // B2B-1 100 GTREFCLK0N_225 AH11
        input GBE_CLK_N,      
        // not connected, here for stupid ibert
// if you leave them not present they get trimmed
//        input NC_GCLK_P,
//        input NC_GCLK_N,  
//        input [1:0] NC_RX_P,
//        input [1:0] NC_RX_N,
//        output [1:0] NC_TX_P,
//        output [1:0] NC_TX_N,
        
        // whatever, these don't matter, not sure if I'll use the strobes
        // B2B-2 116 PL_G17_LVDS68_L11P_GC G17
        input [0:0] RXCLK_P,
        // B2B-2 118 PL_F17_LVDS68_L11N_GC F17
        input [0:0] RXCLK_N,

        // INV_TXCLK = 1010                
        // B2B-2 122 PL_AM10_LVDS67_L18P AM10
        // B2B-2 75  PL_B15_LVDS68_L18N  B15
        // B2B-2 145 PL_P16_LVDS68_L2P   P16
        // B2B-2 157 PL_AW10_LVDS67_L9N  AW10
        output [3:0] TXCLK_P,
        // B2B-2 124 PL_AN10_LVDS67_L18N AN10
        // B2B-2 77  PL_C15_LVDS68_L18P  C15
        // B2B-2 143 PL_N16_LVDS68_L2N   N16
        // B2B-2 155 PL_AW11_LVDS67_L9P  AW11
        output [3:0] TXCLK_N,
        
        // INV_CINTIO=1100
        // CIN_CLKTYPE=0011
        // B2B-2 92  PL_B13_LVDS68_L16P_QBC B13
        // B2B-2 76  PL_A14_LVDS68_L17P     A14
        // B2B-2 134 PL_BB8_LVDS67_L2N      BB8
        // B2B-2 154 PL_AN13_LVDS67_L23N    AN13
        input [3:0] CINTIO_P,
        // B2B-2 94  PL_A12_LVDS68_L16N_QBC A12
        // B2B-2 78  PL_A13_LVDS68_L17N     A13
        // B2B-2 132 PL_BB9_LVDS67_L2P      BB9
        // B2B-2 152 PL_AM13_LVDS67_L23P    AM13
        input [3:0] CINTIO_N,        

        // INV_COUT = 1110
        // COUT_CLKTYPE = 0110
        // B2B-2 126 PL_AL15_LVDS67_L19P_DBC AL15
        // B2B-2 79  PL_A18_LVDS68_L24N      A18
        // B2B-2 141 PL_C13_LVDS68_L15N      C13
        // B2B-2 161 PL_AY9_LVDS67_L1N_DBC   AY9
        output [3:0] COUT_P,

        // B2B-2 128 PL_AM15_LVDS67_L19N_DBC AM15
        // B2B-2 81 PL_B18_LVDS68_L24P       B18
        // B2B-2 139 PL_D13_LVDS68_L15P      D13
        // B2B-2 159 PL_AW9_LVDS67_L1P_DBC   AW9
        output [3:0] COUT_N,
        
        // INV_CINA = 0000010
        // B2B-2 99  PL_J16_LVDS68_L8P      J16
        // B2B-2 96  PL_C18_LVDS68_L23N     C18
        // B2B-2 103 PL_E16_LVDS68_L19P_DBC E16
        // B2B-2 100 PL_G18_LVDS68_L10P_QBC G18
        // B2B-2 109 PL_G16_LVDS68_L12P_GC  G16
        // B2B-2 104 PL_P15_LVDS68_L1P_DBC  P15
        // B2B-2 115 PL_F14_LVDS68_L13P_GC  F14   
        input [6:0] CINA_P,
        
        // B2B-2 101 PL_H16_LVDS68_L8N      H16
        // B2B-2 98  PL_D18_LVDS68_L23P     D18
        // B2B-2 105 PL_D16_LVDS68_L19N_DBC D16
        // B2B-2 102 PL_F18_LVDS68_L10N_QBC F18
        // B2B-2 111 PL_F15_LVDS68_L12N_GC  F15
        // B2B-2 106 PL_N15_LVDS68_L1N_DBC  N15
        // B2B-2 117 PL_E14_LVDS68_L13N_GC  E14   
        input [6:0] CINA_N,
        
        // INV_CINB = 0001011
        // B2B-2 83 PL_K17_LVDS68_L6N       K17
        // B2B-2 80 PL_B16_LVDS68_L20N      B16
        // B2B-2 87 PL_E17_LVDS68_L21P      E17
        // B2B-2 84 PL_A17_LVDS68_L22N_DBC  A17
        // B2B-2 91 PL_J18_LVDS68_L9P       J18
        // B2B-2 88 PL_M15_LVDS68_L4P_DBC   M15
        // B2B-2 95 PL_K16_LVDS68_L5P       K16      
        input [6:0] CINB_P,

        // B2B-2 85 PL_L17_LVDS68_L6P       L17
        // B2B-2 82 PL_C16_LVDS68_L20P      C16
        // B2B-2 89 PL_D17_LVDS68_L21N      D17
        // B2B-2 86 PL_B17_LVDS68_L22P_DBC  B17
        // B2B-2 93 PL_H18_LVDS68_L9N       H18
        // B2B-2 90 PL_L15_LVDS68_L4N_DBC   L15
        // B2B-2 97 PL_K15_LVDS68_L5N       K15        
        input [6:0] CINB_N,        
        
        // INV_CINC = 1111111
        //B2B-2 133 PL_AN11_LVDS67_L17N     AN11
        //B2B-2 138 PL_AP14_LVDS67_L22N_DBC AP14
        //B2B-2 137 PL_AK15_LVDS67_L20N     AK15
        //B2B-2 142 PL_AK14_LVDS67_L24N     AK14
        //B2B-2 149 PL_AR14_LVDS67_L15N     AR14
        //B2B-2 146 PL_AM14_LVDS67_L21N     AM14
        //B2B-2 153 PL_AV11_LVDS67_L8N      AV11
        input [6:0] CINC_P,
        
        //B2B-2 131 PL_AM11_LVDS67_L17P     AM11
        //B2B-2 136 PL_AN14_LVDS67_L22P_DBC AN14
        //B2B-2 135 PL_AJ15_LVDS67_L20P     AJ15
        //B2B-2 140 PL_AJ14_LVDS67_L24P     AJ14
        //B2B-2 147 PL_AR15_LVDS67_L15P     AR15
        //B2B-2 144 PL_AL14_LVDS67_L21P     AL14
        //B2B-2 151 PL_AU11_LVDS67_L8P      AU11
        input [6:0] CINC_N,

        // INV_CIND = 1100111
        //B2B-2 165 PL_BA7_LVDS67_L4N_DBC   BA7
        //B2B-2 158 PL_AY8_LVDS67_L3N       AY8
        //B2B-2 171 PL_AR10_LVDS67_L14N_GC  AR10
        //B2B-2 162 PL_BA6_LVDS67_L5P       BA6
        //B2B-2 183 PL_AV12_LVDS67_L7P_QBC  AV12 (was AR12)
        //B2B-2 166 PL_AV8_LVDS67_L10N_QBC  AV8
        //B2B-2 184 PL_AP12_LVDS67_L16N_QBC AP12 (was AV12)                   
        input [6:0] CIND_P,
   
        //B2B-2 163 PL_BA8_LVDS67_L4P_DBC   BA8
        //B2B-2 156 PL_AW8_LVDS67_L3P       AW8
        //B2B-2 169 PL_AP10_LVDS67_L14P_GC  AP10
        //B2B-2 160 PL_BB6_LVDS67_L5N       BB6
        //B2B-2 181 PL_AW12_LVDS67_L7N_QBC  AW12 (was AR13)
        //B2B-2 164 PL_AV9_LVDS67_L10P_QBC  AV9
        //B2B-2 182 PL_AN12_LVDS67_L16P_QBC AN12 (was AW12)
        input [6:0] CIND_N,
        
        // DDR clocks (which we use for the IDELAYCTRL since it saves an MMCM)
        input   [1:0] DDR_CLK_P,
        input   [1:0] DDR_CLK_N,
        
        // B2B-1 40 PL_D6_LVDS93_L9N D6
        // B2B-1 42 PL_F6_LVDS93_L1N F6
        // B2B-1 44 PL_G6_LVDS93_L1P G6
        // B2B-1 56 PL_D7_LVDS93_L7N D7
        // B2B-1 58 PL_E7_LVDS93_L7P E7
        output [4:0] GPIO,
        // These are the other GPIOs not on the HSK header and not
        // currently externally assigned
        // B2B-1 70 PL_B6_LVDS94_L11P B6 
        // B2B-1 72 PL_B5_LVDS94_L11N B5
        output [1:0] LGPIO

    );
    
    localparam [15:0] FIRMWARE_VERSION = { VER_MAJOR, VER_MINOR, VER_REV };
    localparam [31:0] DATEVERSION = { FIRMWARE_DATE, FIRMWARE_VERSION };
    // address, data, id, user

    // Configuration information for the TURFIOs.
    localparam [31:0] TRAIN_VALUE = 32'hA55A6996;
    localparam [3:0] INV_CINTIO = 4'b1100;
    localparam [3:0] INV_COUT =   4'b1110;
    localparam [3:0] INV_TXCLK =  4'b1010;
    localparam [6:0] INV_CINA =   7'b0000010;
    localparam [6:0] INV_CINB =   7'b0001011;
    localparam [6:0] INV_CINC =   7'b1111111;
    localparam [6:0] INV_CIND =   7'b1100111;
    localparam [3:0] CIN_CLKTYPE = 4'b0011;
    localparam [3:0] COUT_CLKTYPE =4'b0110;    

    //////////////////////////////////////////////////////////
    //                     CLOCKS                           //
    //////////////////////////////////////////////////////////

    // 100 MHz clock from processing system
    wire ps_clk;
    // This is the DIRECT output of the IBUFDS
    wire sys_clk_ibuf;
    // After the deskew MMCM.
    wire sys_clk;
    // Global phase of sys_clk.
    wire sys_clk_phase;
    // Sync state. This is a direct analog to the SURF clock inputs
    // and if we time everything up correctly should be exactly synchronous.
    wire sys_clk_sync;
    // TURFIO MGT reference clock (125 MHz)
    wire mgt_refclk;
    // TURFIO MGT stream clock (312.5 MHz)
    wire mgt_clk;
    // *both* MGT reference clocks b/c IBERT is stupid
    wire [1:0] gbe_clk;
    // both after IBUFs
    wire [1:0] gbe_clk_ibuf;
    // GBE MGT reference clock (156.25 MHz = 10 GHz/64)
    wire gbe_refclk;
    // DDR clocks (300 MHz)
    wire [1:0] ddr_clk;

    
    // Generic 28-bit AXI space from PS
    `DEFINE_AXI4L_IF( axips_ , 28, 32 );
    // converted to the simple WISHBONE
    `DEFINE_WB_IF( wbps_ , 28, 32 );
    // module bus, for turf ID ctl
    `DEFINE_WB_IF( turf_idctl_ , 15, 32);
    // module bus, for aurora
    `DEFINE_WB_IF( aurora_ , 15, 32);
    // module bus, for control if
    `DEFINE_WB_IF( ctl_ , 15, 32);
    // module bus for hski2c
    `DEFINE_WB_IF( hski2c_ , 15, 32);

    // interface clock in bank 67
    wire if_clk67;
    // interface clk x2 in bank 67
    wire if_clk67_x2;
    // indicates that if_clk67_x2 is in 1st clk of 2-clk phase
    wire if_clk67_x2_phase;
    // interface clock in bank 68
    wire if_clk68;
    // interface clock x2 in bank 68
    wire if_clk68_x2;
    // indicates that if_clk68_x2 is in 1st clk of 2-clk phase
    wire if_clk68_x2_phase;
    // PLLs locked
    wire [1:0] pll_locked;
    
    // Sync command
    wire bitcommand_sync;
    // This is the req to generate a sync
    wire bitcmd_sync_req;
    // PPS command
    wire bitcommand_pps;
    // Command processor reset
    wire bitcommand_cmdproc_reset;
    // Bit command vector
    wire [11:0] bitcommand = { {9{1'b0}},
                                bitcommand_cmdproc_reset,   // 2
                                bitcommand_pps,             // 1
                                bitcommand_sync };          // 0
    // kill the unimplementeds
    assign bitcommand_pps = 1'b0;
    assign bitcommand_cmdproc_reset = 1'b0;
    
    // Command to feed to turfio ctl in bank 67
    wire [31:0] turfio_if_command67;
    // Command to feed to turfio ctl in bank 68
    wire [31:0] turfio_if_command68;
    
    // Command processor stream for bank 67
    `DEFINE_AXI4S_MIN_IF( cmdproc67_ , 8);
    wire [2:0] cmdproc67_tuser;
    wire cmdproc67_tlast;
    // kill it
    assign cmdproc67_tuser = 3'b000;
    assign cmdproc67_tdata = {8{1'b0}};
    assign cmdproc67_tvalid = 1'b0;
    assign cmdproc67_tlast = 1'b0;

    // Command processor stream for bank 68
    `DEFINE_AXI4S_MIN_IF( cmdproc68_ , 8);
    wire [2:0] cmdproc68_tuser;
    wire cmdproc68_tlast;
    // kill it
    assign cmdproc68_tuser = 3'b000;
    assign cmdproc68_tdata = {8{1'b0}};
    assign cmdproc68_tvalid = 1'b0;
    assign cmdproc68_tlast = 1'b0;
        
    
    // The TURF prototype has the P/Ns hooked up BACKWARDS relative to their
    // correct orientation. The correct orientation has N on the P input,
    // and P on the N input. HOWEVER: the schematic labelling has SYSCLK
    // *backwards* from all of the TURFIOs. So we *want* to invert SYSCLK.
    // To summarize:
    // PROTOTYPE: invert (because it is hooked up *non-inverted* and we want to invert)
    // non-prototype: do not invert (because it is hooked up *inverted* and that's what we want)
    //
    // You can tell this because the # of slips seen at TURFIO should be zero
    // since everything's synchronous.
    localparam INV_MMCM = (PROTOTYPE=="TRUE") ? "TRUE" : "FALSE";
    // wrap the PS system
    turf_ps_bd_wrapper u_ps(.ACLK(ps_clk),
                            `CONNECT_AXI4L_IF( m_axi_ps_ , axips_ ),
                            .CLK_IIC_scl_io(CLK_IIC_scl_io),
                            .CLK_IIC_sda_io(CLK_IIC_sda_io),
                            .HSK_UART_rxd(HSK_UART_rxd),
                            .HSK_UART_txd(HSK_UART_txd),
                            .PL_CLK(ps_clk),
                            .PS_RESET_N(1'b1));
    // wrapper for Aurora paths
    turfio_aurora_wrap u_aurora(.wb_clk_i(ps_clk),
                                .wb_rst_i(1'b0),
                                `CONNECT_WBS_IFM(wb_ , aurora_ ),
                                .MGTCLK_P(MGTCLK_P),
                                .MGTCLK_N(MGTCLK_N),
                                .MGTRX_P(MGTRX_P),
                                .MGTRX_N(MGTRX_N),
                                .MGTTX_P(MGTTX_P),
                                .MGTTX_N(MGTTX_N));
    // convert to simple wishbone
    axil2wb u_axil2wb( .clk_i( ps_clk ),
                       .rst_i( 1'b0 ),
                       `CONNECT_AXI4L_IF( s_axi_ , axips_ ),
                       `CONNECT_WBM_IFM( wb_ , wbps_ ) );
    // interconnect
    turf_intercon u_intercon( .clk_i(ps_clk),
                              .rst_i(1'b0),
                              `CONNECT_WBS_IFM(wb_ , wbps_),
                              `CONNECT_WBM_IFM(turf_id_ctrl_ , turf_idctl_ ),
                              `CONNECT_WBM_IFM(aurora_ , aurora_ ),
                              `CONNECT_WBM_IFM(ctl_ , ctl_ ),
                              `CONNECT_WBM_IFM(hski2c_ , hski2c_ ));

    // dummy up the unuseds
    //wbs_dummy #(.ADDRESS_WIDTH(15),.DATA_WIDTH(32)) u_ctlstub(`CONNECT_WBS_IFM(wb_ , ctl_ ));
    wbs_dummy #(.ADDRESS_WIDTH(15),.DATA_WIDTH(32)) u_hskstub(`CONNECT_WBS_IFM(wb_ , hski2c_ ));

    // number of clocks to monitor:
    // clk0: sysclk
    // clk1: gbe_sysclk
    // clk2: DDR clock 0
    // clk3: DDR clock 1
    // I guess add other stuff later or some'n
    turf_id_ctrl #(.IDENT(IDENT),
                   .DATEVERSION(DATEVERSION),
                   .NUM_CLK_MON(4))
        u_idctrl( .wb_clk_i(ps_clk),
                  .wb_rst_i(1'b0),
                  `CONNECT_WBS_IFM(wb_ , turf_idctl_ ),
                  .bitcmd_sync_o(bitcmd_sync_req),
                  .clk_mon_i( { ddr_clk[1], ddr_clk[0], gbe_sysclk, sys_clk } ));

    // and sync generator. This times up the bitcmd sync to be req'd correctly.
    sysclk_sync_req u_syncreq(.sysclk_i(sys_clk),
                              .sysclk_phase_i(sys_clk_phase),
                              .sysclk_sync_i(sys_clk_sync),
                              .sync_req_i(bitcmd_sync_req),
                              .sync_bitcommand_o(bitcommand_sync));

    // this needs to get pushed into the 10GbE core                  
    IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00))
        u_gclk_ibuf(.I(GBE_CLK_P),.IB(GBE_CLK_N),.CEB(1'b0),.O(gbe_clk[0]), .ODIV2(gbe_clk_ibuf[0]));
    // The example design is sooo not helpful here.
    BUFG_GT u_gth_internal(.I(gbe_clk_ibuf[0]),
                           .O(gbe_sysclk),
                           .CE(1'b1),
                           .CEMASK(1'b0),
                           .CLR(1'b0),
                           .CLRMASK(1'b0),
                           .DIV(3'b000));

    // this needs to get pushed into the DDR core. Might go through
    // an MMCM. Not sure.
    IBUFDS u_ddrclk0_ibuf(.I(DDR_CLK_P[0]),.IB(DDR_CLK_N[0]),.O(ddr_clk[0]));
    IBUFDS u_ddrclk1_ibuf(.I(DDR_CLK_P[1]),.IB(DDR_CLK_N[1]),.O(ddr_clk[1]));

    system_clock_v2 #(.INVERT_MMCM(INV_MMCM))
        u_sysclk(.SYS_CLK_P(SYSCLK_P),
                 .SYS_CLK_N(SYSCLK_N),
                 .reset(1'b0),
                 .sysclk_o(sys_clk),
                 .sysclk_ibuf_o(sys_clk_ibuf),
                 .sysclk_phase_o(sys_clk_phase),
                 .sysclk_sync_o(sys_clk_sync));
    turfio_if #( .INV_SYSCLK(INV_MMCM),
                 .TRAIN_VALUE(TRAIN_VALUE),
                 .INV_CINTIO(INV_CINTIO),
                 .INV_COUT(INV_COUT),
                 .INV_CINA(INV_CINA),
                 .INV_CINB(INV_CINB),
                 .INV_CINC(INV_CINC),
                 .INV_CIND(INV_CIND),
                 .INV_TXCLK(INV_TXCLK),
                 .CIN_CLKTYPE(CIN_CLKTYPE),
                 .COUT_CLKTYPE(COUT_CLKTYPE))
        u_tioctl( .clk_i(ps_clk),
                  .rst_i(1'b0),
                  `CONNECT_WBS_IFM(wb_ , ctl_ ),
                  .clk300_i( ddr_clk[0] ),
                  .ifclk67_o( if_clk67 ),
                  .ifclk68_o( if_clk68 ),

                  .sysclk_ibuf_i(sys_clk_ibuf),
                  .sysclk_phase_i(sys_clk_phase),
                  .cout_command67_i( turfio_if_command67 ),
                  .cout_command68_i( turfio_if_command68 ),
                  .cina_command_o(),
                  .cinb_command_o(),
                  .cinc_command_o(),
                  .cind_command_o(),
                  .cina_valid_o(),
                  .cinb_valid_o(),
                  .cinc_valid_o(),
                  .cind_valid_o(),
                  .CINTIO_P(CINTIO_P),
                  .CINTIO_N(CINTIO_N),
                  .COUT_P(COUT_P),
                  .COUT_N(COUT_N),
                  .TXCLK_P(TXCLK_P),
                  .TXCLK_N(TXCLK_N),
                  .CINA_P(CINA_P),
                  .CINA_N(CINA_N),
                  .CINB_P(CINB_P),
                  .CINB_N(CINB_N),
                  .CINC_P(CINC_P),
                  .CINC_N(CINC_N),
                  .CIND_P(CIND_P),
                  .CIND_N(CIND_N));

    // Command encoder for bank67.
    pueo_command_encoder u_cmd_encode67( .sysclk_i(if_clk67),
                                         .sysclk_phase_i(sys_clk_phase),
                                         .command_o(turfio_if_command67),
                                         .bitcommand_i(bitcommand),
                                         .bitcommand_ack(),
                                         `CONNECT_AXI4S_MIN_IF( cmdproc_ , cmdproc67_ ),
                                         .cmdproc_tuser(cmdproc67_tuser),
                                         .cmdproc_tlast(cmdproc67_tlast),
                                         .trig_tdata( {16{1'b0}} ),
                                         .trig_tvalid( 1'b0 ),
                                         .trig_tready() );
    // Command encoder for bank68.
    pueo_command_encoder u_cmd_encode68( .sysclk_i(if_clk68),
                                         .sysclk_phase_i(sys_clk_phase),
                                         .command_o(turfio_if_command68),
                                         .bitcommand_i(bitcommand),
                                         .bitcommand_ack(),
                                         `CONNECT_AXI4S_MIN_IF( cmdproc_ , cmdproc68_ ),
                                         .cmdproc_tuser(cmdproc68_tuser),
                                         .cmdproc_tlast(cmdproc68_tlast),
                                         .trig_tdata( {16{1'b0}} ),
                                         .trig_tvalid( 1'b0 ),
                                         .trig_tready() );

//    system_clock #(.INVERT_MMCM(INV_MMCM)) 
//        u_sysclk(.SYS_CLK_P(SYSCLK_P),
//                 .SYS_CLK_N(SYSCLK_N),
//                 .reset(1'b0),
//                 .sysclk_o(sys_clk),
//                 .ifclk67_o(if_clk67),
//                 .ifclk67_x2_o(if_clk67_x2),
//                 .ifclk67_x2_phase_o(if_clk67_x2_phase),
//                 .ifclk68_o(if_clk68),
//                 .ifclk68_x2_o(if_clk68_x2),
//                 .ifclk68_x2_phase_o(if_clk68_x2_phase),
//                 .locked(pll_locked));
//    turfio_prototest #(.INV_RXCLK(0),
//                       .INV_TXCLK(0),
//                       .INV_CINTIO(0),
//                       .INV_COUT(0)) u_proto(.RXCLK_P(RXCLK_P[0]),
//                             .RXCLK_N(RXCLK_N[0]),
//                             .TXCLK_P(TXCLK_P[0]),
//                             .TXCLK_N(TXCLK_N[0]),
//                             .CINTIO_P(CINTIO_P[0]),
//                             .CINTIO_N(CINTIO_N[0]),
//                             .COUT_P(COUT_P[0]),
//                             .COUT_N(COUT_N[0]),
//                             .sys_clk(sys_clk),
//                             .if_clk67(if_clk67),
//                             .if_clk67_x2(if_clk67_x2),
//                             .if_clk67_x2_phase(if_clk67_x2_phase),
//                             .if_clk68(if_clk68),
//                             .if_clk68_x2(if_clk68_x2),
//                             .if_clk68_x2_phase(if_clk68_x2_phase),
//                             .if_clk_x2_locked(&pll_locked));

    sync_debug u_syncdebug(.sysclk_i(sys_clk),
                           .sysclk_sync_i(sys_clk_sync),
                           .LGPIO(LGPIO));    

//    ///// UNUSED CRAP
//    OBUFDS u_obuf(.I(1'b0),.O(COUT_N[1]),.OB(COUT_P[1]));            
    assign GPIO = {5{1'b1}};
endmodule
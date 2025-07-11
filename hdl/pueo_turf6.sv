`timescale 1ns / 1ps
/////////////////////////////////////////////
// NEW TURF FIRMWARE: Now using PetaLinux  //
// and a bunch of stock cores for serial   //
// crap.                                   //
/////////////////////////////////////////////
`define USE_GBE
`define USE_DDR_0

`include "interfaces.vh"
`include "mem_axi.vh"
module pueo_turf6 #(parameter IDENT="TURF",
                    parameter REVISION="A",
                    parameter [3:0] VER_MAJOR=4'd0,
                    parameter [3:0] VER_MINOR=4'd7,
                    parameter [7:0] VER_REV=8'd28,
                    parameter [15:0] FIRMWARE_DATE = {16{1'b0}})                    
                    (

        // SLOW PERIPHERALS
        output TTXA,
        input TRXA,
        inout TRESETB_A,        // used to be TGPIO1A pin 124 D2

        output TTXB,
        input TRXB,
        inout TRESETB_B,        // used to be TGPIO1B pin 74 B3
        
        output TTXC,
        input TRXC,
        inout TRESETB_C,        // used to be TGPIO1C pin 88 E2
        
        output TTXD,
        input TRXD,
        inout TRESETB_D,        // used to be TGPIO1D pin 92 E1
        
        output GPS_TX,
        input GPS_RX,
        input [1:0] GPS_TIMEPULSE,
        output [1:0] GPS_EXTINT,
    
        // CLK_SCL/CLK_SDA are the "3V3" guys        
        output CLK_SCL,
        inout CLK_SDA,
        
        output CAL_SCL,
        inout CAL_SDA,
        // these are the HSK gpios
        inout [2:0] GPIO,
        input [1:0] TIN,
        output TOUT,
        
        // these are the silly PL GPIOs
        // B5 = 0 B6 = 1
        output [1:0] PLGPIO,
        
        output UART_SCLK,
        output UART_MOSI,
        input UART_MISO,
        output UART_CS_B,
        input UART_IRQ_B,
        // CLOCKS
        input [1:0] DDR_CLK_P,
        input [1:0] DDR_CLK_N,
        input GBE_CLK_P,
        input GBE_CLK_N,
        input SYSCLK_P,
        input SYSCLK_N,
        input MGTCLK_P,
        input MGTCLK_N,
        // MGTs
        input [3:0] MGTRX_P,
        input [3:0] MGTRX_N,
        output [3:0] MGTTX_P,
        output [3:0] MGTTX_N,
        // GBE
`ifdef USE_GBE
        input [1:0] GBE_RX_P,
        input [1:0] GBE_RX_N,
        output [1:0] GBE_TX_P,
        output [1:0] GBE_TX_N,
`endif
`ifdef USE_DDR_0        
        output [0:0]    C0_DDR4_ck_t,
        output [0:0]    C0_DDR4_ck_c,
        inout [7:0]     C0_DDR4_dqs_t,
        inout [7:0]     C0_DDR4_dqs_c,
        inout [7:0]     C0_DDR4_dm_dbi_n,
        inout [63:0]    C0_DDR4_dq,
        output [1:0]    C0_DDR4_ba,
        output [0:0]    C0_DDR4_cke,
        output          C0_DDR4_act_n,
        output [0:0]    C0_DDR4_odt,
        output [16:0]   C0_DDR4_adr,
        output          C0_DDR4_reset_n,
        output [0:0]    C0_DDR4_bg,
        output [0:0]    C0_DDR4_cs_n,
`endif
`ifdef USE_DDR_1
        output [0:0]    C1_DDR4_ck_t,
        output [0:0]    C1_DDR4_ck_c,
        inout [7:0]     C1_DDR4_dqs_t,
        inout [7:0]     C1_DDR4_dqs_c,
        inout [7:0]     C1_DDR4_dm_n,
        inout [63:0]    C1_DDR4_dq,
        output [1:0]    C1_DDR4_ba,
        output [0:0]    C1_DDR4_cke,
        output          C1_DDR4_actn,
        output [0:0]    C1_DDR4_odt,
        output [16:0]   C1_DDR4_adr,
        output          C1_DDR4_reset_n,
        output [0:0]    C1_DDR4_bg,
        output [0:0]    C1_DDR4_cs_n,
`endif
        // TURFIO INTERFACES
        output [3:0] TXCLK_P,
        output [3:0] TXCLK_N,
        input [3:0] CINTIO_P,
        input [3:0] CINTIO_N,
        input [6:0] CINA_P,
        input [6:0] CINA_N,
        input [6:0] CINB_P,
        input [6:0] CINB_N,
        input [6:0] CINC_P,
        input [6:0] CINC_N,
        input [6:0] CIND_P,
        input [6:0] CIND_N,
        output [3:0] COUT_P,
        output [3:0] COUT_N,
        // The SPAREs are too awkward to use, and we hooked up
        // the RXCLKs correctly. So use 'em.
        input [3:0] RXCLK_GPIO_P,   // 0,1,2,3 116, 110, 172, 178: G17 E15 AT10 AT12 
        input [3:0] RXCLK_GPIO_N    // 0,1,2,3 118, 112, 170, 176: F17 D14 AT11 AT13
                
    );
    
    localparam PROTOTYPE = (REVISION == "A") ? "TRUE" : "FALSE";
    
    localparam UART_DEBUG = "TRUE";
    localparam [15:0] FIRMWARE_VERSION = { VER_MAJOR, VER_MINOR, VER_REV };
    localparam [31:0] DATEVERSION = { (REVISION=="B" ? 1'b1 : 1'b0), FIRMWARE_DATE[14:0], FIRMWARE_VERSION };

    // Configuration information for the TURFIOs.
    // We split this up into two INV parameters because OUR names all match
    // the TURF revC schematic. But the bits that pass through the expander
    // board might have an additional inversion.

    // There are also random inversions that were determined
    // empirically: we fold this into the XB inversion, but I'm going to document
    // it separately.
    // CINA: bit 1
    // CINB: bit 0 bit 1 bit 3
    // CINC: none
    // CIND: bit 3 bit 4
    localparam [31:0] TRAIN_VALUE = 32'hA55A6996;
    localparam [3:0] INV_CINTIO =       4'b1100;
    localparam [3:0] INV_CINTIO_XB =    4'b1100;        // correct

    localparam [3:0] INV_COUT =         4'b1110;
    localparam [3:0] INV_COUT_XB =      4'b1100;        // correct
    
    localparam [3:0] INV_TXCLK =        4'b1010;      
    localparam [3:0] INV_TXCLK_XB =     4'b1100;        // correct
    
    localparam [6:0] INV_CINA =     7'b0000010;
    localparam [6:0] INV_CINA_XB =  7'b0000000;         // correct bc no XB

    localparam [6:0] INV_CINB =     7'b0001011;
    localparam [6:0] INV_CINB_XB =  7'b0000000;         // correct bc no XB
    
    localparam [6:0] INV_CINC =     7'b1111111;
    localparam [6:0] INV_CINC_XB =  7'b1111111;     // correct

    localparam [6:0] INV_CIND =     7'b1100111;
    localparam [6:0] INV_CIND_XB =  7'b1111111;     // correct    
        
    localparam [3:0] CIN_CLKTYPE = 4'b0011;
    localparam [3:0] COUT_CLKTYPE =4'b0110;
        
    localparam [3:0] INV_RXCLK_GPIO = 4'b1100;
    localparam [3:0] INV_RXCLK_GPIO_XB = 4'b0000;       
        
    wire emio_scl;
    wire emio_sda_i;
    wire emio_sda_t;
    
    // the TOP 4 BITS of the EMIO are the resets to the TURFIOs
    // the NEXT 4 BITS are GPSy: TP1/TP0 EXTINT1/EXTINT0
    // the NEXT 4 are reserved
    // and the BOTTOM 4 are reserved, hsk_complete (2), hsk_irq (1), and UART_IRQ_B (0).
    
    wire [15:0] emio_gpio_t;
    wire [15:0] emio_gpio_i;
    wire [15:0] emio_gpio_o;    
    
    wire hsk_irq;    
    wire hsk_complete;
    wire pps_pulse;
    wire photoshutter;
    
    assign emio_gpio_i[11:0] = { GPS_TIMEPULSE[1], pps_pulse, {7{1'b0}}, hsk_complete, hsk_irq, UART_IRQ_B };
    assign GPS_EXTINT[0] = photoshutter;
    assign GPS_EXTINT[1] = !emio_gpio_t[9] && emio_gpio_o[9];
    // TURFIO resets
    IOBUF u_tioa_resetb(.IO(TRESETB_A),.I(emio_gpio_o[12]),
                                       .O(emio_gpio_i[12]),
                                       .T(emio_gpio_t[12]));
    IOBUF u_tiob_resetb(.IO(TRESETB_B),.I(emio_gpio_o[13]),
                                       .O(emio_gpio_i[13]),
                                       .T(emio_gpio_t[13]));
    IOBUF u_tiob_resetc(.IO(TRESETB_C),.I(emio_gpio_o[14]),
                                       .O(emio_gpio_i[14]),
                                       .T(emio_gpio_t[14]));
    IOBUF u_tiob_resetd(.IO(TRESETB_D),.I(emio_gpio_o[15]),
                                       .O(emio_gpio_i[15]),
                                       .T(emio_gpio_t[15]));
    // TURFIO GPIOs forwarded through RXCLK fakery
    // I should use the parameters here
    // I so don't care atm
    wire [3:0] tio_gpio;
    wire [3:0] tio_gpio_cmpl;
    IBUFDS_DIFF_OUT u_tioa_gpio(.I(RXCLK_GPIO_P[0]),.IB(RXCLK_GPIO_N[0]),.O(tio_gpio[0]),.OB(tio_gpio_cmpl[0]));
    IBUFDS_DIFF_OUT u_tiob_gpio(.I(RXCLK_GPIO_P[1]),.IB(RXCLK_GPIO_N[1]),.O(tio_gpio[1]),.OB(tio_gpio_cmpl[1]));
    IBUFDS_DIFF_OUT u_tioc_gpio(.I(RXCLK_GPIO_N[2]),.IB(RXCLK_GPIO_P[2]),.O(tio_gpio_cmpl[2]),.OB(tio_gpio[2]));
    IBUFDS_DIFF_OUT u_tiod_gpio(.I(RXCLK_GPIO_N[3]),.IB(RXCLK_GPIO_P[3]),.O(tio_gpio_cmpl[3]),.OB(tio_gpio[3]));   
                                                                              
    wire [5:0] gp_in = { tio_gpio, TIN };
    
    //////////////////////////////////////////////
    //              REGISTER SPACES             //
    //////////////////////////////////////////////
    
    // PS AXI side interface. Gets bridged to WISHBONE via axil2wb.
    `DEFINE_AXI4L_IF( axi_ps_ , 28, 32 );
    // PS WISHBONE side.
    `DEFINE_WB_IF( wb_ps_ , 28, 32 );
    // Ethernet WISHBONE side
    `DEFINE_WB_IF( wb_eth_ , 28, 32 );
    // TURF ID ctl
    `DEFINE_WB_IF( turf_idctl_ , 14, 32);
    // GBE space
    `DEFINE_WB_IF( gbe_ , 14, 32);
    // Aurora space
    `DEFINE_WB_IF( aurora_ , 15, 32);
    // Control (CIN/COUT stuff) space
    `DEFINE_WB_IF( ctl_ , 15, 32);
    // This USED to be called hski2c_, it's now evctl_.
    `DEFINE_WB_IF( evctl_ , 13, 32);
    // now split off: time control
    `DEFINE_WB_IF( time_ , 13, 32);
    // Trigger control space. Also contains the sync/runctl stuff
    `DEFINE_WB_IF( trig_ , 14, 32);
    // Crate space, accessed through the bridge.
    `DEFINE_WB_IF( crate_ , 27, 32);    

    //////////////////////////////////////////////
    //              STREAMS                     //
    //////////////////////////////////////////////

    // Aurora command processor path
    `DEFINE_AXI4S_MIN_IF( aurora_cmd_ , 32 );
    wire [1:0] aurora_cmd_tdest;
    wire aurora_cmd_tlast;
    // Response path. Don't bother with tlast at the moment.
    `DEFINE_AXI4S_MIN_IF( aurora_resp_ , 32 );
    wire [1:0] aurora_resp_tuser;
    
    //////////////////////////////////////////////
    //              CLOCKS                      //
    //////////////////////////////////////////////
    // Clocking Is Complicated due to the bank  //
    // restrictions.                            //
    //////////////////////////////////////////////
    
    // 100 MHz clock from processing system
    wire ps_clk;
    // This is the DIRECT output of the IBUFDS
    wire sys_clk_ibuf;
    // After the deskew MMCM.
    wire sys_clk;
    // Global phase of sys_clk.
    wire sys_clk_phase;
    // The X2 clock (250 MHz).
    wire sys_clk_x2;
    // The X2 clock's CE (to clean capture from sys_clk)
    wire sys_clk_x2_ce;
    
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
    wire gbe_sysclk;
    
    // actual sfp recovered rxclk
    wire sfp_rxclk;
    // actual sfp generated txclk
    wire sfp_txclk;
        
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
    
    // DDR clocks (300 MHz)
    wire [1:0] ddr_clk;

    // Aurora *reference* clock (125 MHz)
    wire aurora_clk;
    
    // Aurora *user* clock (156.25 MHz)
    wire aclk;

    // general-purpose output usage select and enable
    wire [2:0] gpo_select;
    wire       gpo_en;

    wire gpo_sync_ce;
    wire gpo_sync_d;
    wire gpo_run_ce;
    wire gpo_run_d;
    wire gpo_trig_ce;
    wire gpo_trig_d;
    wire gpo_pps_ce;
    wire gpo_pps_d;

    IBUFDS u_ddrclk1_ibuf(.I(DDR_CLK_P[1]),.IB(DDR_CLK_N[1]),.O(ddr_clk[1]));
    
    localparam INV_MMCM = (PROTOTYPE=="TRUE") ? "TRUE" : "FALSE";
    system_clock_v2 #(.INVERT_MMCM(INV_MMCM))
        u_sysclk(.SYS_CLK_P(SYSCLK_P),
                 .SYS_CLK_N(SYSCLK_N),
                 .reset(1'b0),
                 .sysclk_o(sys_clk),
                 .sysclk_x2_o(sys_clk_x2),
                 .sysclk_x2_ce_o(sys_clk_x2_ce),
                 .sysclk_ibuf_o(sys_clk_ibuf),
                 .sysclk_phase_o(sys_clk_phase),
                 .sysclk_sync_o(sys_clk_sync),
                 .gpo_sync_ce_o(gpo_sync_ce),
                 .gpo_sync_d_o(gpo_sync_d));
    assign PLGPIO[1] = 1'b0;
    assign PLGPIO[0] = 1'b1;
    // NOTE: we might add in the optional TURFIO I2C controls
    // at some point. If we do that, we need to disconnect the
    // UART. We can only do one of those at a time because their
    // addresses will clash.
    // Our local addresses are only 0x62/0x6A and whatever's
    // on the cal board (will need to check that to not clash!!)
    // on the turfio we pick up 48/10/40/44/11/41/45/46 and 70.
    // that's a busy I2C bus!
    i2c_merger u_i2c_merger(.clk(ps_clk),
                            .scl_in(emio_scl),
                            .sda_in_o(emio_sda_i),
                            .sda_in_t(emio_sda_t),
                            .scl0_out(CLK_SCL),
                            .sda0_out(CLK_SDA),
                            .scl1_out(CAL_SCL),
                            .sda1_out(CAL_SDA));    
    
    turf_gpo_mux #(.SYSCLKTYPE("SYSCLK"))
        u_mux(.sysclk_i(sys_clk),
              .gpo_en_i(gpo_en),
              .gpo_select_i(gpo_select),
              
              .gpo_sync_ce_i(gpo_sync_ce),
              .gpo_sync_d_i(gpo_sync_d),
              
              .gpo_run_ce_i(gpo_run_ce),
              .gpo_run_d_i(gpo_run_d),
              
              .gpo_trig_ce_i(gpo_trig_ce),
              .gpo_trig_d_i(gpo_trig_d),
              
              .gpo_pps_ce_i(gpo_pps_ce),
              .gpo_pps_d_i(gpo_pps_d),
              
              .GPO(TOUT));                    
    
    wire hsk_sclk;
    wire hsk_mosi;
    wire hsk_miso;
    wire [1:0] hsk_cs_b;
    
    zynq_bd_wrapper u_zynq( .EMIO_tri_t(emio_gpio_t),
                            .EMIO_tri_i(emio_gpio_i),
                            .EMIO_tri_o(emio_gpio_o),
                            
                            .IIC_scl_o(emio_scl),
                            .IIC_sda_i(emio_sda_i),
                            .IIC_sda_t(emio_sda_t),
                            
                            .spi0_sclk(UART_SCLK),
                            .spi0_mosi(UART_MOSI),
                            .spi0_miso(UART_MISO),
                            .spi0_cs_b(UART_CS_B),
    
                            .spi1_sclk(hsk_sclk),
                            .spi1_mosi(hsk_mosi),
                            .spi1_miso(hsk_miso),
                            .spi1_cs_b(hsk_cs_b),
    
                            .GPS_rxd(GPS_RX),
                            .GPS_txd(GPS_TX),
                            
                            .TFIO_A_rxd(TRXA),
                            .TFIO_A_txd(TTXA),
                            
                            .TFIO_B_rxd(TRXB),
                            .TFIO_B_txd(TTXB),
                            
                            .TFIO_C_rxd(TRXC),
                            .TFIO_C_txd(TTXC),
                            
                            .TFIO_D_rxd(TRXD),
                            .TFIO_D_txd(TTXD),
                            
                            `CONNECT_AXI4L_IF( m_axi_ps_ , axi_ps_ ),
                            
                            .pl_clk0(ps_clk));

    /////////////////////////////////////////////////////
    //         REGISTER INTERCONNECT                   //
    /////////////////////////////////////////////////////
    
    // bridge AXI4L -> WB
    axil2wb #(.ADDR_WIDTH(28),
              .DEBUG("FALSE")) u_axil2wb(.clk_i(ps_clk),
                                         .rst_i(1'b0),
                                         `CONNECT_AXI4L_IF( s_axi_ , axi_ps_ ),
                                         `CONNECT_WBM_IFM( wb_ , wb_ps_ ));
    
    // interconnect
    turf_intercon #(.DEBUG("TRUE"))
                  u_intercon( .clk_i(ps_clk),
                              .rst_i(1'b0),
                              `CONNECT_WBS_IFM(wbps_ , wb_ps_),
                              `CONNECT_WBS_IFM(wbeth_, wb_eth_),
                              `CONNECT_WBM_IFM(turf_id_ctrl_ , turf_idctl_ ),
                              `CONNECT_WBM_IFM(gbe_ , gbe_ ),
                              `CONNECT_WBM_IFM(aurora_ , aurora_ ),
                              `CONNECT_WBM_IFM(ctl_ , ctl_ ),
                              `CONNECT_WBM_IFM(evctl_ , evctl_ ),
                              `CONNECT_WBM_IFM(time_ , time_ ),
                              `CONNECT_WBM_IFM(trig_ , trig_ ),
                              `CONNECT_WBM_IFM(crate_ , crate_ ));

    /////////////////////////////////////////////////////
    //         REGISTER MODULES                        //
    /////////////////////////////////////////////////////

    // ID and Control
    // register bridge type selection
    wire [7:0] bridge_type;
    // a bridge timeout occurred
    wire [3:0] bridge_timeout;
    // an invalid bridge access occured
    wire [3:0] bridge_invalid_access;
    // bridge valid indicators
    wire [15:0] bridge_valid;

    // NEED TO DO SOMETHING TO FIX THESE
    wire bitcmd_sync_req;

    turf_id_ctrl #(.IDENT(IDENT),
                   .DATEVERSION(DATEVERSION),
                   .NUM_CLK_MON(8))
        u_idctrl( .wb_clk_i(ps_clk),
                  .wb_rst_i(1'b0),
                  `CONNECT_WBS_IFM(wb_ , turf_idctl_ ),
                  .bitcmd_sync_o(bitcmd_sync_req),
                  
                  .gpo_en_o(gpo_en),
                  .gpo_select_o(gpo_select),

                  .bridge_type_o(bridge_type),
                  .bridge_timeout_i(bridge_timeout),
                  .bridge_invalid_i(bridge_invalid_access),

                  .clk_mon_i( { aclk, sfp_txclk, sfp_rxclk, aurora_clk, ddr_clk[1], ddr_clk[0], gbe_sysclk, sys_clk } ));

    // Aurora
    // indicates auroras are up
    wire [3:0] aurora_up;

    // wrapper for Aurora paths
    `DEFINE_AXI4S_MIN_IF( aur0_, 32 );
    wire aur0_tlast;    
    `DEFINE_AXI4S_MIN_IF( aur1_, 32 );
    wire aur1_tlast;
    `DEFINE_AXI4S_MIN_IF( aur2_, 32 );    
    wire aur2_tlast;
    `DEFINE_AXI4S_MIN_IF( aur3_, 32 );    
    wire aur3_tlast;
    turfio_aurora_wrap #(.WBCLKTYPE("PSCLK"),
                         .ACLKTYPE("USERCLK"))
                       u_aurora(.wb_clk_i(ps_clk),
                                .wb_rst_i(1'b0),
                                `CONNECT_WBS_IFM(wb_ , aurora_ ),
                                `CONNECT_AXI4S_MIN_IF( s_cmd_ , aurora_cmd_ ),
                                .s_cmd_tdest(aurora_cmd_tdest),
                                .s_cmd_tlast(aurora_cmd_tlast),
                                `CONNECT_AXI4S_MIN_IF( m_resp_ , aurora_resp_ ),
                                .m_resp_tuser(aurora_resp_tuser),                                
                                .aurora_up_o(aurora_up),
                                .aurora_clk_o(aurora_clk),
                                
                                .aclk_o( aclk ),
                                .m_aurora_tdata( { aur3_tdata, aur2_tdata, aur1_tdata, aur0_tdata } ),
                                .m_aurora_tvalid({ aur3_tvalid, aur2_tvalid, aur1_tvalid, aur0_tvalid } ),
                                .m_aurora_tready({ aur3_tready, aur2_tready, aur1_tready, aur0_tready } ),
                                .m_aurora_tlast( { aur3_tlast, aur2_tlast, aur1_tlast, aur0_tlast } ),
                                
                                .MGTCLK_P(MGTCLK_P),
                                .MGTCLK_N(MGTCLK_N),
                                .MGTRX_P(MGTRX_P),
                                .MGTRX_N(MGTRX_N),
                                .MGTTX_P(MGTTX_P),
                                .MGTTX_N(MGTTX_N));
    // and the bridge from crate to Aurora
    // Crate register bridge. 

    // Hook up valids. Top 2 bits aren't implemented yet, last is always valid (BRIDGE_NONE)
    assign bridge_valid = { 1'b0, 1'b0, aurora_up[3], 1'b1,
                            1'b0, 1'b0, aurora_up[2], 1'b1,
                            1'b0, 1'b0, aurora_up[1], 1'b1,
                            1'b0, 1'b0, aurora_up[0], 1'b1 };                            
    // The bridge.
    turfio_register_bridge 
        u_bridge( .wb_clk_i(ps_clk),
                  .wb_rst_i(1'b0),
                  .timeout_reached_o(bridge_timeout),
                  .invalid_o(bridge_invalid_access),
                  .bridge_type_i(bridge_type),
                  .bridge_valid_i(bridge_valid),
                  `CONNECT_WBS_IFM( bridge_ , crate_ ),
                  `CONNECT_AXI4S_MIN_IF( m_cmd_ , aurora_cmd_ ),
                  .m_cmd_tdest(aurora_cmd_tdest),
                  .m_cmd_tlast(aurora_cmd_tlast),
                  `CONNECT_AXI4S_MIN_IF( s_resp_ , aurora_resp_ ),
                  .s_resp_tuser( aurora_resp_tuser ));                                    

    // turfio path
    wire [31:0] turfio_if_command67;
    wire [31:0] turfio_if_command68;
    // triggers
    wire [16*8-1:0] turfioa_trigger;
    wire [7:0] turfioa_valid;
    wire [16*8-1:0] turfiob_trigger;
    wire [7:0] turfiob_valid;
    wire [16*8-1:0] turfioc_trigger;
    wire [7:0] turfioc_valid;
    wire [16*8-1:0] turfiod_trigger;
    wire [7:0] turfiod_valid;
    
    turfio_if #( .INV_SYSCLK(INV_MMCM),
                 .TRAIN_VALUE(TRAIN_VALUE),
                 .INV_CINTIO(INV_CINTIO),
                 .INV_CINTIO_XB(INV_CINTIO_XB),
                 
                 .INV_COUT(INV_COUT),
                 .INV_COUT_XB(INV_COUT_XB),
                 
                 .INV_CINA(INV_CINA),
                 .INV_CINA_XB(INV_CINA_XB),
                 
                 .INV_CINB(INV_CINB),
                 .INV_CINB_XB(INV_CINB_XB),
                 
                 .INV_CINC(INV_CINC),
                 .INV_CINC_XB(INV_CINC_XB),
                 
                 .INV_CIND(INV_CIND),
                 .INV_CIND_XB(INV_CIND_XB),
                 
                 .INV_TXCLK(INV_TXCLK),
                 .INV_TXCLK_XB(INV_TXCLK_XB),
                 
                 .CLK300_CLKTYPE("DDRCLK0"),
                 .WBCLKTYPE("PSCLK"),
                 .CIN_CLKTYPE(CIN_CLKTYPE),
                 .COUT_CLKTYPE(COUT_CLKTYPE))
        u_tioctl( .clk_i(ps_clk),
                  .rst_i(1'b0),
                  `CONNECT_WBS_IFM(wb_ , ctl_ ),
                  .clk300_i( ddr_clk[0] ),
                  .ifclk67_o( if_clk67 ),
                  .ifclk68_o( if_clk68 ),
                  .sysclk_i(sys_clk),
                  .sysclk_ibuf_i(sys_clk_ibuf),
                  .sysclk_phase_i(sys_clk_phase),
                  .cout_command67_i( turfio_if_command67 ),
                  .cout_command68_i( turfio_if_command68 ),
                  .cina_trigger_o(turfioa_trigger),
                  .cina_valid_o(turfioa_valid),
                  .cinb_trigger_o(turfiob_trigger),
                  .cinb_valid_o(turfiob_valid),
                  .cinc_trigger_o(turfioc_trigger),
                  .cinc_valid_o(turfioc_valid),
                  .cind_trigger_o(turfiod_trigger),
                  .cind_valid_o(turfiod_valid),
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

    // ETHERNET STREAMS AND CONTROLS
    `DEFINE_AXI4S_MIN_IF( ack_ , 48);
    `DEFINE_AXI4S_MIN_IF( nack_ , 48);
    wire event_open;
    `DEFINE_AXI4S_MIN_IF( ev_ctrl_ , 32);
    `DEFINE_AXI4S_IF( ev_data_ , 64);
    // kill the streams for now
//    assign ack_tready = 1'b1;
//    assign nack_tready = 1'b1;
//    assign ev_ctrl_tvalid = 1'b0;
//    assign ev_ctrl_tdata = {32{1'b0}};
//    assign ev_data_tvalid = 1'b0;
//    assign ev_data_tdata = {64{1'b0}};

    // WHEEEEE
    // The UDP wrap contains hookups for the full SFP, but
    // obviously we don't have any of them. All we hook up are
    // the TXP/TXNs and RXP/RXNs plus refclks.
    // We also grab the LEDs for funsies and push them to EMIOs.
    wire [3:0] sfp_led;
    wire [31:0] cur_sec;
    wire pps;
    
    wire emergency_stop;
    wire event_stopped;

    turf_udp_wrap #(.WBCLKTYPE("PSCLK"),
                    .ETHCLKTYPE("GBECLK"))
          u_ethernet(
            .sfp_led(sfp_led),
            .sfp_tx_p( GBE_TX_P ),
            .sfp_tx_n( GBE_TX_N ),
            .sfp_rx_p( GBE_RX_P ),
            .sfp_rx_n( GBE_RX_N ),
            .sfp_refclk_p(GBE_CLK_P),
            .sfp_refclk_n(GBE_CLK_N),
            .sfp_rxclk_o(sfp_rxclk),
            .sfp_txclk_o(sfp_txclk),
            .aclk(gbe_sysclk),

            .hsk_sclk_i(hsk_sclk),
            .hsk_mosi_i(hsk_mosi),
            .hsk_miso_o(hsk_miso),
            .hsk_cs_b_i(hsk_cs_b),
            .hsk_irq_o(hsk_irq),
            .hsk_complete_o(hsk_complete),
            
            `CONNECT_AXI4S_MIN_IF( m_ack_ , ack_ ),
            `CONNECT_AXI4S_MIN_IF( m_nack_ , nack_ ),
            .event_open_o(event_open),
            .emergency_stop_o(emergency_stop),
            .stopped_i(event_stopped),
            
            `CONNECT_AXI4S_MIN_IF( s_ev_ctrl_ , ev_ctrl_ ),
            `CONNECT_AXI4S_IF( s_ev_data_ , ev_data_ ),
            
            .cur_sec_i(cur_sec),
            .pps_i(pps),
            .sysclk_i(sys_clk),
            
            .wb_clk_i(ps_clk),
            `CONNECT_WBS_IFM( gtp_ , gbe_ ),
            `CONNECT_WBM_IFM( wb_ , wb_eth_ )          
          );
    
    wire runrst;
    wire pps_dbg;
    wire [31:0] cur_time;
    wire [31:0] last_pps;
    wire [31:0] llast_pps;
    wire [31:0] cur_dead;
    wire [31:0] last_dead;
    wire [31:0] llast_dead;
    wire trigger_dead;
    wire [3:0] panic_count;
    wire panic_count_ce;                  

    pueo_time_wrap_v2 #(.WBCLKTYPE("PSCLK"),
                        .SYSCLKTYPE("SYSCLK"),
                        .MEMCLKTYPE("DDRCLK0"))
                     u_time(.wb_clk_i(ps_clk),
                            .wb_rst_i(1'b0),
                            `CONNECT_WBS_IFM( wb_ , time_ ),
                            .sys_clk_i(sys_clk),
                            .pps_i(GPS_TIMEPULSE[0]),
                            .pps_dbg_o(pps_dbg),
                            .runrst_i(runrst),
                            
                            .trig_dead_i(trigger_dead),
                            .panic_count_i(panic_count),
                            .panic_count_ce_i(panic_count_ce),
                            .memclk_i(ddr_clk[0]),
                            
                            .pps_flag_o(pps),
                            .pps_pulse_o(pps_pulse),
                            .gpo_pps_ce_o(gpo_pps_ce),
                            .gpo_pps_d_o(gpo_pps_d),
                            .cur_sec_o(cur_sec),
                            .cur_time_o(cur_time),
                            .last_pps_o(last_pps),
                            .llast_pps_o(llast_pps),
                            .cur_dead_o(cur_dead),
                            .last_dead_o(last_dead),
                            .llast_dead_o(llast_dead));

    `DEFINE_AXI4S_MIN_IF( turfhdr_ , 64 );
    wire turfhdr_tlast;
    wire [3:0] tio_mask;
    wire [11:0] runcfg;

    wire evin_complete_aclk;
    wire evin_complete_sysclk;
    flag_sync u_evin_complete_sync(.in_clkA(evin_complete_aclk),.out_clkB(evin_complete_sysclk),
                                   .clkA(aclk),.clkB(sys_clk));

    wire track_events;
    wire panic;             
    event_pueo_wrap_v2  #(.WBCLKTYPE("PSCLK"),
                          .ETHCLKTYPE("GBECLK"),
                          .ACLKTYPE("USERCLK"),
                          .MEMCLKTYPE("DDRCLK0"))
                    u_event( .wb_clk_i(ps_clk),
                             `CONNECT_WBS_IFM( wb_ , evctl_ ),                    
                             .DDR_CLK_P(DDR_CLK_P[0]),
                             .DDR_CLK_N(DDR_CLK_N[0]),
                             // UI clock output
                             .ddr4_clk_o(ddr_clk[0]),
                             `CONNECT_PHY_IF( c0_ddr4_ , C0_DDR4_ ),
                             .aclk( aclk ),                             
                             `CONNECT_AXI4S_MIN_IF( s_aurora0_ , aur0_ ),
                             .s_aurora0_tlast(aur0_tlast),
                             `CONNECT_AXI4S_MIN_IF( s_aurora1_ , aur1_ ),
                             .s_aurora1_tlast(aur1_tlast),
                             `CONNECT_AXI4S_MIN_IF( s_aurora2_ , aur2_ ),
                             .s_aurora2_tlast(aur2_tlast),
                             `CONNECT_AXI4S_MIN_IF( s_aurora3_ , aur3_ ),
                             .s_aurora3_tlast(aur3_tlast),
                             
                             // in memclk domain
                             `CONNECT_AXI4S_MIN_IF( s_turfhdr_ , turfhdr_ ),
                             .s_turfhdr_tlast(turfhdr_tlast),
                             .tio_mask_o(tio_mask),
                             .runcfg_o(runcfg),
                             
                             .track_events_i(track_events),
                             .evin_complete_o(evin_complete_aclk),
                             
                             .panic_o(panic),
                             .panic_count_o(panic_count),
                             .panic_count_ce_o(panic_count_ce),
                             
                             .ethclk(gbe_sysclk),
                             .event_open_i(event_open),
                             .emergency_stop_i(emergency_stop),
                             .stopped_o(event_stopped),
                             `CONNECT_AXI4S_MIN_IF( s_ack_ , ack_ ),
                             `CONNECT_AXI4S_MIN_IF( s_nack_ , nack_ ),
                             `CONNECT_AXI4S_IF( m_ev_data_ , ev_data_ ),
                             `CONNECT_AXI4S_MIN_IF( m_ev_ctrl_ , ev_ctrl_ ));
    
    
    trig_pueo_wrap_v3 #(.WBCLKTYPE("PSCLK"),
                        .SYSCLKTYPE("SYSCLK"),
                        .MEMCLKTYPE("DDRCLK0"))
                   u_trig( .wb_clk_i(ps_clk),
                           .wb_rst_i(1'b0),
                           `CONNECT_WBS_IFM( wb_ , trig_ ),
                           .sysclk_i(sys_clk),
                           .sysclk_phase_i(sys_clk_phase),
                           .sysclk_sync_i(sys_clk_sync),
                           .sysclk_x2_i(sys_clk_x2),
                           .sysclk_x2_ce_i(sys_clk_x2_ce),
                           .pps_i(pps),
                           .pps_trig_i(GPS_TIMEPULSE[1]),
                           
                           .gp_in_i(gp_in),
                           
                           .gpo_run_ce_o(gpo_run_ce),
                           .gpo_run_d_o(gpo_run_d),
                           .gpo_trig_ce_o(gpo_trig_ce),
                           .gpo_trig_d_o(gpo_trig_d),
                           
                           .tio_mask_i(tio_mask),
                           .runcfg_i(runcfg),
                           .runrst_o(runrst),
                           
                           .track_events_o(track_events),
                           .event_complete_i(evin_complete_sysclk),
                           .panic_i(panic),
                           .dead_o(trigger_dead),

                           .cur_sec_i(cur_sec),
                           .cur_time_i(cur_time),
                           .last_pps_i(last_pps),
                           .llast_pps_i(llast_pps),
                           .cur_dead_i(cur_dead),
                           .last_dead_i(last_dead),
                           .llast_dead_i(llast_dead),
                           
                           .trig_dat_i( { turfiod_trigger, turfioc_trigger,
                                          turfiob_trigger, turfioa_trigger } ),
                           .trig_dat_valid_i( { turfiod_valid, turfioc_valid,
                                                turfiob_valid, turfioa_valid } ),
                                                
                           .memclk(ddr_clk[0]),
                           `CONNECT_AXI4S_MIN_IF( turfhdr_ , turfhdr_ ),
                           .turfhdr_tlast(turfhdr_tlast),
                           
                           .photoshutter_o(photoshutter),
                                                
                           .command67_o(turfio_if_command67),
                           .command68_o(turfio_if_command68));                           

    generate
        if (UART_DEBUG == "TRUE") begin : SERDBG
            // 16x is 8 MHz = 1/12.5th of 100M
            // adding 82 ticks in 1024 is within 0.1%
            localparam [9:0] HSK_ADD = 82;
            reg [10:0] hsk_16x_counter = {11{1'b0}};
            wire hsk_16x = hsk_16x_counter[10];
            // gps is 38400, expand to 12 bits and add 25
            localparam [11:0] GPS_ADD = 25;
            reg [12:0] gps_16x_counter = {13{1'b0}};
            wire gps_16x = gps_16x_counter[12];
            always @(posedge ps_clk) begin : CTRS
                hsk_16x_counter <= hsk_16x_counter[9:0] + HSK_ADD;
                gps_16x_counter <= gps_16x_counter[11:0] + GPS_ADD;
            end
            uart_ila u_ila(.clk(ps_clk),
                           .probe0(hsk_16x),                           
                           .probe1(gps_16x),
                           .probe2(TTXA),
                           .probe3(TRXA),
                           .probe4(TTXB),
                           .probe5(TRXB),
                           .probe6(TTXC),
                           .probe7(TRXC),
                           .probe8(TTXD),
                           .probe9(TRXD),
                           .probe10(GPS_TX),
                           .probe11(GPS_RX),
                           .probe12(UART_SCLK),
                           .probe13(UART_MOSI),
                           .probe14(UART_MISO),
                           .probe15(UART_CS_B),
                           .probe16(UART_IRQ_B),
                           .probe17({GPS_TIMEPULSE[1],pps_dbg}),
                           .probe18(gp_in));
        end
    endgenerate
    
endmodule

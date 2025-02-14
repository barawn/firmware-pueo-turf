`timescale 1ns / 1ps
/////////////////////////////////////////////
// NEW TURF FIRMWARE: Now using PetaLinux  //
// and a bunch of stock cores for serial   //
// crap.                                   //
/////////////////////////////////////////////
module pueo_turf6 #(parameter IDENT="TURF",
                    parameter REVISION="B",
                    parameter [3:0] VER_MAJOR=4'd0,
                    parameter [3:0] VER_MINOR=4'd1,
                    parameter [7:0] VER_REV=4'd3,
                    parameter [15:0] FIRMWARE_DATE = {16{1'b0}})                    
                    (
        output TTXA,
        input TRXA,
        
        output TTXB,
        input TRXB,
        
        output TTXC,
        input TRXC,
        
        output TTXD,
        input TRXD,
        
        output GPS_TX,
        input GPS_RX,
        
        output CLK_SCL,
        inout CLK_SDA,
        
        output CAL_SCL,
        inout CAL_SDA,
        
        output UART_SCLK,
        output UART_MOSI,
        input UART_MISO,
        output UART_CS_B,
        input UART_IRQ_B
    );
    
    localparam UART_DEBUG = "TRUE";
    localparam [15:0] FIRMWARE_VERSION = { VER_MAJOR, VER_MINOR, VER_REV };
    localparam [31:0] DATEVERSION = { (REVISION=="B" ? 1'b1 : 1'b0), FIRMWARE_DATE[14:0], FIRMWARE_VERSION };
    
    wire ps_clk;
    
    wire emio_scl;
    wire emio_sda_i;
    wire emio_sda_t;
        
    // NOTE: we might add in the optional TURFIO I2C controls
    // at some point. If we do that, we need to disconnect the
    // UART. We can only do one of those at a time because their
    // addresses will clash.
    // Our local addresses are only 0x62/0x6A and whatever's
    // on the cal board (will need to check that to not clash!!)
    // on the turfio we pick up 48/10/40/44/11/41/45/46 and 70.
    // that's a busy I2C bus!
    i2c_merger u_i2c_merger(.scl_in(emio_scl),
                            .sda_in_o(emio_sda_i),
                            .sda_in_t(emio_sda_t),
                            .scl0_out(CLK_SCL),
                            .sda0_out(CLK_SDA),
                            .scl1_out(CAL_SCL),
                            .sda1_out(CAL_SDA));
    
    wire [15:0] emio_gpio_t;
    wire [15:0] emio_gpio_i;
    wire [15:0] emio_gpio_o;
    
    // WHATEVER THIS IS TEMPORARY
    wire dna_data;
    (* CUSTOM_DNA_VER = DATEVERSION *)
    DNA_PORTE2 u_dina(.DIN(1'b0),.READ(!emio_gpio_t[1] && emio_gpio_o[1]),.CLK(ps_clk),.DOUT(dna_data));
    assign emio_gpio_i = { {13{1'b0}}, dna_data, UART_IRQ_B };
    
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
                            
                            .pl_clk0(ps_clk));

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
                           .probe11(GPS_RX));
        end
    endgenerate
    
endmodule

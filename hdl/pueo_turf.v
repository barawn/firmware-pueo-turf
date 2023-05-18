`timescale 1ns / 1ps
`include "interfaces.vh"
module pueo_turf(
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
        
        // B2B-1 40 PL_D6_LVDS93_L9N D6
        // B2B-1 42 PL_F6_LVDS93_L1N F6
        // B2B-1 44 PL_G6_LVDS93_L1P G6
        // B2B-1 56 PL_D7_LVDS93_L7N D7
        // B2B-1 58 PL_E7_LVDS93_L7P E7
        output [4:0] GPIO

    );
    
    parameter PROTOTYPE = "TRUE";
    
    // address, data, id, user
    wire ps_clk;
    wire sys_clk;
    wire sys_clk_b;
    // SYSCLK is inverted.
    // 
    generate
        if (PROTOTYPE == "TRUE") begin : POS
            IBUFDS_DIFF_OUT u_sysclk_buf(.I(SYSCLK_N),.IB(SYSCLK_P),.O(sys_clk));    
        end else begin : NEG
            IBUFDS_DIFF_OUT u_sysclk_buf(.I(SYSCLK_N),.IB(SYSCLK_P),.OB(sys_clk));
        end
    endgenerate 
    
    // god *damnit* aaugh
    // let's try the MGT sysclk and see what the hell else we haven't screwed up
    turf_ps_bd_wrapper u_ps(.ACLK(ps_clk),
                            .CLK_IIC_scl_io(CLK_IIC_scl_io),
                            .CLK_IIC_sda_io(CLK_IIC_sda_io),
                            .HSK_UART_rxd(HSK_UART_rxd),
                            .HSK_UART_txd(HSK_UART_txd),
                            .PL_CLK(ps_clk),
                            .PS_RESET_N(1'b1));
    // wrapper for Aurora paths
    turfio_aurora_wrap u_aurora(.init_clk(ps_clk),
                                .MGTCLK_P(MGTCLK_P),
                                .MGTCLK_N(MGTCLK_N),
                                .MGTRX_P(MGTRX_P),
                                .MGTRX_N(MGTRX_N),
                                .MGTTX_P(MGTTX_P),
                                .MGTTX_N(MGTTX_N));

    // let's count system clock
    wire pps_count;
    wire pps_count_sysclk;
    reg count_updated = 0;
    wire count_updated_psclk;
    flag_sync u_countupdate_sync(.in_clkA(count_updated),.out_clkB(count_updated_psclk),
                                .clkA(sys_clk),.clkB(ps_clk));
                                
    dsp_counter_terminal_count #(.FIXED_TCOUNT("TRUE"),
                                 .FIXED_TCOUNT_VALUE(100000000))
        u_ppscount(.clk_i(ps_clk),
                   .rst_i(1'b0),
                   .count_i(1'b1),
                   .tcount_reached_o(pps_count));

    flag_sync u_ppssync(.in_clkA(pps_count),.out_clkB(pps_count_sysclk),
                        .clkA(ps_clk),.clkB(sys_clk));

    (* USE_DSP = "YES" *)
    reg [47:0] clk_counter = {48{1'b0}};
    reg [47:0] clk_full_count = {48{1'b0}};
    reg [47:0] clk_full_count_psclk = {48{1'b0}};
    always @(posedge sys_clk) begin        
        if (pps_count_sysclk) begin
            clk_counter <= {48{1'b0}};
            clk_full_count <= clk_counter;
        end else begin
            clk_counter <= clk_counter + 1;
        end
        count_updated <= pps_count_sysclk;
    end 
    sysclk_ila u_cntila(.clk(sys_clk),.probe0(clk_counter));

    always @(posedge ps_clk) begin
        if (count_updated_psclk) clk_full_count_psclk <= clk_full_count;
    end 
                      
    clk_vio u_vio(.clk(ps_clk),
                  .probe_in0(clk_full_count_psclk));
            
    assign GPIO = {5{1'b1}};
endmodule

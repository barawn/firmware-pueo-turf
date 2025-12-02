`timescale 1ns / 1ps
`include "interfaces.vh"
module pueo_scaler_wrap #(parameter SYSCLKTYPE="NONE",
                          parameter WBCLKTYPE="NONE",
                          parameter ETHCLKTYPE="NONE")(
        
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF(wb_ , 8, 32 ),
        
        input pps_i,
        input [5:0] gp_gate_i,
                
        input sys_clk_i,
        input [5:0] sys_adr_i,
        output [15:0] sys_dat_o,
        
        input eth_clk_i,
        input [5:0] eth_adr_i,
        output [15:0] eth_dat_o,
        
        input [31:0] trig_i,
        input [23:0] leveltwo_i,
        input [1:0] mie_i,
        input [1:0] lf_i,
        input aux_i,
        input levelthree_i
    );
    
    wire gate;
    wire [31:0] gate_enable;
    
    // we have 256 bytes of address space
    // we split this in two: the upper address space is control register stuff
    // and the lower address space are the scalers.

    // OK, we actually need MORE now - but that's fine, because our
    // lower address space was only using 2 registers. We also now only need
    // 24 4-byte (32-bit) scalers. That means we can shave 8 32-bit registers,
    // which is 7:5 == 3'b100. 432 then become the address and 10 are dummy.
    // scaltwo gets selected more than it should, but I don't care.
    
    `DEFINE_WB_IF( scalctrl_ , 7, 32);
    `DEFINE_WB_IF( scal_ , 7, 32);
    `DEFINE_WB_IF( scaltwo_ , 7, 32 );
    `define MAP( pfx_out, pfx_in, condition )   \
        assign pfx_out``cyc_o = pfx_in``cyc_i && condition; \
        assign pfx_out``stb_o = pfx_in``stb_i && condition; \
        assign pfx_out``adr_o = pfx_in``adr_i;              \
        assign pfx_out``sel_o = pfx_in``sel_i;              \
        assign pfx_out``we_o = pfx_in``we_i;                \
        assign pfx_out``dat_o = pfx_in``dat_i
    
    `MAP( scalctrl_ ,   wb_ ,   wb_adr_i[7:5] == 3'b100 );
    `MAP( scal_ ,       wb_ ,   !wb_adr_i[7] );
    `MAP( scaltwo_ ,    wb_ ,   wb_adr_i[7] );
    
    assign scal_dat_i[16 +: 16] = {16{1'b0}};
    assign scaltwo_dat_i[16 +: 16] = {16{1'b0}};
    // this NORMALLY would be bad but we're registering it.
    // no combinatorial acks normally
    assign scal_ack_i = scal_cyc_o && scal_stb_o;
    assign scaltwo_ack_i = scaltwo_cyc_o && scaltwo_stb_o;
    
    wire [31:0] scaltwo_in =  { leveltwo_i , 8'h00 };

    wire [15:0] scal_eth;
    wire [15:0] scal_sys;
    wire [15:0] scaltwo_eth;
    wire [15:0] scaltwo_sys;

    assign eth_dat_o = eth_adr_i[5] ? scaltwo_eth : scal_eth;
    assign sys_dat_o = sys_adr_i[5] ? scaltwo_sys : scal_sys;

    pueo_scaler_register_core #(.SYSCLKTYPE(SYSCLKTYPE),
                                .WBCLKTYPE(WBCLKTYPE))
        u_registers(.wb_clk_i(wb_clk_i),
                    .wb_rst_i(wb_rst_i),
                    `CONNECT_WBS_IFM( wb_ , scalctrl_ ),
                    
                    .sysclk_i(sys_clk_i),
                    .pps_i(pps_i),
                    .gp_gate_i(gp_gate_i),
                    
                    .mie_i(mie_i),
                    .lf_i(lf_i),
                    .aux_i(aux_i),
                    .levelthree_i(levelthree_i),
                    
                    .gate_o(gate),
                    .gate_en_o(gate_enable));                                
    
    reg ack = 0;
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] dat = {32{1'b0}};
    
    always @(posedge wb_clk_i) begin
        if (wb_adr_i[7]) begin
            if (wb_adr_i[6:5] == 2'b00) begin
                ack <= scalctrl_ack_i;
                dat <= scalctrl_dat_i;
            end else begin
                ack <= scaltwo_ack_i;
                dat <= scaltwo_dat_i;
            end                
        end else begin
            ack <= scal_ack_i;
            dat <= scal_dat_i;
        end    
    end
    
    pueo_scaler_core #(.SYSCLKTYPE(SYSCLKTYPE),
                       .WBCLKTYPE(WBCLKTYPE),
                       .ETHCLKTYPE(ETHCLKTYPE))
        u_scaler_core( .sysclk_i(sys_clk_i),
                       .wb_clk_i(wb_clk_i),
                       .wb_adr_i(scal_adr_o[2 +: 5]),
                       .wb_dat_o(scal_dat_i[15:0]),
                       // just ignore ethclk for now
                       .eth_clk_i(eth_clk_i),
                       .eth_adr_i(eth_adr_i[4:0]),
                       .eth_dat_o(scal_eth),
                       // and sysclk
                       .sys_adr_i(sys_adr_i[4:0]),
                       .sys_dat_o(scal_sys),
                       .pps_i(pps_i),
                       .gate_i(gate),
                       .gate_en_i(gate_enable),
                       .trig_i(trig_i));

    pueo_scaler_core #(.SYSCLKTYPE(SYSCLKTYPE),
                       .WBCLKTYPE(WBCLKTYPE),
                       .ETHCLKTYPE(ETHCLKTYPE))
        u_leveltwo_core( .sysclk_i(sys_clk_i),
                       .wb_clk_i(wb_clk_i),
                       .wb_adr_i(scaltwo_adr_o[2 +: 5]),
                       .wb_dat_o(scaltwo_dat_i[15:0]),
                       // just ignore ethclk for now
                       .eth_clk_i(eth_clk_i),
                       .eth_adr_i(eth_adr_i[4:0]),
                       .eth_dat_o(scaltwo_eth),
                       // and sysclk
                       .sys_adr_i(sys_adr_i[4:0]),
                       .sys_dat_o(scaltwo_sys),
                       .pps_i(pps_i),
                       .gate_i(gate),
                       .gate_en_i(gate_enable),
                       .trig_i(scaltwo_in));
    
    
    // what-e-v-er
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;    
    assign wb_ack_o = ack && wb_cyc_i;
    assign wb_dat_o = dat;
endmodule

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
        input [4:0] sys_adr_i,
        output [15:0] sys_dat_o,
        
        input eth_clk_i,
        input [4:0] eth_adr_i,
        output [15:0] eth_dat_o,
        
        input [31:0] trig_i
    );
    
    wire gate;
    wire [31:0] gate_enable;
    
    // we have 256 bytes of address space
    // we split this in two: the upper address space is control register stuff
    // and the lower address space are the scalers.
    
    `DEFINE_WB_IF( scalctrl_ , 7, 32);
    `DEFINE_WB_IF( scal_ , 7, 32);
    `define MAP( pfx_out, pfx_in, condition )   \
        assign pfx_out``cyc_o = pfx_in``cyc_i && condition; \
        assign pfx_out``stb_o = pfx_in``stb_i && condition; \
        assign pfx_out``adr_o = pfx_in``adr_i;              \
        assign pfx_out``sel_o = pfx_in``sel_i;              \
        assign pfx_out``we_o = pfx_in``we_i;                \
        assign pfx_out``dat_o = pfx_in``dat_i
    
    `MAP( scalctrl_ ,   wb_ ,   wb_adr_i[7] );
    `MAP( scal_ ,       wb_,    !wb_adr_i[7] );
    
    assign scal_dat_i[16 +: 16] = {16{1'b0}};
    // this NORMALLY would be bad but we're registering it.
    // no combinatorial acks normally
    assign scal_ack_i = scal_cyc_o && scal_stb_o;
    
    pueo_scaler_register_core #(.SYSCLKTYPE(SYSCLKTYPE),
                                .WBCLKTYPE(WBCLKTYPE))
        u_registers(.wb_clk_i(wb_clk_i),
                    .wb_rst_i(wb_rst_i),
                    `CONNECT_WBS_IFM( wb_ , scalctrl_ ),
                    
                    .sysclk_i(sys_clk_i),
                    .pps_i(pps_i),
                    .gp_gate_i(gp_gate_i),
                    
                    .gate_o(gate),
                    .gate_en_o(gate_enable));                                
    
    reg ack = 0;
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] dat = {32{1'b0}};
    
    always @(posedge wb_clk_i) begin
        if (wb_adr_i[7]) begin
            ack <= scalctrl_ack_i;
            dat <= scalctrl_dat_i;
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
                       .eth_clk_i(),
                       .eth_adr_i(),
                       .eth_dat_o(),
                       // and sysclk
                       .sys_adr_i(),
                       .sys_dat_o(),
                       .pps_i(pps_i),
                       .gate_i(gate),
                       .gate_en_i(gate_enable),
                       .trig_i(trig_i));
    
    
    // what-e-v-er
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;    
    assign wb_ack_o = ack && wb_cyc_i;
    assign wb_dat_o = dat;
endmodule

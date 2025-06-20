`timescale 1ns / 1ps
`include "interfaces.vh"
module pueo_scaler_register_core #(parameter SYSCLKTYPE="NONE",
                                   parameter WBCLKTYPE="NONE")(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 7, 32 ),
        
        input sysclk_i,
        input pps_i,
        input [5:0]     gp_gate_i,
        output          gate_o,
        output [31:0]   gate_en_o
    );
    
    localparam [6:0] GATE_CTRL_ADDR = 7'h00;
    localparam [6:0] GATE_EN_ADDR = 7'h04;
    
    // this is in sysclk so we need it shadowed
    (* CUSTOM_CC_SRC = SYSCLKTYPE, CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [31:0] gate_enable = {32{1'b0}};
    (* CUSTOM_CC_SRC = SYSCLKTYPE, CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [15:0] pps_gatelen = {16{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE, CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] dat_holding = {32{1'b0}};
    
    localparam ACCESS_TYPE_CONTROL = 0;
    localparam ACCESS_TYPE_ENABLE = 1;
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg access_type = ACCESS_TYPE_CONTROL;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg access_write = 0;
    
    
    reg [5:0] gp_rereg = {6{1'b0}};
    (* CUSTOM_CC_SRC = SYSCLKTYPE, CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [2:0] gate_sel = {3{1'b0}};
    
    reg pps_gate = 0;
    reg [15:0] pps_gate_counter = {16{1'b0}};
    reg [5:0] gp_gate_rereg = {6{1'b0}};
    
    wire [7:0] gate_in_expanded = { pps_gate, gp_gate_rereg, 1'b0 };

    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] CYCLE = 1;
    localparam [FSM_BITS-1:0] WAIT_BUSY = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;
    
    reg gate = 0;
    
    wire access_in_sysclk;
    wire access_busy;
    flag_sync u_access(.in_clkA(state == CYCLE),.out_clkB(access_in_sysclk),.busy_clkA(access_busy),
                       .clkA(wb_clk_i),.clkB(sysclk_i));
    always @(posedge sysclk_i) begin
        gp_gate_rereg <= gp_gate_i;
        
        gate <= gate_in_expanded[gate_sel];
        
        if (access_in_sysclk && access_write && access_type == ACCESS_TYPE_CONTROL) begin
            gate_sel <= dat_holding[2:0];
            pps_gatelen <= dat_holding[16 +: 16];
        end                

        if (access_in_sysclk && access_write && access_type == ACCESS_TYPE_ENABLE) begin
            gate_enable <= dat_holding;
        end            

        if (gate_sel == 7 && pps_i) pps_gate <= 1;
        else if (pps_gate_counter == pps_gatelen) pps_gate <= 0;
        
        if (!pps_gate) pps_gate_counter <= {16{1'b0}};
        else pps_gate_counter <= pps_gate_counter + 1;
    end

    always @(posedge wb_clk_i) begin
        if (wb_cyc_i && wb_stb_i) access_write <= wb_we_i;
                
        if (wb_rst_i) state <= IDLE;
        else begin
            case (state)
                IDLE: if (wb_cyc_i && wb_stb_i) state <= CYCLE;
                CYCLE: state <= WAIT_BUSY;
                WAIT_BUSY: if (!access_busy) state <= ACK;
                ACK: state <= IDLE;
            endcase
        end
        
        if (state == IDLE) dat_holding <= wb_dat_i;
        else if (state == WAIT_BUSY && !access_busy && !access_write) begin
            if (access_type == ACCESS_TYPE_CONTROL) begin
                dat_holding <= { pps_gatelen, {13{1'b0}}, gate_sel };
            end else if (access_type == ACCESS_TYPE_ENABLE) begin
                dat_holding <= gate_enable;
            end
        end
        
        if (wb_cyc_i && wb_stb_i) begin
            if (!wb_adr_i[2]) access_type <= ACCESS_TYPE_CONTROL;
            else if (wb_adr_i[2]) access_type <= ACCESS_TYPE_ENABLE;
        end
    end

    assign wb_ack_o = (state == ACK);
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    assign wb_dat_o = dat_holding;
    assign gate_o = gate;
    assign gate_en_o = gate_enable;
endmodule

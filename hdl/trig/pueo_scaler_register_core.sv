`timescale 1ns / 1ps
`include "interfaces.vh"
module pueo_scaler_register_core #(parameter SYSCLKTYPE="NONE",
                                   parameter WBCLKTYPE="NONE")(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 7, 32 ),
        
        input sysclk_i,
        input pps_i,
        
        input [1:0] mie_i,
        input [1:0] lf_i,
        input aux_i,
        input levelthree_i,
        
        input [5:0]     gp_gate_i,
        output          gate_o,
        output [31:0]   gate_en_o
    );
    
    localparam [6:0] GATE_CTRL_ADDR = 7'h00;
    localparam [6:0] GATE_EN_ADDR = 7'h04;
    
    // just be lazy as crap
    reg [1:0][15:0] mie_working_scal = {2*16{1'b0}};
    reg [1:0][15:0] lf_working_scal = {2*16{1'b0}};
    reg [15:0] aux_working_scal = {16{1'b0}};
    reg [15:0] levelthree_working_scal = {16{1'b0}};
    
    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg [1:0][15:0] mie_holding_scal = {2*16{1'b0}};
    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg [1:0][15:0] lf_holding_scal = {2*16{1'b0}};
    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg [15:0] aux_holding_scal = {16{1'b0}};
    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg [15:0] levelthree_holding_scal = {16{1'b0}};

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0][15:0] mie_scal = {2*16{1'b0}};
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0][15:0] lf_scal = {2*16{1'b0}};
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [15:0] aux_scal = {16{1'b0}};
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [15:0] levelthree_scal = {16{1'b0}};

    wire [31:0] scaler_select[3:0];
    assign scaler_select[0] = { mie_scal[1], mie_scal[0] };
    assign scaler_select[1] = { lf_scal[1], lf_scal[0] };
    assign scaler_select[2] = { levelthree_scal, aux_scal };
    assign scaler_select[3] = scaler_select[1];
        
    reg scal_captured = 0;
    wire scal_captured_wbclk;
    flag_sync u_scal_capture_sync(.in_clkA(scal_captured),.out_clkB(scal_captured_wbclk),
                                  .clkA(sysclk_i),.clkB(wb_clk_i));

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

    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] CYCLE = 1;
    localparam [FSM_BITS-1:0] WAIT_BUSY = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    localparam [FSM_BITS-1:0] SCALER = 4;
    reg [FSM_BITS-1:0] state = IDLE;
    
    reg gate = 0;
    
    wire access_in_sysclk;
    wire access_busy;
    flag_sync u_access(.in_clkA(state == CYCLE),.out_clkB(access_in_sysclk),.busy_clkA(access_busy),
                       .clkA(wb_clk_i),.clkB(sysclk_i));
//    reg [1:0][15:0] mie_working_scal = {2*16{1'b0}};
//    reg [1:0][15:0] lf_working_scal = {2*16{1'b0}};
//    reg [15:0] aux_working_scal = {16{1'b0}};
//    reg [15:0] levelthree_working_scal = {16{1'b0}};

    `define SIMPLE_SCALER( working, holding, count) \
        if (pps_i) working <= {16{1'b0}};           \
        else if (working != 16'hFFFF && count)      \
            working <= working + 1;                 \
        if (pps_i) holding <= working

    always @(posedge sysclk_i) begin
        scal_captured <= pps_i;
        
        // no time for elegance, folks
        `SIMPLE_SCALER( mie_working_scal[0] , mie_holding_scal[0], mie_i[0] );
        `SIMPLE_SCALER( mie_working_scal[1] , mie_holding_scal[1], mie_i[1] );
        `SIMPLE_SCALER( lf_working_scal[0], lf_holding_scal[0], lf_i[0] );
        `SIMPLE_SCALER( lf_working_scal[1], lf_holding_scal[1], lf_i[1] );
        `SIMPLE_SCALER( aux_working_scal, aux_holding_scal, aux_i );
        `SIMPLE_SCALER( levelthree_working_scal, levelthree_holding_scal, levelthree_i );
        
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
        if (scal_captured_wbclk) begin
            mie_scal[0] <= mie_holding_scal[0];
            mie_scal[1] <= mie_holding_scal[1];
            lf_scal[0] <= lf_holding_scal[0];
            lf_scal[1] <= lf_holding_scal[1];
            aux_scal <= aux_holding_scal;
            levelthree_scal <= levelthree_holding_scal;
        end
    
        if (wb_cyc_i && wb_stb_i) access_write <= wb_we_i;

        // split up into:
        // wb_adr_i[4:2] == 000 => CONTROL
        // wb_adr_i[4:2] == 001 => ENABLE
        // wb_adr_i[4:2] ==                 
        if (wb_rst_i) state <= IDLE;
        else begin
            case (state)
                IDLE: if (wb_cyc_i && wb_stb_i) begin
                    if (wb_adr_i[4]) state <= SCALER;
                    else state <= CYCLE;
                end
                CYCLE: state <= WAIT_BUSY;
                WAIT_BUSY: if (!access_busy) state <= ACK;
                ACK: state <= IDLE;
                SCALER: state <= ACK;
            endcase
        end
        
        if (state == IDLE) dat_holding <= wb_dat_i;
        else if (state == SCALER) begin
            dat_holding <= scaler_select[wb_adr_i[3:2]];
        end
        else if (state == WAIT_BUSY && !access_busy && !access_write) begin
            if (access_type == ACCESS_TYPE_CONTROL) begin
                dat_holding <= { pps_gatelen, {13{1'b0}}, gate_sel };
            end else if (access_type == ACCESS_TYPE_ENABLE) begin
                dat_holding <= gate_enable;
            end
        end
        
        if (wb_cyc_i && wb_stb_i) begin
            // this splits up into 
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

`timescale 1ns / 1ps
`include "interfaces.vh"
module pueo_time_register_core #(parameter WBCLKTYPE = "NONE",
                                 parameter SYSCLKTYPE = "NONE")(
        input wb_clk_i,
        input wb_rst_i,
        input sys_clk_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 13, 32 ),
        output [15:0] pps_holdoff_o,
        output en_int_pps_o,
        output use_ext_pps_o,
        output [15:0] pps_trim_o,
        input [15:0] pps_trim_i,
        output update_pps_trim_o,
        output [31:0] update_sec_o,
        output load_sec_o,
        input [31:0] cur_sec_i,
        input [31:0] last_pps_i,
        input [31:0] llast_pps_i
    );

    localparam [7:0] CTRL_ADDR = 8'h00;
    localparam [7:0] TRIM_ADDR = 8'h04;
    localparam [7:0] SEC_ADDR = 8'h08;
    localparam [7:0] LASTPPS_ADDR = 8'h0C;
    localparam [7:0] LLASTPPS_ADDR = 8'h10;

    wire capture_req;
    wire capture_req_sysclk;
    // this is a GLOBAL ack from sysclk
    reg ack_sysclk = 0;
    wire ack_sysclk_wbclk;
    
    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg [31:0] cur_sec_holding = {32{1'b0}};
    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg [31:0] last_pps_holding = {32{1'b0}};
    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg [31:0] llast_pps_holding = {32{1'b0}};
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] pps_holdoff = {16{1'b0}};
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg en_int_pps = 0;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg use_ext_pps = 0;
    
    // update trim and load second are both flags.
    wire update_trim_wbclk;
    wire load_sec_wbclk;

    (* CUSTOM_CC_DST = WBCLKTYPE, CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [31:0] dat_reg = {32{1'b0}};        
        
    always @(posedge sys_clk_i) begin
        if (capture_req_sysclk) begin
            cur_sec_holding <= cur_sec_i;
            last_pps_holding <= last_pps_i;
            llast_pps_holding <= llast_pps_i;
        end
        // this is _actually_ a flag.
        ack_sysclk <= (capture_req_sysclk || update_pps_trim_o || load_sec_o);
    end

    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WAIT_TASK = 1;
    localparam [FSM_BITS-1:0] CAPTURE = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;

    assign capture_req = (state == IDLE && wb_cyc_i && wb_stb_i && !wb_we_i && wb_adr_i[7:0] == SEC_ADDR);
    assign update_trim_wbclk = (state == IDLE && wb_we_i && wb_adr_i[7:0] == TRIM_ADDR);
    assign load_sec_wbclk = (state == IDLE && wb_we_i && wb_adr_i[7:0] == SEC_ADDR);

    flag_sync u_capture_sync(.in_clkA(capture_req),.out_clkB(capture_req_sysclk),
                             .clkA(wb_clk_i),.clkB(sys_clk_i));
    flag_sync u_update_sync(.in_clkA(update_trim_wbclk),.out_clkB(update_pps_trim_o),
                            .clkA(wb_clk_i),.clkB(sys_clk_i));
    flag_sync u_load_sync(.in_clkA(load_sec_wbclk),.out_clkB(load_sec_o),
                          .clkA(wb_clk_i),.clkB(sys_clk_i));
    flag_sync u_ack_sync(.in_clkA(ack_sysclk),.out_clkB(ack_sysclk_wbclk),
                         .clkA(sys_clk_i),.clkB(wb_clk_i));
    always @(posedge wb_clk_i) begin
        // ctrl addr is purely in wbclk space
        if (state == ACK && wb_we_i && wb_adr_i[7:0] == CTRL_ADDR) begin
            if (wb_sel_i[0]) begin
                en_int_pps <= wb_dat_i[0];
                use_ext_pps <= wb_dat_i[1];
            end
            if (wb_sel_i[2]) pps_holdoff[0 +: 8] <= wb_dat_i[16 +: 8];
            if (wb_sel_i[3]) pps_holdoff[8 +: 8] <= wb_dat_i[24 +: 8];                
        end
        
        if (wb_rst_i) state <= IDLE;
        else case(state)
            IDLE: if (wb_cyc_i && wb_stb_i) begin
                if (wb_adr_i == CTRL_ADDR) state <= (wb_we_i) ? ACK : CAPTURE;
                else if (wb_adr_i == SEC_ADDR) state <= WAIT_TASK;
                else if (wb_we_i && wb_adr_i == TRIM_ADDR) state <= WAIT_TASK;
                else state <= (wb_we_i) ? ACK : CAPTURE;
            end
            WAIT_TASK: if (ack_sysclk_wbclk) state <= (wb_we_i) ? ACK : CAPTURE;
            CAPTURE: state <= ACK;
            ACK: state <= IDLE;
        endcase
        
        if (state == IDLE) dat_reg <= wb_dat_i;
        else if (state == CAPTURE) begin
            if (wb_adr_i == CTRL_ADDR)
                dat_reg <= { pps_holdoff, {14{1'b0}}, use_ext_pps, en_int_pps };
            else if (wb_adr_i == TRIM_ADDR)
                dat_reg <= { {16{1'b0}}, pps_trim_i };
            else if (wb_adr_i == SEC_ADDR)
                dat_reg <= cur_sec_holding;
            else if (wb_adr_i == LASTPPS_ADDR)
                dat_reg <= last_pps_holding;
            else if (wb_adr_i == LLASTPPS_ADDR)
                dat_reg <= llast_pps_holding;
        end
    end
        
    assign use_ext_pps_o = use_ext_pps;
    assign en_int_pps_o = en_int_pps;
    
    assign pps_trim_o = dat_reg[15:0];
    assign update_sec_o = dat_reg;
    
    assign wb_dat_o = dat_reg;
    assign wb_ack_o = (state == ACK) && wb_cyc_i;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
endmodule

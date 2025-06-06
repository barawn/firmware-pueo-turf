`timescale 1ns / 1ps
`include "interfaces.vh"
module pueo_trig_ctrl #(
    // number of clocks from sysclk_phase_i to when data is output
    parameter PHASE_OFFSET=3,
    parameter WBCLKTYPE = "NONE",
    parameter SYSCLKTYPE = "NONE"
    )(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 8, 32 ),
        
        // trigger output-y stuff
        input sysclk_i,
        input sysclk_phase_i,
        output [11:0] turf_trig_o,
        output [7:0]  turf_metadata_o,
        output        turf_valid_o,
        
        // system address time
        input [11:0]  cur_addr_i,
        // no triggers if we're not running
        input         running_i,                

        // masks
        output [27:0] trig_mask_o,
        output update_trig_mask_o,

        // constants
        output [15:0] trig_latency_o,
        output [15:0] trig_offset_o
    );

    // There is no soft offset because it doesn't matter,
    // it's untimed.
    localparam [7:0] MASK_ADDR =    8'h00;
    localparam [7:0] LATENCY_OFFSET_ADDR = 8'h04;
    localparam [7:0] PPS_OFFSET_ADDR =  8'h08;
    localparam [7:0] EXT_OFFSET_ADDR = 8'h0C;
    localparam [7:0] SOFT_TRIGGER_ADDR = 8'h10;
    localparam [7:0] PPS_EXT_TRIGGER_ADDR = 8'h14;
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [27:0] mask_register = {28{1'b1}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] offset_register = {16{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] latency_register = {16{1'b0}};
    
    reg soft_trig = 0;
    wire soft_trig_sysclk;
    
    reg ack = 0;
    reg [31:0] dat_reg = {32{1'b0}};
    always @(posedge wb_clk_i) begin
        ack <= wb_cyc_i && wb_stb_i;        
        if (wb_cyc_i && wb_stb_i && !wb_we_i) begin
            if (wb_adr_i == MASK_ADDR) dat_reg <= { {4{1'b0}}, mask_register };
            else if (wb_adr_i == LATENCY_OFFSET_ADDR) dat_reg <= { offset_register, latency_register };
            else dat_reg <= {32{1'b0}};
        end
        if (wb_cyc_i && wb_stb_i && wb_we_i) begin
            if (wb_adr_i == MASK_ADDR) begin
                if (wb_sel_i[0]) mask_register[7:0] <= wb_dat_i[7:0];
                if (wb_sel_i[1]) mask_register[15:8] <= wb_dat_i[15:8];
                if (wb_sel_i[2]) mask_register[23:16] <= wb_dat_i[23:16];
                if (wb_sel_i[3]) mask_register[27:24] <= wb_dat_i[27:24];
            end
            if (wb_adr_i == LATENCY_OFFSET_ADDR) begin
                if (wb_sel_i[0]) latency_register[7:0] <= wb_dat_i[7:0];
                if (wb_sel_i[1]) latency_register[15:8] <= wb_dat_i[15:8];
                if (wb_sel_i[2]) offset_register[7:0] <= wb_dat_i[23:16];
                if (wb_sel_i[3]) offset_register[15:8] <= wb_dat_i[31:24];
            end
        end
        soft_trig <= ack && (wb_adr_i == SOFT_TRIGGER_ADDR && wb_we_i);
    end

    // JUST SOFT TRIGS FOR NOW!
    // ADD A MUX AND FIFO FOR ALL OF EM LATER
    // OR MAYBE JUST FEED 'EM ALL IN???
    reg [11:0] turf_addr_in = {12{1'b0}};
    reg [7:0]  turf_metadata_in = 8'h80;
    reg        turf_trig_write = 0;
    reg        soft_trig_pending = 0;
    // sysclk_phase_i is 8 clocks, we need to hold data for 4 clocks.
    reg [5:0]  phase_shreg = {8{1'b0}};
    // phase    phase_shreg     cycle
    // 1        000000             0
    // 0        000001             1
    // 0        000010             2    0   capture here
    // 0        000100             3    1
    // 0        001000             4    1
    // 0        010000             5    1
    // 0        100000             6    1   release here
    always @(posedge sysclk_i) begin
        phase_shreg <= { phase_shreg[4:0], sysclk_phase_i };
        // dunno, reset this maybe??? 
        if (turf_trig_write && phase_shreg[5]) begin
            turf_metadata_in[6:0] <= turf_metadata_in[6:0] + 1;
        end
        if (soft_trig_sysclk) turf_addr_in <= cur_addr_i;
        if (soft_trig_sysclk && running_i) soft_trig_pending <= 1;
        else if (phase_shreg[1]) soft_trig_pending <= 0;

        if (phase_shreg[5]) turf_trig_write <= 0;
        else if (phase_shreg[1]) turf_trig_write <= soft_trig_pending;
    end

    flag_sync u_soft_sync(.in_clkA(soft_trig),.out_clkB(soft_trig_sysclk),
                          .clkA(wb_clk_i),.clkB(sysclk_i));

    flag_sync u_update_sync(.in_clkA(wb_ack_o && wb_adr_i == MASK_ADDR && wb_we_i),
                            .out_clkB(update_trig_mask_o),
                            .clkA(wb_clk_i),
                            .clkB(sysclk_i));
                            
    assign turf_trig_o = turf_addr_in;
    assign turf_metadata_o = turf_metadata_in;
    assign turf_valid_o = turf_trig_write;                                

    assign trig_mask_o = mask_register;
    assign trig_latency_o = latency_register;
    assign trig_offset_o = offset_register;

    assign wb_dat_o = dat_reg;                                
    assign wb_ack_o = ack && wb_cyc_i;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
endmodule

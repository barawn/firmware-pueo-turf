`timescale 1ns / 1ps
// Collect all the controls.
`include "interfaces.vh"
module event_register_core #(parameter WBCLKTYPE="NONE",
                             parameter ACLKTYPE="NONE",
                             parameter ETHCLKTYPE="NONE",
                             parameter MEMCLKTYPE="NONE")(
        input wb_clk_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 13, 32 ),
        
        input trigger_running_i,
        output [3:0] tio_mask_o,
        output [3:0] tio_mask_aclk_o,
        output [3:0] tio_mask_memclk_o,

        output [11:0] runcfg_o,
        
        input [3:0] track_err_i,
        
        input [31:0] full_aclk_err_i,
        input [31:0] full_memclk_err_i,
        input [31:0] full_readout_err_i,
        
        input  event_open_i,
        output event_reset_o,
        output event_reset_aclk_o,
        output event_reset_memclk_o,
        output event_reset_ethclk_o,
        
        output ddr_reset_memclk_o,
        
        // in aclk space
        input aclk,
        input [3:0] aurora_tvalid,
        // in ethclk space
        input ethclk,
        input eth_tx_qword_i,
        input eth_tx_event_i,
        input [11:0] ack_count_i,
        // used for tio mask
        input memclk,
        input [13:0] cmpl_count_i,
        input [12:0] allow_count_i
    );
    
    wire [31:0] out_events;
    wire [31:0] out_qwords;
    wire [31:0] event_dwords[3:0];   

    (* CUSTOM_CC_SRC = WBCLKTYPE *)    
    reg ddr_reset = 0;
    (* CUSTOM_CC_DST = MEMCLKTYPE *)
    reg [1:0] ddr_reset_resync = {2{1'b0}};
    wire ddr_reset_delay;
    reg final_ddr_reset = 0;
    SRL16E #(.INIT(16'hFFF0))
        u_rst_dly(.D(ddr_reset_resync[1]),
                  .CE(1'b1),
                  .CLK(memclk),
                  .A0(1'b1),
                  .A1(1'b1),
                  .A2(1'b1),
                  .A3(1'b1),
                  .Q(ddr_reset_delay));
    always @(posedge memclk) begin
        final_ddr_reset <= ddr_reset_delay;
        ddr_reset_resync <= { ddr_reset_resync[0], ddr_reset };        
    end
    
    reg event_force_reset = 0;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg event_reset = 0;
    (* CUSTOM_CC_DST = ACLKTYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] event_reset_aclk = {2{1'b0}};
    (* CUSTOM_CC_DST = MEMCLKTYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] event_reset_memclk = {2{1'b0}};
    (* CUSTOM_CC_DST = ETHCLKTYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] event_reset_ethclk = {2{1'b0}};    
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [11:0] runcfg = {12{1'b0}};

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [2:0] running_wbclk = {2{1'b0}};    

    reg [3:0] tio_mask_next = {4{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [3:0] tio_mask = {4{1'b0}};
    (* CUSTOM_CC_DST = ACLKTYPE *)
    reg [3:0] tio_mask_aclk = {4{1'b0}};
    (* CUSTOM_CC_DST = MEMCLKTYPE *)
    reg [3:0] tio_mask_memclk = {4{1'b0}};
    
    // just use an async reg right now:
    // if we need to do this for more than 1 in each domain refactor
    wire [11:0] ack_count_wbclk;
    async_register #(.WIDTH(12),
                     .UPDATE_PERIOD(6),
                     .CLKATYPE(ETHCLKTYPE),
                     .CLKBTYPE(WBCLKTYPE))
        u_ack_count_reg(.clkA(ethclk),
                          .in_clkA(ack_count_i),
                          .clkB(wb_clk_i),
                          .out_clkB(ack_count_wbclk));
    wire [12:0] allow_count_wbclk;
    async_register #(.WIDTH(13),
                     .UPDATE_PERIOD(12),
                     .CLKATYPE(MEMCLKTYPE),
                     .CLKBTYPE(WBCLKTYPE))
        u_allow_count_reg(.clkA(memclk),
                          .in_clkA(allow_count_i),
                          .clkB(wb_clk_i),
                          .out_clkB(allow_count_wbclk));                     
    wire [13:0] cmpl_count_wbclk;
    async_register #(.WIDTH(14),
                     .UPDATE_PERIOD(12),
                     .CLKATYPE(MEMCLKTYPE),
                     .CLKBTYPE(WBCLKTYPE))
        u_cmpl_count_reg(.clkA(memclk),
                         .in_clkA(cmpl_count_i),
                         .clkB(wb_clk_i),
                         .out_clkB(cmpl_count_wbclk));                                                          
                            
    reg update_tio_mask = 0;
    wire update_tio_mask_aclk;
    wire update_tio_mask_memclk;    
    
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [3:0] track_err_wbclk = {4{1'b0}};
    
    wire [31:0] glob_event_reg = { {4{1'b0}}, runcfg,           // 16
                                   track_err_wbclk, tio_mask_next,         // 8
                                   tio_mask, 1'b0, ddr_reset, event_reset, event_force_reset};    // 8
    
    reg ack = 0;
    wire [3:0] reg_addr = wb_adr_i[2 +: 4];

    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] aclk_err_reg = {32{1'b0}};
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] memclk_err_reg = {32{1'b0}};
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [31:0] readout_err_reg = {32{1'b0}};

    reg [31:0] dat_reg = {32{1'b0}};    
    wire [31:0] event_regs[15:0];
    assign event_regs[0] = glob_event_reg;
    assign event_regs[1] = glob_event_reg;        
    assign event_regs[2] = glob_event_reg;
    assign event_regs[3] = glob_event_reg;
    assign event_regs[4] = event_dwords[0];
    assign event_regs[5] = event_dwords[1];
    assign event_regs[6] = event_dwords[2];
    assign event_regs[7] = event_dwords[3];
    // fully shadow the top bit decode
    assign event_regs[8] = out_qwords;
    assign event_regs[9] = out_events;
    // bits 11:0 ack_count (12 bits starting at bit 0)
    // bits 28:16 allow_count (13 bits starting at bit 16)
    assign event_regs[10] = {{3{1'b0}},allow_count_wbclk,{4{1'b0}},ack_count_wbclk};
    assign event_regs[11] = aclk_err_reg;
    assign event_regs[12] = memclk_err_reg;
    assign event_regs[13] = readout_err_reg;
    assign event_regs[14] = { {16{1'b0}}, {2{1'b0}}, cmpl_count_wbclk };
    assign event_regs[15] = event_regs[7];
    
    always @(posedge wb_clk_i) begin
        running_wbclk <= {running_wbclk[1:0], trigger_running_i};

        if (!running_wbclk[2] && running_wbclk[1]) begin
            tio_mask <= tio_mask_next;
        end
    
        aclk_err_reg <= full_aclk_err_i;
        memclk_err_reg <= full_memclk_err_i;
        readout_err_reg <= full_readout_err_i;
    
        track_err_wbclk <= track_err_i;
                
        event_reset <= event_force_reset || !event_open_i;
    
        if (wb_cyc_i && wb_stb_i && !wb_we_i && !ack) begin
            dat_reg <= event_regs[reg_addr];
        end            
        ack <= wb_cyc_i && wb_stb_i;
        if (wb_cyc_i && wb_stb_i && wb_ack_o && wb_we_i) begin
            if (reg_addr == 4'h0) begin
                if (wb_sel_i[0]) begin
                    event_force_reset <= wb_dat_i[0];
                    ddr_reset <= wb_dat_i[2];
                end
                if (wb_sel_i[1]) tio_mask_next <= wb_dat_i[8 +: 4];
                if (wb_sel_i[2]) runcfg[0 +: 8] <= wb_dat_i[16 +: 8];
                if (wb_sel_i[3]) runcfg[8 +: 4] <= wb_dat_i[24 +: 4];
            end
        end
        update_tio_mask <= !running_wbclk[2] && running_wbclk[1];
    end

    always @(posedge aclk) begin
        event_reset_aclk <= { event_reset_aclk[0], event_reset };
        if (update_tio_mask_aclk) tio_mask_aclk <= tio_mask;
    end

    always @(posedge memclk) begin
        event_reset_memclk <= { event_reset_memclk[0], event_reset };
        if (update_tio_mask_memclk) tio_mask_memclk <= tio_mask;
    end
    
    always @(posedge ethclk) begin
        event_reset_ethclk <= { event_reset_ethclk[0], event_reset };        
    end

    

    flag_sync u_update_mask(.in_clkA(update_tio_mask),.out_clkB(update_tio_mask_aclk),
                            .clkA(wb_clk_i),.clkB(aclk));
    flag_sync u_update_mask_mem(.in_clkA(update_tio_mask),.out_clkB(update_tio_mask_memclk),
                            .clkA(wb_clk_i),.clkB(memclk));                            

    event_cc_stat_counter #(.WBCLKTYPE(WBCLKTYPE),
                            .ACLKTYPE(ACLKTYPE),
                            .NUM_COUNTS(2))
                          u_out_statistics(.aclk(ethclk),
                                           .tx_valid_i( { eth_tx_event_i, eth_tx_qword_i }),
                                           .wb_clk_i(wb_clk_i),
                                           .rst_i(event_reset),
                                           .tx_count_o({ out_events, out_qwords }));    

    event_cc_stat_counter #(.WBCLKTYPE(WBCLKTYPE),
                            .ACLKTYPE(ETHCLKTYPE),
                            .NUM_COUNTS(4))
                          u_statistics(.aclk(aclk),
                                       .tx_valid_i(aurora_tvalid),
                                       .wb_clk_i(wb_clk_i),
                                       .rst_i(event_reset),
                                       .tx_count_o({event_dwords[3],
                                                    event_dwords[2],
                                                    event_dwords[1],
                                                    event_dwords[0]}));

    assign runcfg_o = runcfg;
    
    assign ddr_reset_memclk_o = final_ddr_reset;
    
    assign event_reset_o = event_reset;
    assign event_reset_aclk_o = event_reset_aclk[1];
    assign event_reset_memclk_o = event_reset_memclk[1];
    assign event_reset_ethclk_o = event_reset_ethclk[1];

    assign tio_mask_o = tio_mask;
    assign tio_mask_aclk_o = tio_mask_aclk;
    assign tio_mask_memclk_o = tio_mask_memclk;

    assign wb_ack_o = ack && wb_cyc_i && wb_stb_i;
    assign wb_dat_o = dat_reg;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
endmodule

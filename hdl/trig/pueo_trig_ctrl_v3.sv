`timescale 1ns / 1ps
`include "interfaces.vh"
// there was never a v2, this is just to match everything's name.
module pueo_trig_ctrl_v3 #(
    // number of clocks from sysclk_phase_i to when data is output
    parameter PHASE_OFFSET=3,
    parameter WBCLKTYPE = "NONE",
    parameter SYSCLKTYPE = "NONE",
    // these are spec'd as zero because the module above
    // always does it.
    parameter [15:0] DEFAULT_HOLDOFF = 16'd0,
    parameter [15:0] DEFAULT_LATENCY = 16'd0,
    parameter [15:0] DEFAULT_OFFSET = 16'd0,
    parameter [15:0] DEFAULT_PHOTO_PRESCALE = 16'd0
    )(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 8, 32 ),
        
        // trigger output-y stuff
        input sysclk_i,
        input sysclk_phase_i,
        output [11:0] turf_soft_trig_o,
        output [7:0]  turf_soft_metadata_o,
        output        turf_soft_valid_o,

        output [11:0] turf_pps_trig_o,
        output [7:0]  turf_pps_metadata_o,
        output        turf_pps_valid_o,

        output [11:0] turf_ext_trig_o,
        output [7:0]  turf_ext_metadata_o,
        output        turf_ext_valid_o,

        
        // system address time
        input [11:0]  cur_addr_i,
        // no triggers if we're not running
        input         running_i,                

        input pps_trig_i,
        
        input [5:0] gp_in_i,

        // monitoring
        input [31:0] occupancy_i,
        input surf_err_i,
        input turf_err_i,

        // for the event counter wbclk shadow
        input  event_i,

        // masks
        output [27:0] trig_mask_o,
        output update_trig_mask_o,

        // constants captured at run start
        output [15:0] trig_latency_o,
        output [15:0] trig_offset_o,
        output [15:0] trig_holdoff_o,
        output [15:0] photo_prescale_o,
        output photo_en_o
    );

    // There is no soft offset because it doesn't matter,
    // it's untimed.
    localparam [7:0] MASK_ADDR =    8'h00;
    localparam [7:0] LATENCY_OFFSET_ADDR = 8'h04;
    localparam [7:0] PPS_TRIGGER_ADDR =  8'h08;         // bit 0: enable bits [31:16] = offset
    localparam [7:0] EXT_TRIGGER_ADDR = 8'h0C;          // bit 0: enable bits[10:8] = select bits [31:16] = offset
    localparam [7:0] SOFT_TRIGGER_ADDR = 8'h10;
    localparam [7:0] OCCUPANCY_ADDR = 8'h14;
    localparam [7:0] HOLDOFF_ERR_ADDR = 8'h18;
    localparam [7:0] EVENT_COUNT_ADDR = 8'h1C;
    localparam [7:0] EXT_PRESCALE_ADDR = 8'h20;
    localparam [7:0] PHOTO_PRESCALE_ADDR = 8'h24;

    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [27:0] mask_register = {28{1'b1}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] offset_register = DEFAULT_OFFSET;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] latency_register = DEFAULT_LATENCY;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] holdoff_register = DEFAULT_HOLDOFF;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] photo_prescale = DEFAULT_PHOTO_PRESCALE;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg photo_en = 0;
            
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0] running_wbclk = {2{1'b0}};
    
    reg soft_trig = 0;
    wire soft_trig_sysclk;

    wire event_flag_wbclk;
    flag_sync u_event_flag_sync(.in_clkA(event_i),.out_clkB(event_flag_wbclk),
                                .clkA(sysclk_i),.clkB(wb_clk_i));
    reg [31:0] event_counter_shadow = {32{1'b0}};    
    
    reg ack = 0;
    reg [31:0] dat_reg = {32{1'b0}};

    // NEVER change pps_offset, ext offset, or ext_trig sel
    // when the corresponding trigger is enabled. They're just considered
    // to be static on the sysclk side.
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg en_pps_trig = 0;
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [1:0] en_pps_trig_sysclk = {2{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] pps_offset_register = {16{1'b0}};    
    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg en_ext_trig = 0;
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [1:0] en_ext_trig_sysclk = {2{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [2:0] ext_trig_sel = {2{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] ext_offset_register = {16{1'b0}};    

    wire update_prescale_sysclk;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [15:0] ext_prescale = {16{1'b0}};
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [15:0] ext_prescale_sysclk = {16{1'b0}};
    // prescales work by counting down and bit 16 is the trip    
    reg [16:0] ext_prescale_counter = {17{1'b0}};
    
    always @(posedge wb_clk_i) begin
        running_wbclk <= { running_wbclk[0], running_i };
    
        if (!running_wbclk) event_counter_shadow <= {32{1'b0}};
        else if (event_flag_wbclk) event_counter_shadow <= event_counter_shadow + 1;
    
        ack <= wb_cyc_i && wb_stb_i;        
        if (wb_cyc_i && wb_stb_i && !wb_we_i) begin
            if (wb_adr_i == MASK_ADDR) dat_reg <= { {4{1'b0}}, mask_register };
            else if (wb_adr_i == LATENCY_OFFSET_ADDR) dat_reg <= { offset_register, latency_register };
            else if (wb_adr_i == PPS_TRIGGER_ADDR) dat_reg <= { pps_offset_register, {15{1'b0}}, en_pps_trig };
            else if (wb_adr_i == EXT_TRIGGER_ADDR) dat_reg <= { ext_offset_register, {5{1'b0}}, ext_trig_sel, {7{1'b0}}, en_ext_trig };
            else if (wb_adr_i == OCCUPANCY_ADDR) dat_reg <= occupancy_i;
            else if (wb_adr_i == HOLDOFF_ERR_ADDR) dat_reg <= { {14{1'b0}}, turf_err_i, surf_err_i, holdoff_register };
            else if (wb_adr_i == SOFT_TRIGGER_ADDR) dat_reg <= { {15{1'b0}}, running_wbclk, {16{1'b0}} };
            else if (wb_adr_i == EVENT_COUNT_ADDR) dat_reg <= event_counter_shadow;
            else if (wb_adr_i == EXT_PRESCALE_ADDR) dat_reg <= { {16{1'b0}}, ext_prescale };
            else if (wb_adr_i == PHOTO_PRESCALE_ADDR) dat_reg <= { {15{1'b0}}, photo_en, photo_prescale };
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
            if (wb_adr_i == HOLDOFF_ERR_ADDR) begin
                if (wb_sel_i[0]) holdoff_register[7:0] <= wb_dat_i[7:0];
                if (wb_sel_i[1]) holdoff_register[15:8] <= wb_dat_i[15:8];
            end
            if (wb_adr_i == PPS_TRIGGER_ADDR) begin
                if (wb_sel_i[0]) en_pps_trig <= wb_dat_i[0];
                if (wb_sel_i[2]) pps_offset_register[7:0] <= wb_dat_i[16 +: 8];
                if (wb_sel_i[3]) pps_offset_register[15:8] <= wb_dat_i[24 +: 8];
            end
            if (wb_adr_i == EXT_TRIGGER_ADDR) begin
                if (wb_sel_i[0]) en_ext_trig <= wb_dat_i[0];
                if (wb_sel_i[1]) ext_trig_sel <= wb_dat_i[8 +: 3];
                if (wb_sel_i[2]) ext_offset_register[7:0] <= wb_dat_i[16 +: 8];
                if (wb_sel_i[3]) ext_offset_register[15:8] <= wb_dat_i[24 +: 8];
            end
            if (wb_adr_i == EXT_PRESCALE_ADDR) begin
                if (wb_sel_i[0]) ext_prescale <= wb_dat_i[0 +: 8];
                if (wb_sel_i[1]) ext_prescale <= wb_dat_i[8 +: 8];
            end
            if (wb_adr_i == PHOTO_PRESCALE_ADDR) begin
                if (wb_sel_i[0]) photo_prescale <= wb_dat_i[0 +: 8];
                if (wb_sel_i[1]) photo_prescale <= wb_dat_i[8 +: 8];
                if (wb_sel_i[2]) photo_en <= wb_dat_i[16];
            end
        end
        soft_trig <= ack && (wb_adr_i == SOFT_TRIGGER_ADDR && wb_we_i);
    end

    reg [11:0] turf_soft_addr_in = {12{1'b0}};
    reg [7:0]  turf_soft_metadata_in = 8'h80;
    reg        turf_soft_trig_write = 0;

    reg        soft_trig_pending = 0;

    reg [2:0]  pps_rereg = {3{1'b0}};
    reg        pps_trig_sysclk = 0;
    reg        pps_trig_pending = 0;
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [11:0] turf_pps_addr_in = {12{1'b0}};
    reg [7:0]  turf_pps_metadata_in = 8'h80;
    reg        turf_pps_trig_write = 0;

    (* CUSTOM_CC_DST = SYSCLKTYPE *)    
    reg        ext_demux = 0;
    reg [1:0]  ext_rereg = {2{1'b0}};
    // this mapping is to allow for it to be the same as the gate
    wire [7:0] ext_in_expanded = { 1'b0, gp_in_i , 1'b0 };
    wire       ext_in = ext_in_expanded[ext_trig_sel];
    
    reg        ext_trig_sysclk = 0;
    reg        ext_trig_pending = 0;
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [11:0] turf_ext_addr_in = {12{1'b0}};
    reg [7:0]  turf_ext_metadata_in = 8'h80;
    reg        turf_ext_trig_write = 0;

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
        en_pps_trig_sysclk <= { en_pps_trig_sysclk[0], en_pps_trig };
        en_ext_trig_sysclk <= { en_ext_trig_sysclk[0], en_ext_trig };

        /// SOFT TRIGGER
        if (!running_i) turf_soft_metadata_in <= 8'h80;
        else if (turf_soft_trig_write && phase_shreg[5]) begin
            turf_soft_metadata_in[6:0] <= turf_soft_metadata_in[6:0] + 1;
        end
        if (soft_trig_sysclk) turf_soft_addr_in <= cur_addr_i;

        if (soft_trig_sysclk) soft_trig_pending <= 1;
        else if (phase_shreg[1]) soft_trig_pending <= 0;        

        if (phase_shreg[5]) turf_soft_trig_write <= 0;
        else if (phase_shreg[1]) turf_soft_trig_write <= soft_trig_pending;

        /// PPS TRIGGER
        if (!running_i) turf_pps_metadata_in <= 8'h80;
        else if (turf_pps_trig_write && phase_shreg[5]) begin
            turf_pps_metadata_in[6:0] <= turf_pps_metadata_in[6:0] + 1;
        end           
        pps_rereg <= {pps_rereg[1:0], pps_trig_i};                
        pps_trig_sysclk <= pps_rereg[1] && !pps_rereg[2] && en_pps_trig_sysclk[1] && !pps_trig_pending;

        if (pps_trig_sysclk) turf_pps_addr_in <= cur_addr_i - pps_offset_register;
        
        if (pps_trig_sysclk) pps_trig_pending <= 1;
        else if (phase_shreg[1]) pps_trig_pending <= 0;
        
        if (phase_shreg[5]) turf_pps_trig_write <= 0;
        else if (phase_shreg[1]) turf_pps_trig_write <= pps_trig_pending;
                                     
        /// EXT TRIGGER
        if (!running_i) turf_ext_metadata_in <= 8'h80;
        else if (turf_ext_trig_write && phase_shreg[5]) begin
            turf_ext_metadata_in[6:0] <= turf_ext_metadata_in[6:0] + 1;
        end

        ext_demux <= ext_in;           
        ext_rereg <= {ext_rereg[0], ext_demux};
        // no effing flooding us, jackasses
        ext_trig_sysclk <= ext_rereg[0] && !ext_rereg[1] && en_ext_trig_sysclk[1] && !ext_trig_pending;
        
        if (ext_prescale_counter[16]) ext_prescale_counter <= ext_prescale_sysclk;
        else if (ext_trig_sysclk) ext_prescale_counter <= ext_prescale_counter - 1;
        
        if (ext_prescale_counter[16]) begin
            turf_ext_addr_in <= cur_addr_i - ext_offset_register;
            ext_trig_pending <= 1;
        end else if (phase_shreg[1]) begin
            ext_trig_pending <= 0;
        end        
        
        if (phase_shreg[5]) turf_ext_trig_write <= 0;
        else if (phase_shreg[1]) turf_ext_trig_write <= ext_trig_pending;

        if (update_prescale_sysclk) ext_prescale_sysclk <= ext_prescale;
    end

    flag_sync u_soft_sync(.in_clkA(soft_trig),.out_clkB(soft_trig_sysclk),
                          .clkA(wb_clk_i),.clkB(sysclk_i));

    flag_sync u_update_sync(.in_clkA(wb_ack_o && wb_adr_i == MASK_ADDR && wb_we_i),
                            .out_clkB(update_trig_mask_o),
                            .clkA(wb_clk_i),
                            .clkB(sysclk_i));

    flag_sync u_update_ext_pre(.in_clkA(wb_ack_o && wb_adr_i == EXT_PRESCALE_ADDR && wb_we_i),
                               .out_clkB(update_prescale_sysclk),
                               .clkA(wb_clk_i),
                               .clkB(sysclk_i));
                            
    assign turf_soft_trig_o = turf_soft_addr_in;
    assign turf_soft_metadata_o = turf_soft_metadata_in;
    assign turf_soft_valid_o = turf_soft_trig_write;
    
    assign turf_pps_trig_o = turf_pps_addr_in;
    assign turf_pps_metadata_o = turf_pps_metadata_in;
    assign turf_pps_valid_o = turf_pps_trig_write;
    
    assign turf_ext_trig_o = turf_ext_addr_in;
    assign turf_ext_metadata_o = turf_ext_metadata_in;
    assign turf_ext_valid_o = turf_ext_trig_write;
    
    assign trig_mask_o = mask_register;
    assign trig_latency_o = latency_register;
    assign trig_offset_o = offset_register;
    assign trig_holdoff_o = holdoff_register;
    assign photo_prescale_o = photo_prescale;
    assign photo_en_o = photo_en;
        
    assign wb_dat_o = dat_reg;                                
    assign wb_ack_o = ack && wb_cyc_i;
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
endmodule

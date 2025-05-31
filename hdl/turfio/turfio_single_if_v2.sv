`timescale 1ns / 1ps
`include "interfaces.vh"
// Single TURFIO control interface.
//
// v2 gets rid of lock requests/etc. since we don't need them.
//
// The base control space has 15 bits reserved for it: we slice
// out half of that for the TURFIO space, and we have 4 TURFIO control interfaces.
// We do this "global/individual" split so that we can have a space for global common
// controls. For instance, reading the RDY from the IDELAYCTRLs, resetting the MMCMs,
// etc., both of which are split between 2 TURFIOs.
//
// This module just handles a single TURFIO.
//
// So 14-bits base, 12-bits per TURFIO, so 10 real bits, which should be more than
// enough.
// Note: All CINs + RXCLK are in the same bank.
// COUT/TXCLK can be in a different bank, but they're always in the same one together.
//
// CINs need to use *two* delay chains in order to get a full bit width.
// We don't even use RXCLK because there's functionally no way to do it: I only have
// 2 banks available and not enough MMCMs to do it. I can't even use IDELAYs
// because they don't have the range to cover an 8 ns period.
//
// Seriously, this is ridiculously annoying. And let's not even *talk* about the
// issues with using this in TIME mode. But, it is what it is.
//
// Each bit requires a total of *4* effing delays: 2 ODELAYs (in cascade) and 2 IDELAYs.
// Resets are targeted for each bit.
// We again split the 12-bit space in half (now 11 bits) and split the 11-bit CIN space
// into 8 (address 7 = TURFIO) so 8 bits (6 real bits = 64 total registers)
// The space for each bit becomes:
// 0x00 - 0x7F: control 
// 0x00: bit[0] = rst, bit[1] = EN_VTC
// 0x04: bit error count
// 0x08-0x7C: reserved
// 0x80: Primary IDELAY CNTVALUEINOUT
// 0x84: Primary ODELAY CNTVALUEINOUT
// 0x88: Monitor IDELAY CNTVALUEINOUT
// 0x8C: Monitor ODELAY CNTVALUEINOUT
// 0xC0: capture/bitslip
// 0xC1: round-trip delay (clock phase capture when valid)
// 0xE0: bit error interval load
module turfio_single_if_v2 #(
        parameter [6:0] INV_CIN = {7{1'b0}},
        parameter [6:0] INV_CIN_XB = {7{1'b0}},
        parameter INV_CINTIO = 1'b0,
        parameter INV_CINTIO_XB = 1'b0,
        parameter INV_COUT = 1'b0,
        parameter INV_COUT_XB = 1'b0,
        parameter INV_TXCLK = 1'b0,
        parameter INV_TXCLK_XB = 1'b0,
        parameter CIN_CLKTYPE = "IFCLK67",
        parameter COUT_CLKTYPE = "IFCLK67",
        parameter [7:0] BIT_DEBUG = 8'h00,
        parameter [31:0] TRAIN_VALUE = 32'hA55A6996
        )(
        input clk_i,
        input rst_i,
        `TARGET_NAMED_PORTS_WB_IF(wb_ , 12, 32),

        input cin_clk_i,
        input cin_clk_phase_i,
        input cin_clk_ok_i,
        input cin_rst_i,
        
        input cout_clk_i,
        
        input cin_clk_x2_i,
        input cout_clk_x2_i,        
        input cout_clk_x2_phase_i,
        input [31:0] cout_command_i,
        
        // all of the various CIN output data go here when it's working!!
        output [8*32-1:0] cin_response_o,
        output [7:0] cin_valid_o,
                
        input [6:0] CIN_P,
        input [6:0] CIN_N,
        input CINTIO_P,
        input CINTIO_N,
        output COUT_P,
        output COUT_N,
        output TXCLK_P,
        output TXCLK_N
    );

    localparam [2:0] CIN_OFFSET_DEFAULT = 3'd0;

    // The WISHBONE interface has to cross clock domains:
    // in order to do that, we have to know that the cin clk is running.
    // The CIN clock spaces are being accessed when:
    // bit[11] is high (CIN spaces)
    // bit[7] is high (cin write/readback)
    wire       cin_access;
    
    // This returns which delay we're selecting. Macro to allow using on multiple objects
    `define BIT_NUMBER(x) x[10:8]
    (* CUSTOM_CC_SRC = "PSCLK" *)
    reg [11:0] adr_static = {12{1'b0}};
    (* CUSTOM_CC_SRC = "PSCLK", CUSTOM_CC_DST = "PSCLK" *)
    reg [31:0] dat_reg = {32{1'b0}};
    (* CUSTOM_CC_SRC = "PSCLK" *)
    reg [3:0]  sel_static = {4{1'b0}};
    (* CUSTOM_CC_SRC = "PSCLK" *)
    reg        we_static = 0; 
    
    // Don't use busy, use returned flags so I can delay it.
    // access flag in ifclk domain
    wire       cin_access_ifclk;
    // ack in ifclk domain
    reg [2:0]  cin_ack_ifclk = 0;
    // ack in wbclk domain
    wire       cin_ack_wbclk;
    // done in wbclk domain
    wire       done_wbclk;
    // done in ifclk domain
    wire       done_ifclk;
    
    flag_sync u_cin_access_sync(.in_clkA(cin_access),.out_clkB(cin_access_ifclk),
                                .clkA(clk_i),.clkB(cin_clk_i));
    flag_sync u_cin_ack_sync(.in_clkA(cin_ack_ifclk[2]),.out_clkB(cin_ack_wbclk),
                             .clkA(cin_clk_i),.clkB(clk_i));
    // done *always* goes. it doesn't really matter.
    flag_sync u_done_sync(.in_clkA(done_wbclk),.out_clkB(done_ifclk),
                          .clkA(clk_i),.clkB(cin_clk_i));
    
    // 0x000-0x7FF control
    // 0x800-0x8FF cin0
    // 0x900-0x9FF cin1
    // 0xA00-0xAFF cin2
    // 0xB00-0xBFF cin3
    // 0xC00-0xCFF cin4
    // 0xD00-0xDFF cin5
    // 0xE00-0xEFF cin6
    // 0xF00-0xFFF cintio

    // vectorize the positive inputs
    wire [7:0] in_p = { CINTIO_P, CIN_P };
    // vectorize the negative inputs
    wire [7:0] in_n = { CINTIO_N, CIN_N };
    // combine the inversion parameters
    localparam [7:0] INV_VEC = { INV_CINTIO, INV_CIN };
    localparam [7:0] INV_VEC_XB = { INV_CINTIO_XB, INV_CIN_XB };
    // create a mux of the data from each bit
    wire [31:0] bit_muxed_data[7:0];
    
    // enable cout training
    (* CUSTOM_CC_SRC = "PSCLK" *)
    reg cout_train = 1;
    // resynchronize
    (* CUSTOM_CC_DST = COUT_CLKTYPE, ASYNC_REG = "TRUE" *)
    reg cout_train_resync = 1;
    (* ASYNC_REG = "TRUE" *)
    reg cout_train_ifclk = 1;
    
    // This is just standard now
    (* CUSTOM_CC_SRC = "PSCLK" *)
    reg [2:0] cin_offset = CIN_OFFSET_DEFAULT;
    (* CUSTOM_CC_DST = CIN_CLKTYPE *)
    reg [2:0] cin_offset_ifclk = CIN_OFFSET_DEFAULT;
    
    // Control space has the cout_train control and the offset.
    wire [31:0] control_data = { {16{1'b0}},
                                 { {5{1'b0}}, cin_offset },
                                 {7{1'b0}},cout_train };
    
    // this is our FSM for access
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] ACK = 1;
    localparam [FSM_BITS-1:0] WAIT_ACK_IFCLK = 2;
    reg [FSM_BITS-1:0] state = IDLE;
    // This needs to be a FLAG
    assign cin_access = wb_adr_i[11] && wb_adr_i[7] && wb_cyc_i && wb_stb_i && (state == IDLE);
    assign done_wbclk = (state == ACK);
        
    always @(posedge clk_i) begin
        if (rst_i) state <= IDLE;
        else begin
            case (state)
                IDLE: if (wb_cyc_i && wb_stb_i) begin
                    if (cin_access && cin_clk_ok_i) state <= WAIT_ACK_IFCLK;
                    else state <= ACK;
                end
                ACK: state <= IDLE;
                WAIT_ACK_IFCLK: if (cin_ack_wbclk || !cin_clk_ok_i) state <= ACK;
            endcase
        end
        
        if (state == IDLE && wb_cyc_i && wb_stb_i) begin
            adr_static <= wb_adr_i;
            we_static <= wb_we_i;
            sel_static <= wb_sel_i;
            // dat_reg is handled separately
        end
        
        if ((state == IDLE && wb_cyc_i && wb_stb_i) || (state == WAIT_ACK_IFCLK && (cin_ack_wbclk || !cin_clk_ok_i))) begin
           if (wb_we_i) dat_reg <= wb_dat_i;
           else begin
            if (wb_adr_i[11]) begin
                if (!cin_clk_ok_i) dat_reg <= {32{1'b1}};
                else dat_reg <= bit_muxed_data[`BIT_NUMBER(wb_adr_i)];
            end else dat_reg <= control_data;
           end 
        end
        
        if (wb_cyc_i && wb_stb_i && wb_ack_o && wb_we_i &&
            !wb_adr_i[11]) begin
            if (wb_sel_i[0])
                cout_train <= wb_dat_i[0];
            if (wb_sel_i[1])
                cin_offset <= wb_dat_i[8 +: 3];
        end
    end

    always @(posedge cin_clk_i) begin    
        cin_ack_ifclk <= { cin_ack_ifclk[1:0], cin_access_ifclk };
        if (done_ifclk) cin_offset_ifclk <= cin_offset;
    end
    
    always @(posedge cout_clk_x2_i) begin
        cout_train_resync <= cout_train;
        cout_train_ifclk <= cout_train_resync;
    end
    
    generate
        genvar i;
        for (i=0;i<8;i=i+1) begin : BL
            // THIS IS A GODDAMN DISASTER
                
            // Delays map to the upper space (when adr_i[7] is set) and map as [3:2]: eg 00=00, 04=01, 08=10, 0C=11
            wire [1:0] delay_sel = adr_static[3:2];
            // *this* bit is being accessed when [10:8]==i
            wire this_bit_access = (`BIT_NUMBER(adr_static) == i) && cin_access_ifclk;
            // Delays are loaded any time in the upper space
            wire delay_load = (adr_static[7] && !adr_static[6] && this_bit_access && we_static && sel_static[1] && sel_static[0]);
            // Same for reads
            wire delay_read = (adr_static[7] && !adr_static[6] && this_bit_access && !we_static);
            // Bitslip request. Delay doesn't matter so resync it.
            (* CUSTOM_CC_DST = CIN_CLKTYPE *)
            reg bitslip = 1'b0;
            // Capture request. This needs to be registered because it broadcasts to 32 separate bits,
            // and they all need to grab in the same domain.
            (* CUSTOM_CC_DST = CIN_CLKTYPE *)
            reg capture = 1'b0;
            // Interval load
            (* CUSTOM_CC_DST = CIN_CLKTYPE *)
            reg interval_load = 0;
            // *disable*_vtc for this bit
            reg dis_vtc = 0;
            // local rst for this bit
            reg local_rst = 0;
            // actual reset for this bit
            reg rst = 0;
            // bitslip reset for this bit in WB clk
            (* CUSTOM_CC_SRC = "PSCLK" *)
            reg bitslip_rst = 0;
            // and in ifclk
            (* ASYNC_REG = "TRUE", CUSTOM_CC_DST = CIN_CLKTYPE *)
            reg [1:0] bitslip_rst_ifclk = {2{1'b0}};
            // enable for this bit in WB clk
            (* CUSTOM_CC_SRC = "PSCLK" *)
            reg enable = 0;
            // and in ifclk
            (* ASYNC_REG = "TRUE", CUSTOM_CC_DST = CIN_CLKTYPE *)
            reg [1:0] enable_ifclk = {2{1'b0}};
            
            // count value out
            wire [8:0] this_cntvalueout;
            // expanded
            wire [31:0] cntvalueout_data = { {23{1'b0}}, this_cntvalueout };
            // capture
            wire [31:0] capture_data = cin_response_o[32*i +: 32];
            // Roundtrip delay value
            wire [2:0] cin_roundtrip;
            // Expanded
            wire [31:0] cin_roundtrip_data = { {28{1'b0}}, cin_roundtrip };
            // mux the capture and roundtrip registers
            wire [31:0] capture_data_muxed = (adr_static[2]) ? cin_roundtrip_data : capture_data;
            // CIN clock space data
            wire [31:0] cin_data = (adr_static[6]) ? capture_data_muxed : cntvalueout_data;
            // non-CIN clock space data
            wire [31:0] control_data[1:0];


            ////// BIT ERROR STUFF
            (* CUSTOM_CC_DST = "PSCLK" *)
            reg [24:0] bit_error_count_wbclk = {25{1'b0}};            
            // From IFCLK
            wire [24:0] bit_error_count;
            // Valid in WBCLK
            wire bit_error_count_valid_wbclk;

            // create control reg 0, structured in byte
            assign control_data[0] = { {8{1'b0}},
                                       {8{1'b0}},
                                       {8{1'b0}},
                                       {3{1'b0}}, enable, 1'b0, bitslip_rst, dis_vtc, local_rst };
            // create control reg 1
            assign control_data[1] = { {7{1'b0}}, bit_error_count_wbclk };
            // Output from the serdes
            wire [3:0] serdes_out;           
            // Bit error
            wire biterr;
            
            // control logic
            always @(posedge clk_i) begin : RVT
                if (wb_cyc_i && wb_stb_i && wb_ack_o && (`BIT_NUMBER(wb_adr_i) == i) && !wb_adr_i[7] && wb_we_i && wb_sel_i[0]) begin
                    local_rst <= wb_dat_i[0];
                    dis_vtc <= wb_dat_i[1];
                end
                // Resets affect these bits differently. Basically they're forced high while rst is high
                // and then drop low when it ends.
                if (local_rst || cin_rst_i) begin
                    bitslip_rst <= 1'b1;
                end else if (rst && !local_rst && !cin_rst_i) begin
                    bitslip_rst <= 1'b0;
                end else if (wb_cyc_i && wb_stb_i && wb_ack_o && (`BIT_NUMBER(wb_adr_i) == i) && !wb_adr_i[7] && wb_we_i && wb_sel_i[0]) begin
                    bitslip_rst <= wb_dat_i[2];
                end
                
                if (rst) begin
                    enable <= 1'b0;
                end else if (wb_cyc_i && wb_stb_i && wb_ack_o && (`BIT_NUMBER(wb_adr_i) == i) && !wb_adr_i[7] && wb_we_i && wb_sel_i[0]) begin
                    enable <= wb_dat_i[4]; 
                end                
                rst <= local_rst || cin_rst_i;              
                
                if (bit_error_count_valid_wbclk) bit_error_count_wbclk <= bit_error_count;
            end            

            always @(posedge cin_clk_i) begin
                enable_ifclk <= { enable_ifclk[0], enable };
                bitslip_rst_ifclk <= { bitslip_rst_ifclk[0], bitslip_rst };
                bitslip <= (adr_static[7] && adr_static[6] && !adr_static[5] && this_bit_access && we_static);            
                interval_load <= (adr_static[7] && adr_static[6] && adr_static[5] && this_bit_access && we_static && sel_static[3:0] == 4'hF);
                capture <= (adr_static[7] && adr_static[6] && !adr_static[5] && this_bit_access && !we_static);
            end
            
            assign bit_muxed_data[i] = (wb_adr_i[7]) ? cin_data : control_data[wb_adr_i[2]];            
            turfio_bit #(.INV(INV_VEC[i]),
                         .INV_XB(INV_VEC_XB[i]),
                         .CLKTYPE(CIN_CLKTYPE))
                u_bit( .if_clk_i(cin_clk_i),
                       .if_clk_x2_i(cin_clk_x2_i),
                       .rst_i(rst),
                       .en_vtc_i(!dis_vtc),
                       .delay_load_i(delay_load),
                       .delay_rd_i(delay_read),
                       .delay_sel_i(delay_sel),
                       .delay_cntvaluein_i(dat_reg[8:0]),
                       .delay_cntvalueout_o(this_cntvalueout),
                       .data_o(serdes_out),
                       .CIN_P(in_p[i]),
                       .CIN_N(in_n[i]));
            // NO: We DO NOT NEED lock/lock req for the TURFIO bits!
            // They're synced: we determine that parameter ONCE and it's
            // the EXACT FREAKING SAME every time.
            // The ONLY THING WE NEED is a SINGLE offset.
            turfio_cin_parallel_sync_v2 #(.TRAIN_SEQUENCE(TRAIN_VALUE),
                                       .CLKTYPE(CIN_CLKTYPE),
                                       .DEBUG(BIT_DEBUG[i] == 1'b1 ? "TRUE" : "FALSE"))
                u_cin_sync(.ifclk_i(cin_clk_i),
                           .ifclk_phase_i(cin_clk_phase_i),
                           .rst_bitslip_i(bitslip_rst_ifclk[1]),
                           .cin_i(serdes_out),
                           .offset_i(cin_offset_ifclk),
                           .capture_i(capture),
                           .captured_i(done_ifclk),
                           .bitslip_i(bitslip),
                           .enable_i(enable_ifclk[1]),
                           .cin_parallel_o(cin_response_o[32*i +: 32]),
                           .cin_parallel_valid_o(cin_valid_o[i]),
                           .cin_biterr_o(biterr));
            // And we need the bit error counter.
            reg bit_error_count_valid_rereg = 0;
            wire bit_error_count_valid;
            wire bit_error_count_ack;
            flag_sync u_bit_error_count_valid_sync(.clkA(cin_clk_i),.clkB(clk_i),
                                                   .in_clkA(bit_error_count_valid && !bit_error_count_valid_rereg),
                                                   .out_clkB(bit_error_count_valid_wbclk));
            flag_sync u_bit_error_ack_sync(.clkA(clk_i),.clkB(cin_clk_i),
                                           .in_clkA(bit_error_count_valid_wbclk),
                                           .out_clkB(bit_error_count_ack));                                                   

            always @(posedge cin_clk_i) bit_error_count_valid_rereg <= bit_error_count_valid;
            // this is a CC path for both source/destination
            // dat_reg -> C register (interval)
            // P register -> bit_error_count_wbclk
            dsp_timed_counter #(.MODE("ACKNOWLEDGE"),.CLKTYPE_SRC(CIN_CLKTYPE),.CLKTYPE_DST(CIN_CLKTYPE))
                u_cin_biterr(.clk(cin_clk_i),
                             .rst(bit_error_count_ack),
                             .count_in(biterr),
                             .interval_in(dat_reg[23:0]),
                             .interval_load(interval_load),
                             .count_out(bit_error_count),
                             .count_out_valid(bit_error_count_valid));
        end
    endgenerate
    
    turfio_cout #(.INV_COUT(INV_COUT),
                  .INV_COUT_XB(INV_COUT_XB),
                  .INV_TXCLK(INV_TXCLK),
                  .INV_TXCLK_XB(INV_TXCLK_XB),
                  .TRAIN_VALUE(TRAIN_VALUE))
        u_cout(.if_clk_i(cout_clk_i),
               .if_clk_x2_i(cout_clk_x2_i),
               .if_clk_x2_phase_i(cout_clk_x2_phase_i),
               .cout_command_i(cout_command_i),
               .cout_train_i(cout_train_ifclk),
               .TXCLK_P(TXCLK_P),
               .TXCLK_N(TXCLK_N),
               .COUT_P(COUT_P),
               .COUT_N(COUT_N));

    assign wb_ack_o = (state == ACK);
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    assign wb_dat_o = dat_reg;
    
endmodule

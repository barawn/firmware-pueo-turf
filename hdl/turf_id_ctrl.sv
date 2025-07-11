`timescale 1ns / 1ps
`include "interfaces.vh"
// We have a big address space so let's split it up.
// We have 13 real bits, splitting them up into 9-bit
// dword sections gives us 16 sections, which should
// be enough for future-proofing.
//
// NOPE NOW WE SLICE THIS IN TWO: this gives us
// space for the Ethernet DRP stuff.
//
// 0x0000 - 0x07FF : ID/control/status space, maybe also reprogramming stuff who knows
// 0x0800 - 0x0FFF : Simple clock monitor.
// 0x1000 - 0x18FF : Crate register bridge control and status.
module turf_id_ctrl #(
        parameter [31:0] IDENT = "TURF",
        parameter [31:0] DATEVERSION = {32{1'b0}},
        parameter NUM_CLK_MON = 3,
        localparam NUM_ADDRESS_BITS = 14
    )(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF(wb_ , NUM_ADDRESS_BITS, 32),

        input [3:0] bridge_timeout_i,
        input [3:0] bridge_invalid_i,
        output [7:0] bridge_type_o,        
        
        input [NUM_CLK_MON-1:0] clk_mon_i,
        output [NUM_CLK_MON-1:0] clk_ok_o,
        
        output [2:0] gpo_select_o,
        output gpo_en_o,
        output bitcmd_sync_o
    );
    // Number of section bits (3 for a total of 8 sections
    localparam NUM_SECTION_BITS = 3;
    // Number of sections
    localparam NUM_SECTIONS = (1<<NUM_SECTION_BITS);
    // Section selection
    wire [NUM_SECTION_BITS-1:0] section = wb_adr_i[NUM_ADDRESS_BITS-NUM_SECTION_BITS +: NUM_SECTION_BITS];
    // these are the maximum dword bits
    localparam MAX_DWORD_BITS = 13;
    // number of dword address bits for id_statctrl section
    localparam ID_STATCTRL_ADR_BITS = 2;
    // number of registers for id_statctrl section
    localparam ID_STATCTRL_REGS = (1<<ID_STATCTRL_ADR_BITS);
    // simplified id_statctrl_adr so we can write addresses equivalent to their true addresses
    wire [NUM_ADDRESS_BITS-1:0] id_statctrl_adr = { {(MAX_DWORD_BITS-ID_STATCTRL_ADR_BITS){1'b0}}, 
        wb_adr_i[2 +: ID_STATCTRL_ADR_BITS],2'b00};    
    wire [31:0] id_statctrl[ID_STATCTRL_REGS-1:0];
    wire dna_data;
    reg [31:0] statctrl_reg = {32{1'b0}};
    (* CUSTOM_CC_SRC = "PSCLK" *)
    reg bitcmd_sync = 0;
    (* CUSTOM_CC_SRC = "PSCLK" *)
    reg [2:0] gpo_select = {3{1'b0}};
    (* CUSTOM_CC_SRC = "PSCLK" *)
    reg gpo_en = 1'b0;
    
    assign id_statctrl[0] = IDENT;
    assign id_statctrl[1] = DATEVERSION;
    assign id_statctrl[2] = { {31{1'b0}}, dna_data };
    assign id_statctrl[3] = statctrl_reg;
    localparam [NUM_SECTION_BITS-1:0] ID_STATCTRL_SECTION = 0;
    wire id_statctrl_sel = 
        (section == ID_STATCTRL_SECTION);

    // Statctrl ack reg. Catch-all ack: this goes even if the section isn't addressed
    reg id_statctrl_ack_ff = 0;
    // Statctrl ack reg qualified (to ensure it's never active when wb_cyc_i is not
    wire id_statctrl_ack = (id_statctrl_ack_ff && wb_cyc_i);
    
    // DNA parameters
    reg dna_shift = 0;
    reg dna_read = 0;
    reg [31:0] id_statctrl_dat_ff = {32{1'b0}};
    
    // clock monitor output data    
    wire [31:0] clockmon_dat;
    // clock monitor output ack
    wire        clockmon_ack;
    // identifier for clockmon section
    localparam [NUM_SECTION_BITS-1:0] CLOCKMON_SECTION = 1;
    // enable for clockmon
    wire        clockmon_en = (wb_cyc_i && wb_stb_i && section == CLOCKMON_SECTION);
    // number of adr bits for clockmon
    localparam  CLOCKMON_ADR_BITS = $clog2(NUM_CLK_MON);
    // clockmon address stripped from full address
    wire [CLOCKMON_ADR_BITS-1:0] clockmon_adr = (wb_adr_i[2 +: CLOCKMON_ADR_BITS]);

    // bridge ctrl section
    localparam [NUM_SECTION_BITS-1:0] BRIDGECTL_SECTION = 2;
    localparam BRIDGECTL_ADR_BITS = 2;
    wire [31:0] bridgectl_regs[3:0];
    wire [31:0] bridgectl_dat = bridgectl_regs[wb_adr_i[2 +: BRIDGECTL_ADR_BITS]];
    reg bridgectl_ack_ff = 0;
    wire        bridgectl_ack = bridgectl_ack_ff;
    wire        bridgectl_en = (wb_cyc_i && wb_stb_i && section == BRIDGECTL_SECTION);
    wire [NUM_ADDRESS_BITS-1:0] bridgectl_adr = { {(MAX_DWORD_BITS-BRIDGECTL_ADR_BITS){1'b0}}, 
        wb_adr_i[2 +: BRIDGECTL_ADR_BITS],2'b00};    

    // a bridge error was seen (access to disabled bridge)
    reg [3:0] bridge_err_seen = 0;
    // a bridge timeout occurred
    reg [3:0] bridge_timeout_seen = 0;
    // select which bridge to use
    reg [7:0] bridge_type = {8{1'b0}};
    // the remaining 2 registers are unused
    assign bridgectl_regs[0] = { 6'h00, bridge_type[6 +: 2],
                                 6'h00, bridge_type[4 +: 2],
                                 6'h00, bridge_type[2 +: 2],
                                 6'h00, bridge_type[0 +: 2] };

    assign bridgectl_regs[1] = { {24{1'b0}}, bridge_err_seen, bridge_timeout_seen };
    assign bridgectl_regs[2] = bridgectl_regs[0];
    assign bridgectl_regs[3] = bridgectl_regs[1];
        
    
    // demux sections. This is designed to simplify decoder. Note that we use id_statctrl_ack
    // as a catch-all ack since it always goes, regardless of whether or not a section is addressed
    
    // acks from each section go here (use id_statctrl_ack for unused sections)
    wire [NUM_SECTIONS-1:0] section_ack;
    // data from each section goes here. Choose based on decoder simplicity
    wire [31:0] section_dat[NUM_SECTIONS-1:0];
        
    // this section is huge because I don't feel like putting it in a
    // generate loop        
    assign section_ack[0] = id_statctrl_ack;
    assign section_dat[0] = id_statctrl_dat_ff;
    assign section_ack[1] = clockmon_ack;
    assign section_dat[1] = clockmon_dat;
    assign section_ack[2] = bridgectl_ack;
    assign section_dat[2] = bridgectl_dat;
    // unused acks
    assign section_ack[3] = section_ack[0];
    assign section_ack[4] = section_ack[0];
    assign section_ack[5] = section_ack[0];
    assign section_ack[6] = section_ack[0];
    assign section_ack[7] = section_ack[0];
    // unused dats
    assign section_dat[3] = section_dat[1];
    assign section_dat[4] = section_dat[0];
    assign section_dat[5] = section_dat[1];
    assign section_dat[6] = section_dat[0];
    assign section_dat[7] = section_dat[1];
    
    // logic section  
    integer br;  
    always @(posedge wb_clk_i) begin
    
        dna_shift <= (wb_cyc_i && wb_stb_i && wb_ack_o && id_statctrl_sel && id_statctrl_adr == 15'h0008 && !wb_we_i);
        dna_read <= (wb_cyc_i && wb_stb_i && wb_ack_o && id_statctrl_sel && id_statctrl_adr == 15'h0008 && wb_we_i && wb_dat_i[31]);
        // NOTE: id_statctrl is a *catch-all* ack. We don't qualify its address
        id_statctrl_ack_ff <= wb_cyc_i && wb_stb_i;
        
        id_statctrl_dat_ff <= id_statctrl[ id_statctrl_adr[2 +: ID_STATCTRL_ADR_BITS] ];        

        if (wb_cyc_i && wb_stb_i && wb_ack_o && id_statctrl_sel && id_statctrl_adr== 15'h000C && wb_we_i) begin
           if (wb_sel_i[0]) statctrl_reg[0] <= wb_dat_i[0];
           if (wb_sel_i[1]) begin
                statctrl_reg[8 +: 3] <= wb_dat_i[8 +: 3];
                statctrl_reg[15] <= wb_dat_i[15];
           end                
        end
        
        bitcmd_sync <= statctrl_reg[0];
        gpo_select <= statctrl_reg[8 +: 3];
        gpo_en <= statctrl_reg[15];

        bridgectl_ack_ff <= wb_cyc_i && wb_stb_i && bridgectl_en;
        
        if (wb_cyc_i && wb_stb_i && wb_ack_o && bridgectl_en && bridgectl_adr == 15'h0000 && wb_we_i) begin
            if (wb_sel_i[0]) bridge_type[0 +: 2] <= wb_dat_i[0 +: 2];
            if (wb_sel_i[1]) bridge_type[2 +: 2] <= wb_dat_i[8 +: 2];
            if (wb_sel_i[2]) bridge_type[4 +: 2] <= wb_dat_i[16 +: 2];
            if (wb_sel_i[3]) bridge_type[6 +: 2] <= wb_dat_i[24 +: 2];
        end
        
        if (wb_cyc_i && wb_stb_i && wb_ack_o && bridgectl_en && bridgectl_adr == 15'h0004 && wb_we_i) begin
            bridge_timeout_seen <= 4'h0;
            bridge_err_seen <= 4'h0;
        end else begin
            for (br=0;br<4;br=br+1) begin
                if (bridge_timeout_i[br]) bridge_timeout_seen[br] <= 1'b1;
                if (bridge_invalid_i[br]) bridge_err_seen[br] <= 1'b1;
            end
        end
    end
    (* CUSTOM_DNA_VER = DATEVERSION *)
    DNA_PORTE2 u_dna(.DIN(1'b0),.READ(dna_read),.SHIFT(dna_shift),.CLK(wb_clk_i),.DOUT(dna_data));
        
    simple_clock_mon #(.NUM_CLOCKS(NUM_CLK_MON))
        u_clkmon( .clk_i(wb_clk_i),
                  .adr_i(clockmon_adr),
                  .en_i(clockmon_en),
                  .wr_i(wb_we_i),
                  .dat_i(wb_dat_i),
                  .dat_o(clockmon_dat),
                  .ack_o(clockmon_ack),
                  .clk_running_o(clk_ok_o),
                  .clk_mon_i(clk_mon_i));    
    // The first bit in the section bit list is NUM_ADDRESS_BITS-NUM_SECTION_BITS
    assign wb_ack_o = section_ack[section];
    assign wb_dat_o = section_dat[section];
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;

    assign bitcmd_sync_o = bitcmd_sync;
    assign bridge_type_o = bridge_type;
    
    assign gpo_select_o = gpo_select;
    assign gpo_en_o = gpo_en;
    
endmodule

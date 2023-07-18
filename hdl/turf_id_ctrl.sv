`timescale 1ns / 1ps
`include "interfaces.vh"
// We have a big address space so let's split it up.
// We have 13 real bits, splitting them up into 9-bit
// dword sections gives us 16 sections, which should
// be enough for future-proofing.
//
// 0x0000 - 0x07FF : ID/control/status space, maybe also reprogramming stuff who knows
// 0x0800 - 0x0FFF : Simple clock monitor.
// 0x1000 - 0x7FFF : reserved
module turf_id_ctrl #(
        parameter [31:0] IDENT = "TURF",
        parameter [31:0] DATEVERSION = {32{1'b0}},
        parameter NUM_CLK_MON = 3,
        localparam NUM_ADDRESS_BITS = 15
    )(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF(wb_ , NUM_ADDRESS_BITS, 32),
        
        input [NUM_CLK_MON-1:0] clk_mon_i,
        output [NUM_CLK_MON-1:0] clk_ok_o
    );
    // Number of section bits (4 for a total of 16 sections
    localparam NUM_SECTION_BITS = 4;
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
    // unused acks
    assign section_ack[2] = section_ack[0];
    assign section_ack[3] = section_ack[0];
    assign section_ack[4] = section_ack[0];
    assign section_ack[5] = section_ack[0];
    assign section_ack[6] = section_ack[0];
    assign section_ack[7] = section_ack[0];
    assign section_ack[8] = section_ack[0];
    assign section_ack[9] = section_ack[0];
    assign section_ack[10]= section_ack[0];
    assign section_ack[11]= section_ack[0];
    assign section_ack[12]= section_ack[0];
    assign section_ack[13]= section_ack[0];
    assign section_ack[14]= section_ack[0];
    assign section_ack[15]= section_ack[0];
    // unused dats
    assign section_dat[2] = section_dat[0];
    assign section_dat[3] = section_dat[1];
    assign section_dat[4] = section_dat[0];
    assign section_dat[5] = section_dat[1];
    assign section_dat[6] = section_dat[0];
    assign section_dat[7] = section_dat[1];
    assign section_dat[8] = section_dat[0];
    assign section_dat[9] = section_dat[1];
    assign section_dat[10]= section_dat[0];
    assign section_dat[11]= section_dat[1];
    assign section_dat[12]= section_dat[0];
    assign section_dat[13]= section_dat[1];
    assign section_dat[14]= section_dat[0];
    assign section_dat[15]= section_dat[1];
    
    // logic section    
    always @(posedge wb_clk_i) begin
        dna_shift <= (wb_cyc_i && wb_stb_i && wb_ack_o && id_statctrl_sel && id_statctrl_adr == 15'h008 && !wb_we_i);
        dna_read <= (wb_cyc_i && wb_stb_i && wb_ack_o && id_statctrl_sel && id_statctrl_adr == 15'h008 && wb_we_i && wb_dat_i[31]);
        // NOTE: id_statctrl is a *catch-all* ack. We don't qualify its address
        id_statctrl_ack_ff <= wb_cyc_i && wb_stb_i;
        
        id_statctrl_dat_ff <= id_statctrl[ id_statctrl_adr[2 +: ID_STATCTRL_ADR_BITS] ];        
    end
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
    
endmodule

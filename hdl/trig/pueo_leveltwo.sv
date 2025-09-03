`timescale 1ns / 1ps
// L2 trigger has multiple versions in it for testing.
// V1 mimics the original trigger. It adds a few clocks of latency,
// which we have to correct for in the metadata collection later.
// Also means we have to adjust the lookback time as well, but who cares,
// that's programmable.
module pueo_leveltwo #(parameter VERSION = 1)(
        input clk_i,
        input ce_i,
        input [7:0] tio0_trig_i,
        input [7:0] tio1_trig_i,
        input [7:0] tio2_trig_i,
        input [7:0] tio3_trig_i,
        input [63:0] tio0_meta_i,
        input [63:0] tio1_meta_i,
        input [63:0] tio2_meta_i,
        input [63:0] tio3_meta_i,
        input holdoff_i,
        input dead_i,
        
        output [63:0] tio0_meta_o,
        output [63:0] tio1_meta_o,
        output [63:0] tio2_meta_o,
        output [63:0] tio3_meta_o,
        output trig_o
    );
    // normally trigger would just be or of everyone, so next sysclk_x2_ce
    // here aux/leveltwo/lf are formed in sysclk_x2_ce
    // then the trig occurs, so meta delay is 1.
    localparam META_DELAY = (VERSION == 1) ? 1 : 1;

    reg [META_DELAY-1:0][63:0] tio0_meta_hold = {64*META_DELAY{1'b0}};
    reg [META_DELAY-1:0][63:0] tio1_meta_hold = {64*META_DELAY{1'b0}};
    reg [META_DELAY-1:0][63:0] tio2_meta_hold = {64*META_DELAY{1'b0}};
    reg [META_DELAY-1:0][63:0] tio3_meta_hold = {64*META_DELAY{1'b0}};

    wire [META_DELAY-1:0][63:0] tio0_meta_shift = 
        (META_DELAY > 1) ? { tio0_meta_hold[64 +: 64*(META_DELAY-1)], tio0_meta_i } :
                             tio0_meta_i;
    wire [META_DELAY-1:0][63:0] tio1_meta_shift = 
        (META_DELAY > 1) ? { tio1_meta_hold[64 +: 64*(META_DELAY-1)], tio1_meta_i } :
                             tio1_meta_i;
    wire [META_DELAY-1:0][63:0] tio2_meta_shift = 
        (META_DELAY > 1) ? { tio2_meta_hold[64 +: 64*(META_DELAY-1)], tio2_meta_i } :
                             tio2_meta_i;
    wire [META_DELAY-1:0][63:0] tio3_meta_shift = 
        (META_DELAY > 1) ? { tio3_meta_hold[64 +: 64*(META_DELAY-1)], tio3_meta_i } :
                             tio3_meta_i;
    
    always @(posedge clk_i) begin
        if (ce_i) begin
            tio0_meta_hold <= tio0_meta_shift;
            tio1_meta_hold <= tio1_meta_shift;
            tio2_meta_hold <= tio2_meta_shift;
            tio3_meta_hold <= tio3_meta_shift;
        end
    end
    
            
    reg aux_trig = 0;
    // there are always two leveltwos, one for each polarity
    reg [1:0] leveltwo_trig = 2'b00;
    // and pointlessly two lf trigs as well
    reg [1:0] lf_trig = 2'b00;
    
    reg master_trig = 0;
    
    wire [3:0] aux_triggers = { tio3_trig_i[7],
                                tio2_trig_i[7],
                                tio1_trig_i[7],
                                tio0_trig_i[7] };
    // Aux trig's the same for both versions.
    always @(posedge clk_i) begin
        if (ce_i) aux_trig <= |aux_triggers;
    end

    generate
        if (VERSION == 2) begin : V2
            assign trig_o = 1'b0;
        end else begin : V1
            always @(posedge clk_i) begin : V1P
                if (ce_i) leveltwo_trig[0] <= (|tio0_trig_i[5:0]) || (|tio1_trig_i[5:0]);
                if (ce_i) leveltwo_trig[1] <= (|tio2_trig_i[5:0]) || (|tio3_trig_i[5:0]);
                if (ce_i) lf_trig[0] <= tio0_trig_i[6] || tio1_trig_i[6];
                if (ce_i) lf_trig[1] <= tio2_trig_i[6] || tio2_trig_i[6];
                
                master_trig <= (!holdoff_i && !dead_i) && ce_i && (aux_trig || (|leveltwo_trig) || (|lf_trig));
            end
            assign trig_o = master_trig;
        end
    endgenerate

    assign tio0_meta_o = tio0_meta_hold[(META_DELAY-1)*64 +: 64];
    assign tio1_meta_o = tio1_meta_hold[(META_DELAY-1)*64 +: 64];
    assign tio2_meta_o = tio2_meta_hold[(META_DELAY-1)*64 +: 64];
    assign tio3_meta_o = tio3_meta_hold[(META_DELAY-1)*64 +: 64];
    
endmodule

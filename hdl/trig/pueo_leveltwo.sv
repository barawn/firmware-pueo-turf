`timescale 1ns / 1ps
// L2 trigger has multiple versions in it for testing.
// V1 mimics the original trigger. It adds a few clocks of latency,
// which we have to correct for in the metadata collection later.
// Also means we have to adjust the lookback time as well, but who cares,
// that's programmable.

`include "dsp_macros.vh"

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
        
        // individual leveltwo scalers
        output [23:0] leveltwo_o,
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
        (META_DELAY > 1) ? { tio0_meta_hold[META_DELAY-2:0], tio0_meta_i } :
                             tio0_meta_i;
    wire [META_DELAY-1:0][63:0] tio1_meta_shift = 
        (META_DELAY > 1) ? { tio1_meta_hold[META_DELAY-2:0], tio1_meta_i } :
                             tio1_meta_i;
    wire [META_DELAY-1:0][63:0] tio2_meta_shift = 
        (META_DELAY > 1) ? { tio2_meta_hold[META_DELAY-2:0], tio2_meta_i } :
                             tio2_meta_i;
    wire [META_DELAY-1:0][63:0] tio3_meta_shift = 
        (META_DELAY > 1) ? { tio3_meta_hold[META_DELAY-2:0], tio3_meta_i } :
                             tio3_meta_i;
    
    always @(posedge clk_i) begin
        if (ce_i) begin
            tio0_meta_hold <= tio0_meta_shift;
            tio1_meta_hold <= tio1_meta_shift;
            tio2_meta_hold <= tio2_meta_shift;
            tio3_meta_hold <= tio3_meta_shift;
        end
    end
    
    reg [3:0] por_holdoff_shreg = {4{1'b0}};
    wire por_done = por_holdoff_shreg[3];
            
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
        
        por_holdoff_shreg <= {por_holdoff_shreg[2:0], 1'b1};
    end

    generate
        if (VERSION == 2) begin : V2
            localparam COINCIDENCE_WINDOW = 2;
            
            // number of polarizations
            localparam NPOL = 2;
            // number of surf sectors
            localparam NSURFSECT = 12;
            // number of regions/surf
            localparam NREGION = 4;            
                        
            localparam HPOL = 0;
            localparam VPOL = 1;
            // these are by surf sector
            wire [NPOL-1:0][NSURFSECT*NREGION-1:0] meta_low_in;
            wire [NPOL-1:0][NSURFSECT*NREGION-1:0] meta_high_in;
            
            wire [NPOL-1:0] leveltwo_trigger;
            wire [NPOL-1:0][47:0] leveltwo_scaler;
              
            reg [NPOL*NSURFSECT-1:0] leveltwo_scaler_ff = {NPOL*NSURFSECT{1'b0}};
            assign leveltwo_o = leveltwo_scaler_ff;
                        
            wire [3:0][47:0] meta;
            assign meta[0] = tio0_meta_i;
            assign meta[1] = tio1_meta_i;
            assign meta[2] = tio2_meta_i;
            assign meta[3] = tio3_meta_i;
            
            // mappity mappy
            genvar i, pol;
            for (i=0;i<12;i=i+1) begin : IN
                always @(posedge clk_i) begin : SCL
                    // adding the ce qual makes it a flag
                    leveltwo_scaler_ff[NSURFSECT*HPOL+i] <= |leveltwo_scaler[HPOL][4*i +: 4] && ce_i;
                    leveltwo_scaler_ff[NSURFSECT*VPOL+i] <= |leveltwo_scaler[VPOL][4*i +: 4] && ce_i;
                end
                // hpol sector (turfio/slots) go
                // 0/5, 0/4, 0/3, 0/2, 0/1, 0/0, 1/0, 1/1, 1/2, 1/3, 1/4, 1/5
                // vpol sector (turfio/slots) go
                // 3/5, 3/4, 3/3, 3/2, 3/1, 3/0, 2/0, 2/1, 2/2, 2/3, 2/4, 2/5
                assign meta_low_in[HPOL][4*i +: 4] = (i < 6) ?
                    (meta[0][8*(5-i) +: 4]) : (meta[1][8*(i-6) +: 4]);
                assign meta_low_in[VPOL][4*i +: 4] = (i < 6) ?
                    (meta[3][8*(5-i) +: 4]) : (meta[2][8*(i-6) +: 4]);

                assign meta_high_in[HPOL][4*i +: 4] = (i < 6) ?
                    (meta[0][8*(5-i) +: 4]) : (meta[1][8*(i-6)+4 +: 4]);
                assign meta_high_in[VPOL][4*i +: 4] = (i < 6) ?
                    (meta[3][8*(5-i) +: 4]) : (meta[2][8*(i-6)+4 +: 4]);
            end
            
            // We now have the metadata mapped into SURF sectors.
            // These feed into DSPs just for convenience: the DSPs
            // generate ((AB)z^-2 | (C)z^-1)z^-1
            // Those outputs then feed into another DSP which does
            // AB & C to generate the trigger. We can't cascade
            // the DSPs here unfortunately since the delays won't work.
            // We also can't use the DSP macro because, shock, it
            // doesn't have the logic operations either!
            for (pol=0;pol<NPOL;pol=pol+1) begin : PL
                wire [47:0] dspA_AB = meta_low_in[pol];
                wire [47:0] dspA_C = meta_low_in[pol];
                wire [47:0] meta_low_stretched;

                wire [47:0] dspB_AB = meta_high_in[pol];
                wire [47:0] dspB_C = meta_high_in[pol];
                wire [47:0] meta_high_stretched;
                wire [47:0] meta_high_stretched_rotated =
                    { meta_high_stretched[3:0], meta_high_stretched[47:4] };

                wire [47:0] dspC_AB = meta_low_stretched;
                wire [47:0] dspC_C = meta_high_stretched_rotated;
                wire not_leveltwo_trigger;
                assign leveltwo_trigger[pol] = !not_leveltwo_trigger;

                // We want X OR Z which requires ALUMODE 1100
                // and OPMODE[3:2] = 10, to select Y_OPMODE_MINUS1
                DSP48E2 #(`NO_MULT_ATTRS,
                          `DE2_UNUSED_ATTRS,
                          .AREG(2),
                          .BREG(2),
                          .CREG(1),
                          .PREG(1),
                          `CONSTANT_MODE_ATTRS )
                          u_dspA( .A( `DSP_AB_A( dspA_AB ) ),
                                  .B( `DSP_AB_B( dspA_AB ) ),
                                  .C( dspA_C ),
                                  .P( meta_low_stretched ),
                                  .ALUMODE(4'b1100),
                                  .OPMODE( { `W_OPMODE_0, `Z_OPMODE_C, `Y_OPMODE_MINUS1, `X_OPMODE_AB } ),
                                  .CLK( clk_i ),
                                  .CEA1( ce_i ),
                                  .CEA2( ce_i ),
                                  .CEB1( ce_i ),
                                  .CEB2( ce_i ),
                                  .CEC( ce_i ),
                                  .CEP( ce_i ));
                DSP48E2 #(`NO_MULT_ATTRS,
                          `DE2_UNUSED_ATTRS,
                          .AREG(2),
                          .BREG(2),
                          .CREG(1),
                          .PREG(1),
                          `CONSTANT_MODE_ATTRS )
                          u_dspB( .A( `DSP_AB_A( dspB_AB ) ),
                                  .B( `DSP_AB_B( dspB_AB ) ),
                                  .C( dspB_C ),
                                  .P( meta_high_stretched ),
                                  .ALUMODE(4'b1100),
                                  .OPMODE( { `W_OPMODE_0, `Z_OPMODE_C, `Y_OPMODE_MINUS1, `X_OPMODE_AB } ),
                                  .CLK( clk_i ),
                                  .CEA1( ce_i ),
                                  .CEA2( ce_i ),
                                  .CEB1( ce_i ),
                                  .CEB2( ce_i ),
                                  .CEC( ce_i ),
                                  .CEP( ce_i ));
                DSP48E2 #(`NO_MULT_ATTRS,
                          `DE2_UNUSED_ATTRS,
                          .AREG(1),
                          .BREG(1),
                          .CREG(1),
                          .PREG(1),
                          .USE_PATTERN_DETECT("PATDET"),
                          .SEL_PATTERN("PATTERN"),
                          .SEL_MASK("MASK"),
                          .MASK( {48{1'b0}} ),
                          .PATTERN( {48{1'b0}} ),
                          `CONSTANT_MODE_ATTRS )
                          u_dspC( .A( `DSP_AB_A( dspC_AB ) ),
                                  .B( `DSP_AB_B( dspC_AB ) ),
                                  .C( dspC_C ),
                                  .P( leveltwo_scaler[pol] ),
                                  .PATTERNDETECT( not_leveltwo_trigger ),
                                  .ALUMODE(4'b1100),
                                  .OPMODE( { `W_OPMODE_0, `Z_OPMODE_C, `Y_OPMODE_MINUS1, `X_OPMODE_AB } ),
                                  .CLK( clk_i ),
                                  .CEA2( ce_i ),
                                  .CEB2( ce_i ),
                                  .CEC( ce_i ),
                                  .CEP( ce_i ));                                  
            end
            
            always @(posedge clk_i) begin : V2P
                // First deal with the LF trigs. They're automatic.
                // NOTE NOTE NOTE NOTE!!! THESE NEED TO BE DELAYED
                // TO MATCH UP WITH THE RF TRIGS ABOVE!!
                if (ce_i) lf_trig[0] <= tio0_trig_i[6] || tio1_trig_i[6];
                if (ce_i) lf_trig[1] <= tio2_trig_i[6] || tio3_trig_i[6];
                // actual leveltwos. por_done prevents them from going when the DSP's pattern reg starts at 0.
                if (ce_i) leveltwo_trig[0] <= leveltwo_trigger[0] && por_done;
                if (ce_i) leveltwo_trig[1] <= leveltwo_trigger[1] && por_done;
                
                master_trig <= (!holdoff_i && !dead_i) && ce_i &&
                        ( aux_trig || (|leveltwo_trig) || (|lf_trig) );
            end
            assign trig_o = master_trig;
        end else begin : V1
            always @(posedge clk_i) begin : V1P
                if (ce_i) leveltwo_trig[0] <= (|tio0_trig_i[5:0]) || (|tio1_trig_i[5:0]);
                if (ce_i) leveltwo_trig[1] <= (|tio2_trig_i[5:0]) || (|tio3_trig_i[5:0]);
                if (ce_i) lf_trig[0] <= tio0_trig_i[6] || tio1_trig_i[6];
                if (ce_i) lf_trig[1] <= tio2_trig_i[6] || tio3_trig_i[6];
                
                master_trig <= (!holdoff_i && !dead_i) && ce_i && (aux_trig || (|leveltwo_trig) || (|lf_trig));
            end
            assign trig_o = master_trig;
        end
    endgenerate

    assign tio0_meta_o = tio0_meta_hold[(META_DELAY-1)];
    assign tio1_meta_o = tio1_meta_hold[(META_DELAY-1)];
    assign tio2_meta_o = tio2_meta_hold[(META_DELAY-1)];
    assign tio3_meta_o = tio3_meta_hold[(META_DELAY-1)];
    
endmodule

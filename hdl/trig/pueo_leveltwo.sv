`timescale 1ns / 1ps
// L2 trigger has multiple versions in it for testing.
// V1 mimics the original trigger. It adds a few clocks of latency,
// which we have to correct for in the metadata collection later.
// Also means we have to adjust the lookback time as well, but who cares,
// that's programmable.

`include "dsp_macros.vh"

module pueo_leveltwo #(parameter VERSION = 1,
                       parameter DEBUG = "TRUE")(
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
        
        input logictype_i,
        input rf_en_i,
        input [27:0] mask_i,
                
        output [63:0] tio0_meta_o,
        output [63:0] tio1_meta_o,
        output [63:0] tio2_meta_o,
        output [63:0] tio3_meta_o,
        
        // individual leveltwo scalers
        output [23:0] leveltwo_o,
        output [1:0] mie_o,
        output [1:0] lf_o,
        output aux_o,
        output levelthree_o,
        // actual trigger
        output trig_o
    );
    // normally trigger would just be or of everyone, so next sysclk_x2_ce
    // here aux/leveltwo/lf are formed in sysclk_x2_ce
    // then the trig occurs, so meta delay is 1.
    localparam META_DELAY = (VERSION == 1) ? 1 : 6;

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
            localparam NON_MIE_DELAY = 3;
            localparam [3:0] NMADDR = NON_MIE_DELAY-2;

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

            (* CUSTOM_MC_SRC_TAG = "LEVELTWO_SCAL", CUSTOM_MC_MIN = "0.0", CUSTOM_MC_MAX = "2.0" *)
            reg [NPOL*NSURFSECT-1:0] leveltwo_scaler_ff = {NPOL*NSURFSECT{1'b0}};
            reg [NPOL*NSURFSECT-1:0] leveltwo_scaler_r = {NPOL*NSURFSECT{1'b0}};
            reg [NPOL*NSURFSECT-1:0] leveltwo_scaler_rr = {NPOL*NSURFSECT{1'b0}};
            assign leveltwo_o = leveltwo_scaler_ff;
                        
            wire [3:0][47:0] meta;
            assign meta[0] = tio0_meta_i;
            assign meta[1] = tio1_meta_i;
            assign meta[2] = tio2_meta_i;
            assign meta[3] = tio3_meta_i;
            
            if (DEBUG == "TRUE") begin : ILA
                leveltwo_ila u_ila(.clk(clk_i),
                                   .probe0(tio0_trig_i),
                                   .probe1(tio1_trig_i),
                                   .probe2(tio0_meta_i),
                                   .probe3(tio1_meta_i),
                                   .probe4(leveltwo_o),
                                   .probe5(ce_i),
                                   .probe6(trig_o));
            end
            
            // mappity mappy
            genvar i, pol;
            for (i=0;i<12;i=i+1) begin : IN
                // OK, we 
                always @(posedge clk_i) begin : SCL
                    // reregister and create a rising edge detection for sysclk
                    if (ce_i) begin
                        leveltwo_scaler_r[NSURFSECT*HPOL+i] <= |leveltwo_scaler[HPOL][4*i +: 4];
                        leveltwo_scaler_rr[NSURFSECT*HPOL+i] <= leveltwo_scaler_r[NSURFSECT*HPOL+i];
                        leveltwo_scaler_ff[NSURFSECT*HPOL+i] <= leveltwo_scaler_r[NSURFSECT*HPOL+i] && !leveltwo_scaler_rr[NSURFSECT*HPOL+i];
                        // reregister and create a rising edge detection.
                        leveltwo_scaler_r[NSURFSECT*VPOL+i] <= |leveltwo_scaler[VPOL][4*i +: 4];
                        leveltwo_scaler_rr[NSURFSECT*VPOL+i] <= leveltwo_scaler_r[NSURFSECT*VPOL+i];
                        leveltwo_scaler_ff[NSURFSECT*VPOL+i] <= leveltwo_scaler_r[NSURFSECT*VPOL+i] && !leveltwo_scaler_rr[NSURFSECT*VPOL+i];
                    end
                end
                // hpol sector (turfio/slots) go
                //  0   1    2    3    4    5    6    7    8    9   10    11
                // 0/5, 0/4, 0/3, 0/2, 0/1, 0/0, 1/0, 1/1, 1/2, 1/3, 1/4, 1/5
                // vpol sector (turfio/slots) go
                // 3/5, 3/4, 3/3, 3/2, 3/1, 3/0, 2/0, 2/1, 2/2, 2/3, 2/4, 2/5
                assign meta_low_in[HPOL][4*i +: 4] = (i < 6) ?
                    (meta[0][8*(5-i) +: 4]) : (meta[1][8*(i-6) +: 4]);
                assign meta_low_in[VPOL][4*i +: 4] = (i < 6) ?
                    (meta[3][8*(5-i) +: 4]) : (meta[2][8*(i-6) +: 4]);

                assign meta_high_in[HPOL][4*i +: 4] = (i < 6) ?
                    (meta[0][8*(5-i)+4 +: 4]) : (meta[1][8*(i-6)+4 +: 4]);
                assign meta_high_in[VPOL][4*i +: 4] = (i < 6) ?
                    (meta[3][8*(5-i)+4 +: 4]) : (meta[2][8*(i-6)+4 +: 4]);
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

                wire [47:0] dspA_to_C;
                
                wire [47:0] dspC_AB = meta_high_stretched_rotated;
                // Note that the masks here only go from [23:0].
                // mask[26] is then LF 
                wire [47:0] dspC_C = { {4{mask_i[12*pol + 11]}},
                                       {4{mask_i[12*pol + 10]}},
                                       {4{mask_i[12*pol + 09]}},
                                       {4{mask_i[12*pol + 08]}},
                                       {4{mask_i[12*pol + 07]}},
                                       {4{mask_i[12*pol + 06]}},
                                       {4{mask_i[12*pol + 05]}},
                                       {4{mask_i[12*pol + 04]}},
                                       {4{mask_i[12*pol + 03]}},
                                       {4{mask_i[12*pol + 02]}},
                                       {4{mask_i[12*pol + 01]}},
                                       {4{mask_i[12*pol + 00]}} };

                wire not_leveltwo_trigger;
                assign leveltwo_trigger[pol] = !not_leveltwo_trigger;

                wire [8:0] dspC_OPMODE;
                assign dspC_OPMODE[8:7] = `W_OPMODE_0;
                assign dspC_OPMODE[6:4] = `Z_OPMODE_PCIN;
                // switches between Y_OPMODE_MINUS1 and Y_OPMODE_0 which
                // switches between AND (=0) and OR (=1).
                assign dspC_OPMODE[3:2] = { logictype_i, 1'b0 };
                assign dspC_OPMODE[1:0] = `X_OPMODE_AB;
                
                // We want X OR Z which requires ALUMODE 1100
                // and OPMODE[3:2] = 10, to select Y_OPMODE_MINUS1
                
                // CHANGE OF PLANS: dspA chains up to dsp C.
                // dspB generates meta_high_stretched and we rotate it
                // in the connection over.
                // We handle this by toggling the ce input:
                // the A/B capture happens in !ce_i, so we get
                // clk  ce  dspA_out    dspB_out    dspC Z input dspC X input dspC P output
                // 0    1   X           X           X            X            X
                // 1    0   A_CLK0      B_CLK0      A_CLK0       X            X
                // 2    1   A_CLK0      B_CLK0      A_CLK0       B_CLK0       X
                // 3    0   A_CLK1      B_CLK1      A_CLK1       B_CLK0       A_CLK0 & B_CLK0
                // 4    1   A_CLK1      B_CLK1      A_CLK1       B_CLK1       A_CLK0 & B_CLK0
                // 5    0   A_CLK2      B_CLK2      A_CLK2       B_CLK1       A_CLK1 & B_CLK1
                //
                // The C reg in dspC is then used for the mask input,
                // and we duplicate the mask bits by 4.                                
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
                                  .PCOUT( dspA_to_C ),
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
                // and dspC needs to be an AND not an OR, so you just don't XOR everyone.
                DSP48E2 #(`NO_MULT_ATTRS,
                          `DE2_UNUSED_ATTRS,
                          .AREG(1),
                          .BREG(1),
                          .CREG(1),
                          .PREG(1),
                          .USE_PATTERN_DETECT("PATDET"),
                          .SEL_PATTERN("PATTERN"),
                          .SEL_MASK("C"),
                          .PATTERN( {48{1'b0}} ),
                          `CONSTANT_MODE_ATTRS )
                          u_dspC( .A( `DSP_AB_A( dspC_AB ) ),
                                  .B( `DSP_AB_B( dspC_AB ) ),
                                  .C( dspC_C ),
                                  .PCIN( dspA_to_C ),
                                  .P( leveltwo_scaler[pol] ),
                                  .PATTERNDETECT( not_leveltwo_trigger ),
                                  .ALUMODE(4'b1100),
                                  .OPMODE( dspC_OPMODE ),
                                  .CLK( clk_i ),
                                  .CEA2( ~ce_i ),
                                  .CEB2( ~ce_i ),
                                  .CEC( 1'b1 ),
                                  .CEP( ce_i ));                                  
            end

            wire aux_trig_delayed;
            reg aux_trig_delayed_ff = 0;
            wire [1:0] lf_trig_delayed; 
            reg [1:0] lf_trig_delayed_ff = {2{1'b0}};           
            
            srlvec #(.NBITS(3)) u_dly(.clk(clk_i),.ce(ce_i),
                                      .a(NMADDR),
                                      .din( { aux_trig, lf_trig } ),
                                      .dout( {aux_trig_delayed, lf_trig_delayed} ));            
            
            always @(posedge clk_i) begin : V2P
                if (ce_i) aux_trig_delayed_ff <= aux_trig_delayed;
                if (ce_i) lf_trig_delayed_ff <= lf_trig_delayed;
                // First deal with the LF trigs. They're automatic.
                // NOTE NOTE NOTE NOTE!!! THESE NEED TO BE DELAYED
                // TO MATCH UP WITH THE RF TRIGS ABOVE!!
                // LF trigs only use tio0 and tio1 as the two separate guys.
                // mask 26 is left LF (SURF10)
                // mask 27 is right LF (SURF17)
                if (ce_i) lf_trig[0] <= (tio0_trig_i[6] || tio2_trig_i[6]) && rf_en_i && !mask_i[26];
                if (ce_i) lf_trig[1] <= (tio1_trig_i[6] || tio3_trig_i[6]) && rf_en_i && !mask_i[27];
                // actual leveltwos. por_done prevents them from going when the DSP's pattern reg starts at 0.
                if (ce_i) leveltwo_trig[0] <= leveltwo_trigger[0] && por_done && rf_en_i;
                if (ce_i) leveltwo_trig[1] <= leveltwo_trigger[1] && por_done && rf_en_i;
                
                master_trig <= (!holdoff_i && !dead_i) && ce_i &&
                        ( aux_trig_delayed_ff || (|leveltwo_trig) || (|lf_trig_delayed_ff) );
            end
            assign trig_o = master_trig;
            // scalers. qualified by holdoff/dead because pretty much the only way to do it
            // now only qualified by holdoff, so you can let the system just go dead and it'll
            // still count.
            assign levelthree_o = master_trig;
            assign mie_o = (ce_i && !holdoff_i) ? leveltwo_trig : 2'b00;
            assign lf_o = (ce_i && !holdoff_i) ? lf_trig_delayed_ff : 2'b00;
            assign aux_o = (ce_i && !holdoff_i) ? aux_trig_delayed_ff : 1'b0;
            
        end else begin : V1
            wire [5:0] tio0_remask = { mask_i[0], mask_i[1], mask_i[2], mask_i[3], mask_i[4], mask_i[5] };
            wire [5:0] tio1_remask = { mask_i[11], mask_i[10], mask_i[9], mask_i[8], mask_i[7], mask_i[6] };
            wire [5:0] tio2_remask = { mask_i[12], mask_i[13], mask_i[14], mask_i[15], mask_i[16], mask_i[17] };
            wire [5:0] tio3_remask = { mask_i[23], mask_i[22], mask_i[21], mask_i[20], mask_i[19], mask_i[18] };

            wire tio0_trig = |(tio0_trig_i[5:0] & (~tio0_remask));
            wire tio1_trig = |(tio1_trig_i[5:0] & (~tio1_remask));
            wire tio2_trig = |(tio2_trig_i[5:0] & (~tio2_remask));
            wire tio3_trig = |(tio3_trig_i[5:0] & (~tio3_remask));
            
            wire lftrig0 = ((tio0_trig_i[6] && mask_i[24]) || (tio1_trig_i[6] && mask_i[25])) && rf_en_i;
            wire unused = ((tio2_trig_i[6] && mask_i[26]) || (tio3_trig_i[6] && mask_i[27])) && rf_en_i;
            
            always @(posedge clk_i) begin : V1P
                if (ce_i) leveltwo_trig[0] <= (tio0_trig || tio1_trig) && rf_en_i;
                if (ce_i) leveltwo_trig[1] <= (tio2_trig || tio3_trig) && rf_en_i;
                if (ce_i) lf_trig[0] <= lftrig0;
                if (ce_i) lf_trig[1] <= unused;
                
                master_trig <= (!holdoff_i && !dead_i) && ce_i && (aux_trig || (|leveltwo_trig) || (|lf_trig));
            end
            assign trig_o = master_trig;
            assign leveltwo_o = {24{1'b0}};
        end
    endgenerate

    assign tio0_meta_o = tio0_meta_hold[(META_DELAY-1)];
    assign tio1_meta_o = tio1_meta_hold[(META_DELAY-1)];
    assign tio2_meta_o = tio2_meta_hold[(META_DELAY-1)];
    assign tio3_meta_o = tio3_meta_hold[(META_DELAY-1)];
    
endmodule

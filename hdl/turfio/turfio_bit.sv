`timescale 1ns / 1ps
// Single bit interface, sigh.
module turfio_bit #(parameter INV = 1'b0, parameter INV_XB = 1'b0,
                    parameter CLKTYPE="IFCLK67")(
        input if_clk_i,
        input if_clk_x2_i,
        input rst_i,
        input en_vtc_i,
        // parallelize these
        input delay_load_i,
        input delay_rd_i,
        input [1:0] delay_sel_i,        
        input [8:0] delay_cntvaluein_i,
        output [8:0] delay_cntvalueout_o,
        // now the iserdes data
        output [3:0] data_o,
        // input
        input CIN_P,
        input CIN_N        
    );

    // cntvalueout has logic controlled by PSCLK and sends back to PSCLK
    (* CUSTOM_CC_SRC = CLKTYPE, CUSTOM_CC_DST = CLKTYPE *)
    reg [8:0] delay_cntvalueout = {9{1'b0}};
    // load the IDELAY delay
    wire idelay_load = (delay_load_i && !delay_sel_i[0]);
    // load the ODELAY delay
    wire odelay_load = (delay_load_i && delay_sel_i[0]);
    // IDELAY count value output
    wire [8:0] idelay_cntvalueout;
    // ODELAY count value output
    wire [8:0] odelay_cntvalueout;
    // IDELAY monitor count value output
    wire [8:0] idelaymon_cntvalueout;
    // ODELAY monitor count value output
    wire [8:0] odelaymon_cntvalueout;
    // vector
    wire [8:0] delay_cntvalueout_vec[3:0];
    // map
    assign delay_cntvalueout_vec[0] = idelay_cntvalueout;
    assign delay_cntvalueout_vec[1] = odelay_cntvalueout;
    assign delay_cntvalueout_vec[2] = idelaymon_cntvalueout;
    assign delay_cntvalueout_vec[3] = odelaymon_cntvalueout;    
    
    // O output of IBUFDS_DIFF_OUT
    wire cin_ninv;
    // I output of IBUFDS_DIFF_OUT
    wire cin_inv;
    // correct polarity signal
    // These can be inverted AGAIN with the INV_XB
    localparam FULLINV = INV ^ INV_XB;
    wire cin_real = (FULLINV==1'b0) ? cin_ninv : cin_inv;
    // incorrect polarity signal (unused)
    wire cin_monitor = (FULLINV==1'b0) ? cin_inv : cin_ninv;

    // These have to map to the TURF *schematic*. They determine
    // if we map P to I or IB and vice versa for N.
    // I input to IBUFDS_DIFF_OUT
    wire cin_p_in = (INV==1'b0) ? CIN_P : CIN_N;
    // IB input to IBUFDS_DIFF_OUT
    wire cin_n_in = (INV==1'b0) ? CIN_N : CIN_P;

    // The IDELAYE3 can be chained with the ODELAYE3 using the cascade path.
    wire cin_idelay_to_odelay;
    // Return to IDELAYE3
    wire cin_odelay_to_idelay;
    // Output to ISERDES
    wire cin_to_iserdes;
    // monitor IDELAY to ODELAY
    wire mon_idelay_to_odelay;
    // monitor return to IDELAYE3
    wire mon_odelay_to_idelay;
    

    // input buffer    
    IBUFDS_DIFF_OUT u_cin_ibuf(.I(cin_p_in),.IB(cin_n_in),.O(cin_ninv),.OB(cin_inv));
    (* RLOC = "X0Y0", HU_SET="cin0", CUSTOM_CC_DST = CLKTYPE, CUSTOM_CC_SRC = CLKTYPE, IODELAY_GROUP = CLKTYPE *)
    IDELAYE3 #(.DELAY_SRC("IDATAIN"),
               .CASCADE("MASTER"),
               .DELAY_TYPE("VAR_LOAD"),
               .DELAY_VALUE(0),
               .REFCLK_FREQUENCY(300.00),
               .DELAY_FORMAT("TIME"),
               .UPDATE_MODE("ASYNC"),
               .SIM_DEVICE("ULTRASCALE_PLUS"))
               u_idelay( .CASC_RETURN(cin_odelay_to_idelay),
                         .CASC_IN(),
                         .CASC_OUT(cin_idelay_to_odelay),
                         .CE(1'b0),
                         .CLK(if_clk_i),
                         .INC(1'b0),
                         .LOAD(idelay_load),
                         .CNTVALUEIN(delay_cntvaluein_i),
                         .CNTVALUEOUT(idelay_cntvalueout),
                         .DATAIN(),
                         .IDATAIN(cin_real),
                         .DATAOUT(cin_to_iserdes),
                         .RST(rst_i),
                         .EN_VTC(en_vtc_i));
    (* CUSTOM_CC_DST = CLKTYPE, CUSTOM_CC_SRC = CLKTYPE, IODELAY_GROUP = CLKTYPE *)
    ODELAYE3 #(.CASCADE("SLAVE_END"),
               .DELAY_TYPE("VAR_LOAD"),
               .DELAY_VALUE(0),
               .REFCLK_FREQUENCY(300.0),
               .DELAY_FORMAT("TIME"),
               .UPDATE_MODE("ASYNC"),
               .SIM_DEVICE("ULTRASCALE_PLUS"))
               u_odelay( .CASC_RETURN(),
                         .CASC_IN(cin_idelay_to_odelay),
                         .CASC_OUT(),
                         .CE(1'b0),
                         .CLK(if_clk_i),
                         .INC(1'b0),
                         .LOAD(odelay_load),
                         .CNTVALUEIN(delay_cntvaluein_i),
                         .CNTVALUEOUT(odelay_cntvalueout),
                         .ODATAIN(),
                         .DATAOUT(cin_odelay_to_idelay),
                         .RST(rst_i),
                         .EN_VTC(en_vtc_i));
    (* RLOC = "X0Y0", HU_SET="cin0" *)
    ISERDESE3 #(.DATA_WIDTH(4),
                .FIFO_ENABLE("FALSE"),
                .FIFO_SYNC_MODE("FALSE"),
                .IS_CLK_INVERTED(1'b0),
                .IS_CLK_B_INVERTED(1'b1),
                .IS_RST_INVERTED(1'b0),
                .SIM_DEVICE("ULTRASCALE_PLUS"))
                u_iserdes(.CLK(if_clk_x2_i),
                          .CLK_B(if_clk_x2_i),
                          .CLKDIV(if_clk_i),
                          .FIFO_RD_CLK(1'b0),
                          .FIFO_RD_EN(1'b0),
                          .FIFO_EMPTY(),
                          .D(cin_to_iserdes),
                          .Q(data_o),
                          .RST(rst_i));
    (* IODELAY_GROUP = CLKTYPE, CUSTOM_CC_SRC = CLKTYPE *)
    IDELAYE3 #(.DELAY_SRC("IDATAIN"),
               .CASCADE("MASTER"),
               .DELAY_TYPE("VAR_LOAD"),
               .DELAY_VALUE(700.0),
               .REFCLK_FREQUENCY(300.00),
               .DELAY_FORMAT("TIME"),
               .UPDATE_MODE("ASYNC"),
               .SIM_DEVICE("ULTRASCALE_PLUS"))
               u_idelaymon( .CASC_RETURN(mon_odelay_to_idelay),
                         .CASC_IN(),
                         .CASC_OUT(mon_idelay_to_odelay),
                         .CE(1'b0),
                         .CLK(if_clk_i),
                         .INC(1'b0),
                         .LOAD(1'b0),
                         .CNTVALUEIN(9'h000),
                         .CNTVALUEOUT(idelaymon_cntvalueout),
                         .DATAIN(),
                         .IDATAIN(cin_monitor),
                         .DATAOUT(),
                         .RST(rst_i),
                         .EN_VTC(en_vtc_i));
    (* IODELAY_GROUP = CLKTYPE, CUSTOM_CC_SRC = CLKTYPE *)
    ODELAYE3 #(.CASCADE("SLAVE_END"),
               .DELAY_TYPE("VAR_LOAD"),
               .DELAY_VALUE(700.0),
               .REFCLK_FREQUENCY(300.0),
               .DELAY_FORMAT("TIME"),
               .UPDATE_MODE("ASYNC"),
               .SIM_DEVICE("ULTRASCALE_PLUS"))
               u_odelaymon( .CASC_RETURN(),
                         .CASC_IN(mon_idelay_to_odelay),
                         .CASC_OUT(),
                         .CE(1'b0),
                         .CLK(if_clk_i),
                         .INC(1'b0),
                         .LOAD(1'b0),
                         .CNTVALUEIN(9'h000),
                         .CNTVALUEOUT(odelaymon_cntvalueout),
                         .ODATAIN(),
                         .DATAOUT(mon_odelay_to_idelay),
                         .RST(rst_i),
                         .EN_VTC(en_vtc_i));
                         
    always @(posedge if_clk_i) begin
        if (delay_rd_i) begin
            delay_cntvalueout <= delay_cntvalueout_vec[delay_sel_i];
        end
    end            

    assign delay_cntvalueout_o = delay_cntvalueout;

endmodule

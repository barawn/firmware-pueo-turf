`timescale 1ns / 1ps
// Controls the COUT path from TURFIO to TURF.
// This module is purely SYSCLK domain.
// Note: the sync_i interface realigns the TURFIO responses
// to the overall 16-clock sync period. It also
// realigns the training pattern outputs on all
// lanes, because they're all generated from the same
// thing. 
module turf_cout_interface(
        // system clock
        input sysclk_i,
        // system clock x2 for OSERDES
        input sysclk_x2_i,      
        // OSERDES reset (dunno)
        input oserdes_rst_i,          
        // training enable on all interfaces
        input train_i,
        // synchronize internal period. indicates cycle 0 of 16-clock period
        input sync_i,
        // captured on clock 7 and 15 and presented on 0 and 8
        // nb I don't even know what this will do
        input [31:0] response_i,
        // always immediately reclocked out
        input [27:0] surf_response_i,
        
        output [6:0] T_COUT_P,
        output [6:0] T_COUT_N,
        output COUTTIO_P,
        output COUTTIO_N,
        output TXCLK_P,
        output TXCLK_N
    );
    
    parameter COUTTIO_INV = 1'b0;
    parameter TXCLK_INV = 1'b0;
    parameter [6:0] T_COUT_INV = {7{1'b0}};
    
    localparam NUM_SURF = 7;
    
    localparam [31:0] TRAIN_VALUE = 32'hA55A6996;
    // I don't need a full 16-clock phase
    reg [2:0] response_phase = {3{1'b0}};
    reg [31:0] response_hold = {32{1'b0}};
    
    wire [31:0] value_to_send = (train_i) ? TRAIN_VALUE : response_i;

    // Input to OBUFDS
    wire couttio_out;
    // COUT positive output from OBUFDS
    wire couttio_out_p;
    // COUT negative output from OBUFDS
    wire couttio_out_n;
    // Assign correct polarity to positive
    assign COUTTIO_P = (COUTTIO_INV) ? couttio_out_n : couttio_out_p;
    // Assign correct polarity to negative
    assign COUTTIO_N = (COUTTIO_INV) ? couttio_out_p : couttio_out_n;

    // TXCLK positive output from OBUFDS
    wire txclk_out_p;
    // TXCLK negative output from OBUFDS
    wire txclk_out_n;
    // TXCLK input to OBUFDS
    wire txclk_in;
    // Assign correct polarity to positive
    assign TXCLK_P = (TXCLK_INV) ? txclk_out_n : txclk_out_p;
    // Assign correct polarity to negative
    assign TXCLK_N = (TXCLK_INV) ? txclk_out_p : txclk_out_n;


    always @(posedge sysclk_i) begin
        if (response_phase == 7) response_hold <= value_to_send;
        else response_hold <= { {4{1'b0}}, response_hold[4 +: 28] };        
        
        if (sync_i) response_phase <= 3'h1;
        else response_phase <= response_phase + 1;
    end
    // OSERDES. LSB is first out.    
    OSERDESE2 #(.DATA_RATE_OQ("DDR"),
                .DATA_WIDTH(4),
                .INIT_OQ(COUTTIO_INV),
                .SRVAL_OQ(COUTTIO_INV))
        u_couttio_oserdes( .CLK(sysclk_x2_i),
                           .CLKDIV(sysclk_i),
                           .D1(response_hold[0] ^ COUTTIO_INV),
                           .D2(response_hold[1] ^ COUTTIO_INV),
                           .D3(response_hold[2] ^ COUTTIO_INV),
                           .D4(response_hold[3] ^ COUTTIO_INV),
                           .OCE(1'b1),
                           .RST(oserdes_rst_i),
                           .OQ(couttio_out));
    OBUFDS u_couttio_obufds(.I(couttio_out),.O(couttio_out_p),.OB(couttio_out_n));
    
    // This clock selection is not right, it should be sysclk based
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE"),.INIT(TXCLK_INV),.SRTYPE("SYNC"))
        u_txclk_oddr(.C(sysclk_i),
                     .CE(1'b1),
                     .D1(~TXCLK_INV),
                     .D2(TXCLK_INV),
                     .R(1'b0),
                     .S(1'b0),
                     .Q(txclk_in));
    OBUFDS u_txclk_obuf(.I(txclk_in),.O(txclk_out_p),.OB(txclk_out_n));
    
    generate
        genvar i;
        for (i=0;i<NUM_SURF;i=i+1) begin : SL
            wire [3:0] surf_cin = (train_i) ? response_hold[3:0] : surf_response_i[3:0];
            // output from oserdes
            wire surf_cout;
            // positive output from OBUFDS
            wire surf_cout_p;
            // inverted output from OBUFDS
            wire surf_cout_n;
            // assign correct pin to P
            assign T_COUT_P[i] = T_COUT_INV[i] ? surf_cout_n : surf_cout_p;
            // assign correct pin to N
            assign T_COUT_N[i] = T_COUT_INV[i] ? surf_cout_p : surf_cout_n;
            // OSERDES. LSB is first out.    
            OSERDESE2 #(.DATA_RATE_OQ("DDR"),
                        .DATA_WIDTH(4),
                        .INIT_OQ(T_COUT_INV[i]),
                        .SRVAL_OQ(T_COUT_INV[i]))
                u_surfcout_oserdes( .CLK(sysclk_x2_i),
                                   .CLKDIV(sysclk_i),
                                   .D1(surf_cin[0] ^ T_COUT_INV[i]),
                                   .D2(surf_cin[1] ^ T_COUT_INV[i]),
                                   .D3(surf_cin[2] ^ T_COUT_INV[i]),
                                   .D4(surf_cin[3] ^ T_COUT_INV[i]),
                                   .OCE(1'b1),
                                   .RST(oserdes_rst_i),
                                   .OQ(surf_cout));
            OBUFDS u_surfcout_obufds(.I(surf_cout),.O(surf_cout_p),.OB(surf_cout_n));
                    
            
        end
    endgenerate        
    
endmodule

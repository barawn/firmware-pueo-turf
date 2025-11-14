`timescale 1ns / 1ps
`include "interfaces.vh"
// Fully combined TURFIO interface.
// Notes:
// 1) This *once again* redefines the clocking infrastructure to accomodate the stupid
//    "component mode reset sequence" which suggests resetting the damn PLL. What-the-effing ever.
//    So now the input system clock goes to 3 MMCMs: one (placed wherever), one in bank 67,
//    one in bank 68. We only handle the bank 67/bank 68 ones.
// 2) this has a 15-bit address space. The first half is for global stuff (like IDELAYCTRL
//    readys, and MMCM resets/lockeds, etc.). The second half is split in 4 for each of the TURFIOs.
// 3) the ifclks are fully contained here. They're reclocked to sysclk outside this and the timer
//    should be able to resolve the issues.
module turfio_if #( parameter [31:0] TRAIN_VALUE=32'hA55A6996,
                    parameter [3:0] INV_CINTIO = 4'h0,
                    parameter [3:0] INV_CINTIO_XB = 4'h0,

                    parameter [3:0] INV_COUT = 4'h0,
                    parameter [3:0] INV_COUT_XB = 4'h0,
                    
                    parameter [6:0] INV_CINA = 7'h00,
                    parameter [6:0] INV_CINA_XB = 7'h00,
                    
                    parameter [6:0] INV_CINB = 7'h00,
                    parameter [6:0] INV_CINB_XB = 7'h00,
                    
                    parameter [6:0] INV_CINC = 7'h00,
                    parameter [6:0] INV_CINC_XB = 7'h00,
                    
                    parameter [6:0] INV_CIND = 7'h00,
                    parameter [6:0] INV_CIND_XB = 7'h00,
                    
                    parameter [3:0] INV_TXCLK = 4'h0,
                    parameter [3:0] INV_TXCLK_XB = 4'h0,
                    
                    // 0 if bank 67, 1 if bank 68
                    parameter [3:0] CIN_CLKTYPE = 4'h0,
                    parameter [3:0] COUT_CLKTYPE = 4'h0,
                    parameter INV_SYSCLK = "TRUE",
                    parameter WBCLKTYPE = "NONE",
                    // CLKTYPE of clk300
                    parameter CLK300_CLKTYPE = "DDRCLK0"
        )(
        input clk_i,
        input rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 15, 32),
        input clk300_i,

        // Output of sysclk IBUFDS
        input sysclk_ibuf_i,
        // high in phase 0 of 8-clock sequence
        input sysclk_phase_i,
        
        // interface clock on bank 67
        output ifclk67_o,
        // interface clock on bank 68
        output ifclk68_o,
        
        // This is the real sysclk input. We resync to sysclk.
        input sysclk_i,
        // We now shift to individualized commanding for each TURFIO.
        input [31:0] cout_command0_i,
        input [31:0] cout_command1_i,
        input [31:0] cout_command2_i,
        input [31:0] cout_command3_i,
        
        // Trigger outputs for CINA
        output [16*8-1:0] cina_trigger_o,
        // Outputs are valid
        output [7:0] cina_valid_o,
        
        // Arrayed command outputs for port B
        output [16*8-1:0] cinb_trigger_o,
        // Outputs are valid
        output [7:0] cinb_valid_o,

        // Arrayed command outputs for port C
        output [16*8-1:0] cinc_trigger_o,
        // Outputs are valid
        output [7:0] cinc_valid_o,

        // Arrayed command outputs for port B
        output [16*8-1:0] cind_trigger_o,
        // Outputs are valid
        output [7:0] cind_valid_o,
                
        // vectored CINTIO corresponding to D,C,B,A
        input [3:0] CINTIO_P,
        input [3:0] CINTIO_N,
        // vectored COUT corresponding to D,C,B,A
        output [3:0] COUT_P,
        output [3:0] COUT_N,
        // vectored TXCLK corresponding to D, C, B, A
        output [3:0] TXCLK_P,
        output [3:0] TXCLK_N,        
        // vectored CIN for port A
        input [6:0] CINA_P,
        input [6:0] CINA_N,
        // for port B
        input [6:0] CINB_P,
        input [6:0] CINB_N,
        // for port C
        input [6:0] CINC_P,
        input [6:0] CINC_N,
        // for port D
        input [6:0] CIND_P,
        input [6:0] CIND_N
    );
    // number of interfaces
    localparam NUM_IF = 4;
    // number of bits required for interface
    localparam NUM_IF_BITS = $clog2(NUM_IF);    
    // number of address bits for interface
    localparam NUM_IF_ADR_BITS = 12;

    localparam [31:0] BIT_DEBUG_FULL = {
        8'h00,
        8'h00,
        8'h00,
        8'h30 };

    // create a lookup function for parameters
    function [6:0] lookup_inv_cin;
        input integer i;
        begin
            if (i==0) lookup_inv_cin = INV_CINA;
            else if (i==1) lookup_inv_cin = INV_CINB;
            else if (i==2) lookup_inv_cin = INV_CINC;
            else lookup_inv_cin = INV_CIND;
        end
    endfunction    
    function [6:0] lookup_inv_cin_xb;
        input integer i;
        begin
            if (i==0) lookup_inv_cin_xb = INV_CINA_XB;
            else if (i==1) lookup_inv_cin_xb = INV_CINB_XB;
            else if (i==2) lookup_inv_cin_xb = INV_CINC_XB;
            else lookup_inv_cin_xb = INV_CIND_XB;
        end
    endfunction            
    // create a vector for positive legs of inputs
    wire [6:0] cin_vec_p[NUM_IF-1:0];
    // create a vector for negative legs of inputs
    wire [6:0] cin_vec_n[NUM_IF-1:0];

    // and create a vector for the command outputs.
    wire [16*8-1:0] cin_trigger_vec[NUM_IF-1:0];
    // and valids
    wire [7:0] cin_trigger_valid_vec[NUM_IF-1:0];

    // macro the assignment to avoid mistakes      
    `define ASSIGN_CIN_VEC( number, lowerletter, upperletter) \
        assign cin_vec_p[ number ] = CIN``upperletter``_P;    \
        assign cin_vec_n[ number ] = CIN``upperletter``_N;    \
        assign cin``lowerletter``_trigger_o = cin_trigger_vec[ number ]; \
        assign cin``lowerletter``_valid_o = cin_trigger_valid_vec[ number ]

    `ASSIGN_CIN_VEC( 0, a, A );
    `ASSIGN_CIN_VEC( 1, b, B );
    `ASSIGN_CIN_VEC( 2, c, C );
    `ASSIGN_CIN_VEC( 3, d, D );

    // reset the bank 67 IDELAYCTRL. This needs to get sync'd over to refclk.
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg idelayctrl67_rst = 0;
    // synchronizer for idelayctrl67
    (* ASYNC_REG = "TRUE", CUSTOM_CC_DST = CLK300_CLKTYPE *)
    reg [1:0] idelayctrl67_rst_refclk = {2{1'b0}};    
    // IDELAYCTRL for bank 67 is ready
    wire idelayctrl67_rdy;
    // reset the bank 68 IDELAYCTRL. This needs to get sync'd over to refclk.
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg idelayctrl68_rst = 0;
    // synchronizer for idelayctrl68
    (* ASYNC_REG = "TRUE", CUSTOM_CC_DST = CLK300_CLKTYPE *)
    reg [1:0] idelayctrl68_rst_refclk = {2{1'b0}};
    
    // IDELAYCTRL for bank 68 is ready
    wire idelayctrl68_rdy;
    // reset the MMCM in bank 67
    reg mmcm_rst67 = 0;
    // reset the MMCM in bank 68
    reg mmcm_rst68 = 0;
    // locked outputs
    wire [1:0] mmcm_locked;
    
    // reset all IDELAYs/ISERDESes in bank 67
    reg bank67_rst = 1'b0;
    // reset all IDELAYs/ISERDESes in bank 68
    reg bank68_rst = 1'b0;
    
    // Sysclk in bank 67
    wire ifclk67;
    // Phase of sysclk in bank 67
    wire ifclk67_phase;
    // Sysclk x2 in bank 67
    wire ifclk67x2;
    // Phase of sysclkx2 in bank 67
    wire ifclk67x2_phase;
    // Sysclk in bank 68
    wire ifclk68;
    // Phase of sysclk in bank 68
    wire ifclk68_phase;
    // Sysclk x2 in bank 68
    wire ifclk68x2;
    // Phase of sysclkx2 in bank 68
    wire ifclk68x2_phase;

    // OK, we need to define the vector of WB interfaces now.
    `DEFINE_WB_IFV( wbtio_ , NUM_IF_ADR_BITS, 32, [NUM_IF-1:0] );
    
    // local WISHBONE outputs
    reg [31:0] dat_reg_local = {32{1'b0}};
    reg ack_local_reg = 1'b0;
    wire ack_local = ack_local_reg && wb_cyc_i;
    wire err_local = 1'b0;
    wire rty_local = 1'b0;
    
    // local logic..
    always @(posedge clk_i) begin
        ack_local_reg <= wb_cyc_i && wb_stb_i && !wb_adr_i[14];
        if (wb_cyc_i && wb_stb_i && !wb_adr_i[14] && !wb_we_i) begin
            // DOCUMENT THIS
            // byte 0 is reserved for controls ([0] = reset mmcm 68, [1] = reset mmcm67, [2] reset idelayctrl67 [3] reset idelayctrl68)
            // byte 1 is reserved for statuses. "1" means GOOD. To make things simple unused guys are 1 here.
            //                                  [0] = mmcm locked 67
            //                                  [1] = mmcm locked 68
            //                                  [2] = idelayctrl rdy 67
            //                                  [3] = idelayctrl rdy 68
            dat_reg_local <= { {16{1'b0}}, 
                {4{1'b1}}, idelayctrl68_rdy, idelayctrl67_rdy, mmcm_locked, 
                {2{1'b0}}, bank67_rst, bank68_rst, idelayctrl68_rst, idelayctrl67_rst, mmcm_rst68, mmcm_rst67 };
        end
        
        if (wb_cyc_i && wb_stb_i && !wb_adr_i[14] && wb_we_i) begin
            if (wb_sel_i[0]) begin
                mmcm_rst67 <= wb_dat_i[0];
                mmcm_rst68 <= wb_dat_i[1];
                idelayctrl67_rst <= wb_dat_i[2];
                idelayctrl68_rst <= wb_dat_i[3];
                bank67_rst <= wb_dat_i[4];
                bank68_rst <= wb_dat_i[5];
            end
        end
    end
    
    always @(posedge clk300_i) begin
        idelayctrl67_rst_refclk <= {idelayctrl67_rst_refclk[0], idelayctrl67_rst };
        idelayctrl68_rst_refclk <= {idelayctrl68_rst_refclk[0], idelayctrl68_rst };        
    end
    
    // IODELAYs...    
    (* IODELAY_GROUP = "IFCLK67" *)
    IDELAYCTRL #(.SIM_DEVICE("ULTRASCALE")) u_idelayctrl67(.REFCLK(clk300_i),
                                                           .RST(idelayctrl67_rst_refclk[1]),
                                                           .RDY(idelayctrl67_rdy));
    (* IODELAY_GROUP = "IFCLK68" *)
    IDELAYCTRL #(.SIM_DEVICE("ULTRASCALE")) u_idelayctrl68(.REFCLK(clk300_i),
                                                           .RST(idelayctrl68_rst_refclk[1]),
                                                           .RDY(idelayctrl68_rdy));

    // and clocks
    turfio_if_clocks #(.INVERT_MMCM(INV_SYSCLK))
        u_clocks( .sysclk_ibuf_i(sysclk_ibuf_i),
                  .sysclk_phase_i(sysclk_phase_i),
                  .rst67_i(mmcm_rst67),
                  .rst68_i(mmcm_rst68),
                  .ifclk67_o(ifclk67),
                  .ifclk67_phase_o(ifclk67_phase),
                  .ifclk67_x2_o(ifclk67x2),
                  .ifclk67_x2_phase_o(ifclk67x2_phase),
                  .ifclk68_o(ifclk68),
                  .ifclk68_phase_o(ifclk68_phase),
                  .ifclk68_x2_o(ifclk68x2),
                  .ifclk68_x2_phase_o(ifclk68x2_phase),
                  .locked_o(mmcm_locked));

    wire [31:0] command[3:0];
    assign command[0] = cout_command0_i;
    assign command[1] = cout_command1_i;
    assign command[2] = cout_command2_i;
    assign command[3] = cout_command3_i;

    generate
        genvar i,j;
        for (i=0;i<4;i=i+1) begin : IFL
            // hook up the local bus. Remember it's *master* named so o's to i's
            assign wbtio_cyc_o[i] = wb_cyc_i && wb_adr_i[14] && wb_adr_i[(14-NUM_IF_BITS) +: NUM_IF_BITS] == i;
            assign wbtio_stb_o[i] = wb_stb_i;
            assign wbtio_adr_o[i] = wb_adr_i[0 +: NUM_IF_ADR_BITS];
            assign wbtio_sel_o[i] = wb_sel_i;
            assign wbtio_we_o[i] = wb_we_i;
            assign wbtio_dat_o[i] = wb_dat_i;
            // 0 and 3 are bank 68
            // 1 and 2 are bank 67
            wire [31:0] bank_command = command[i];
            
            // HOLY MOLY BIG
            wire [32*8-1:0] tio_response;
            wire [7:0] tio_response_valid;
            reg [16*8-1:0] trigger_rereg = {32*8{1'b0}};
            reg [7:0] trigger_valid_rereg = {8{1'b0}};

            for (j=0;j<8;j=j+1) begin : BL
                always @(posedge sysclk_i) begin : RR
                    // The UPPER WORD is the active word!!! We shift UP
                    // We get (addr, data) -> (data, xxx).
                    trigger_rereg[16*j +: 16] <= tio_response[(32*j + 16) +: 16];
                    trigger_valid_rereg[j] <= tio_response_valid[j];
                end
            end
            assign cin_trigger_vec[i] = trigger_rereg;
            assign cin_trigger_valid_vec[i] = trigger_valid_rereg;

            // now the single_ifs...
            turfio_single_if_v2 #(.INV_CIN(lookup_inv_cin(i)),
                               .INV_CIN_XB(lookup_inv_cin_xb(i)),
                               .INV_CINTIO(INV_CINTIO[i]),
                               .INV_CINTIO_XB(INV_CINTIO_XB[i]),
                               .INV_COUT(INV_COUT[i]),
                               .INV_COUT_XB(INV_COUT_XB[i]),
                               .INV_TXCLK(INV_TXCLK[i]),
                               .INV_TXCLK_XB(INV_TXCLK_XB[i]),
                               .CIN_CLKTYPE(CIN_CLKTYPE[i] ? "IFCLK67" : "IFCLK68"),
                               .COUT_CLKTYPE(COUT_CLKTYPE[i] ? "IFCLK67" : "IFCLK68"),
                               .BIT_DEBUG(BIT_DEBUG_FULL[8*i +: 8]),
                               .TRAIN_VALUE(TRAIN_VALUE))
                u_if( .clk_i(clk_i),
                      .rst_i(rst_i),
                      `CONNECT_WBS_IFMV( wb_ , wbtio_ , [i] ),                      
                      .cin_clk_i( CIN_CLKTYPE[i] ? ifclk68 : ifclk67 ),
                      .cin_clk_ok_i( mmcm_locked[CIN_CLKTYPE[i]] ),
                      .cin_clk_phase_i( CIN_CLKTYPE[i] ? ifclk68_phase : ifclk67_phase ),
                      .cin_rst_i( CIN_CLKTYPE[i] ? bank68_rst : bank67_rst ),
                      .cout_clk_i( COUT_CLKTYPE[i] ? ifclk68 : ifclk67 ),
                      .cin_clk_x2_i( CIN_CLKTYPE[i] ? ifclk68x2 : ifclk67x2 ),
                      .cout_clk_x2_i( COUT_CLKTYPE[i] ? ifclk68x2 : ifclk67x2 ),
                      .cout_clk_x2_phase_i( COUT_CLKTYPE[i] ? ifclk68x2_phase : ifclk67x2_phase ),
                      .cout_command_i(bank_command),
                      
                      .cin_response_o(tio_response),
                      .cin_valid_o(tio_response_valid),
                      
                      .CIN_P(cin_vec_p[i]),
                      .CIN_N(cin_vec_n[i]),
                      .CINTIO_P(CINTIO_P[i]),
                      .CINTIO_N(CINTIO_N[i]),
                      .COUT_P(COUT_P[i]),
                      .COUT_N(COUT_N[i]),
                      .TXCLK_P(TXCLK_P[i]),
                      .TXCLK_N(TXCLK_N[i]));
        end
    endgenerate

    // now mux stuff. Remember the single-IF interfaces are named as a WB *master* here: the wb_dat_o
    // port on them gets mapped to a dat_i.
    assign wb_dat_o = (wb_adr_i[14]) ? wbtio_dat_i[wb_adr_i[(14-NUM_IF_BITS) +: NUM_IF_BITS]] : dat_reg_local;
    assign wb_ack_o = (wb_adr_i[14]) ? wbtio_ack_i[wb_adr_i[(14-NUM_IF_BITS) +: NUM_IF_BITS]] : ack_local;
    assign wb_err_o = (wb_adr_i[14]) ? wbtio_err_i[wb_adr_i[(14-NUM_IF_BITS) +: NUM_IF_BITS]] : err_local;
    assign wb_rty_o = (wb_adr_i[14]) ? wbtio_rty_i[wb_adr_i[(14-NUM_IF_BITS) +: NUM_IF_BITS]] : rty_local;    
        
        
    assign ifclk67_o = ifclk67;
    assign ifclk68_o = ifclk68;        
endmodule

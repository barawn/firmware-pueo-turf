`timescale 1ns / 1ps
// sigh. OK, this is our attempt at making something work.
// Note that the reason we have the extra clocks here is
// that the I/O clock needs to be min-skew between it and
// the sys_clk_x2. So we really do have 3 clocks, it just
// happens to be that 2 of the clocks are identical
// and phase related. Hopefully the timer should be able to
// deal with it.
//
// Note: We fundamentally have 2 CMTs available to us:
// bank 67 and bank 68. We use the MMCMs in both of them
// to generate ifclk/ifclk x2. We use the PLLs in both
// of them to generate the RXCLKs. PLLs do NOT have fine
// phase shift so we can't pull the same trick as on the TURFIOs,
// so we just use the IDELAY on RXCLK to do it first.
//
// One might ask: why do we capture on RXCLK anyway? Two reasons.
// First, capturing using RXCLK automatically compensates temperature
// variations in the output/input buffer delays, which are pretty
// big.
module turfio_prototest(
        input RXCLK_P,
        input RXCLK_N,
        output TXCLK_P,
        output TXCLK_N,
        input CINTIO_P,
        input CINTIO_N,
        output COUT_P,
        output COUT_N,

        input sys_clk,
        input if_clk67,
        input if_clk67_x2,
        input if_clk67_x2_phase,
        input if_clk68,
        input if_clk68_x2,
        input if_clk68_x2_phase,
        input if_clk_x2_locked
    );
    // Bank Assignments:
    // TURFIO A: CIN/RXCLK/SPARE=bank68 COUT/TXCLK=bank67
    // TURFIO B: CIN/RXCLK/COUT/TXCLK/SPARE=bank68
    // TURFIO C: CIN/RXCLK/SPARE=bank67 COUT/TXCLK=bank68
    // TURFIO D: CIN/RXCLK/COUT/TXCLK/SPARE=bank67
    
    
    parameter IDELAY_INITIAL = 9'd256;
    parameter INV_RXCLK = 0;
    parameter INV_TXCLK = 0;
    parameter INV_CINTIO = 0;
    parameter INV_COUT = 0;
    // single-ended versions
    wire rxclk_bufg;
    wire cin_idelay;
    wire cout;
    wire txclk;
    
    generate
        if (INV_RXCLK==1) begin : RXCLK_INV    
            IBUFDS_DIFF_OUT u_rxclk_ibuf(.I(RXCLK_N),.IB(RXCLK_P),.OB(rxclk_bufg));
        end else begin : RXCLK_NINV
            IBUFDS u_rxclk_ibuf(.I(RXCLK_P),.IB(RXCLK_N),.O(rxclk_bufg));
        end
        if (INV_CINTIO==1) begin : CIN_INV 
            IBUFDS_DIFF_OUT u_cin_ibuf(.I(CINTIO_N),.IB(CINTIO_P),.OB(cin_idelay));
        end else begin : CIN_NINV            
            IBUFDS u_cin_ibuf(.I(CINTIO_P),.IB(CINTIO_N),.O(cin_idelay));
        end
        if (INV_COUT==1) begin : COUT_INV
            OBUFDS u_cout_obuf(.I(cout),.O(COUT_N),.OB(COUT_P));
        end else begin : COUT_NINV
            OBUFDS u_cout_obuf(.I(cout),.O(COUT_P),.OB(COUT_N));
        end
        if (INV_TXCLK==1) begin : TXCLK_INV                    
            OBUFDS u_txclk_obuf(.I(txclk),.O(TXCLK_N),.OB(TXCLK_P));
        end else begin : TXCLK_NINV
            OBUFDS u_txclk_obuf(.I(txclk),.O(TXCLK_P),.OB(TXCLK_N));
        end
    endgenerate
    // We can't do any of the native mode crap. We have to
    // do component mode.
    // All of our RXCLKs are on BUFGs anyway.
    
    wire rxclk;
    wire cin;
    BUFG u_rxclk_bufg(.I(rxclk_bufg),.O(rxclk));
    // IDELAYs in UltraScales kinda suck, you basically need to
    // step them through.
    reg [8:0] cur_idelay = IDELAY_INITIAL;
    wire [8:0] tgt_idelay;
    wire idelay_rst;
    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] RESET = 0;
    localparam [FSM_BITS-1:0] IDLE = 1;
    localparam [FSM_BITS-1:0] INCREMENT = 2;
    localparam [FSM_BITS-1:0] INCR_WAIT = 3;
    localparam [FSM_BITS-1:0] CHECK = 4;
    localparam [FSM_BITS-1:0] READY = 5;
    reg [FSM_BITS-1:0] state = IDLE;
    wire idelay_rdy = (state == READY);
    wire delay_done;
    SRL16E u_delay(.D(state == INCREMENT),.CE(1'b1),.CLK(sys_clk),
                   .A0(1'b1),.A1(1'b1),.A2(1'b1),.A3(1'b1),.Q(delay_done));                       
    
    always @(posedge sys_clk) begin
        if (idelay_rst) state <= RESET;
        else begin
            case (state)
                RESET: state <= IDLE;
                IDLE: if (tgt_idelay != cur_idelay) state <= INCREMENT;
                INCREMENT: state <= INCR_WAIT;
                INCR_WAIT: if (delay_done) state <= CHECK;
                CHECK: if (tgt_idelay != cur_idelay) state <= INCREMENT;
                       else state <= READY;
                READY: state <= IDLE;
            endcase
        end
        
        if (state == RESET) cur_idelay <= IDELAY_INITIAL; 
        else if (state == INCREMENT) cur_idelay <= cur_idelay + 1;        
    end             
    
    (* RLOC = "X0Y0", HU_SET="cin0" *)
    IDELAYE3 #(.DELAY_SRC("IDATAIN"),
               .CASCADE("NONE"),
               .DELAY_TYPE("VARIABLE"),
               .DELAY_VALUE(IDELAY_INITIAL),
               .DELAY_FORMAT("COUNT"),
               .SIM_DEVICE("ULTRASCALE_PLUS"))
               u_idelay(.CLK(if_clk68),
                        .EN_VTC(1'b0),
                        .IDATAIN(cin_idelay),
                        .INC(state == INCREMENT),
                        .CE(state == INCREMENT),
                        .LOAD(1'b0),
                        .RST(idelay_rst),
                        .CNTVALUEIN(9'h000),
                        .DATAOUT(cin));
    wire [7:0] cin_iserdes;
    wire fifo_empty;
    wire iserdes_rst;
    (* RLOC = "X0Y0", HU_SET="cin0" *)
    ISERDESE3 #(.DATA_WIDTH(4),
                .FIFO_ENABLE("TRUE"),
                .FIFO_SYNC_MODE("FALSE"),
                .IS_CLK_INVERTED(1'b0),
                .IS_CLK_B_INVERTED(1'b1),
                .IS_RST_INVERTED(1'b0),
                .SIM_DEVICE("ULTRASCALE_PLUS"))
                u_iserdes(.CLK(if_clk68_x2),
                          .CLK_B(if_clk68_x2),
                          .CLKDIV(if_clk),
                          .FIFO_RD_CLK(if_clk),
                          .FIFO_RD_EN(!fifo_empty),
                          .FIFO_EMPTY(fifo_empty),
                          .D(cin),
                          .Q(cin_iserdes),
                          .RST(iserdes_rst));

    // OK, so now we pop it through the bitaligner:
    wire [3:0] cur_data;
    wire       bitslip;
    wire       bitslip_rst;
    reg        bitslip_seen = 0;
    wire       do_bitslip = bitslip && !bitslip_seen;
    always @(posedge sys_clk) bitslip_seen <= bitslip;
    bit_align u_bitalign(.din(cin_iserdes),
                         .dout(cur_data),
                         .slip(do_bitslip),
                         .rst(bitslip_rst),
                         .clk(sys_clk));

    // This is just temporary!
    // This indicates what phase we're in of the overall 15.625 MHz cycle.
    localparam [31:0] TRAIN_VALUE = 32'hA55A6996;
    reg [2:0] sysclk_phase = {3{1'b0}};
    reg [31:0] train_data = TRAIN_VALUE;
    reg [3:0] cout_oserdes = {4{1'b0}};
    wire [3:0] cout_oserdes_optinv = (INV_COUT == 1) ? ~cout_oserdes : cout_oserdes;
    wire [31:0] cout_qword;
    reg [31:0] cout_vio_data = {32{1'b0}};
    wire       cout_load;    
    wire       cout_use_vio;
    reg        cout_use_vio_sync = 0;
    wire [31:0] cout_in_data = (cout_use_vio_sync) ? cout_vio_data : train_data;
    integer ci;
    always @(posedge sys_clk) begin
        for (ci=0;ci<8;ci=ci+1) begin
            if (sysclk_phase == ci) cout_oserdes <= cout_in_data[4*ci +: 4];
        end        
        if (cout_load) cout_vio_data <= cout_qword;
        if (sysclk_phase == 7) cout_use_vio_sync <= cout_use_vio;
        sysclk_phase <= sysclk_phase + 1;
//        if (cout_load_reg[0] && !cout_load_reg[1]) cout_oserdes <= cout_byte[7:4];
//        else if (cout_load_reg[1] && !cout_load_reg[2]) cout_oserdes <= cout_byte[3:0];
//        else cout_oserdes <= {4{1'b0}};
    end    
    // goddamn OSERDES issues
    // we're supposed to output LSB first and D1 is the first edge.
    reg [3:0] cout_recap = {4{INV_COUT}};
    reg [1:0] cout_buf = {2{INV_COUT}};
    reg       cout_phase_reg = 0;
    always @(posedge if_clk67_x2) begin
        // cout_phase_reg indicates NEXT clock is the first sync clk edge.
        cout_phase_reg <= if_clk67_x2_phase;
        // NEXT clock will be first clock so capture now. We can
        // spec a multi-cycle constraint for cout_oserdes_optinv to
        // cout_recap if we need to.
        if (cout_phase_reg) cout_recap <= cout_oserdes_optinv;
        // LSB always comes out first, so in second-cycle we buffer the
        // high 2 bits.
        if (cout_phase_reg) cout_buf <= cout_recap[3:2];
        else cout_buf <= cout_recap[1:0];
    end        
    ODDRE1 #(.SRVAL(INV_COUT)) u_cout_oddr(.C(if_clk67_x2),.D1(cout_buf[0]),.D2(cout_buf[1]),.SR(1'b0),.Q(cout));
//    OSERDESE3 #(.DATA_WIDTH(4),
//                .INIT(INV_COUT),
//                .SIM_DEVICE("ULTRASCALE_PLUS"))
//                u_oserdes(.CLK(if_clk67_x2),
//                          .CLKDIV(if_clk67),
//                          .D({4'h0, cout_oserdes_optinv}),
//                          .OQ(cout),
//                          .RST(oserdes_rst),
//                          .T(1'b0));
    ODDRE1 #(.SRVAL(INV_TXCLK)) u_txclk_oddr(.C(if_clk67),.D1(1'b1 ^ INV_TXCLK),.D2(1'b0 ^ INV_TXCLK),.SR(1'b0),.Q(txclk));
    
    // VIO controls:
    // cout_byte (8 bits)
    // cout_load (1 bit)
    // idelay_rst (1 bit)
    // idelay_rdy (1 bit in)
    // tgt_idelay (9 bits)
    // cur_idelay (9 bits in)
    // iserdes_rst (1 bit)
    // oserdes_rst (1 bit)
    // and then an ILA for cin_iserdes (8 bits)
    turfio_protovio u_vio(.clk(sys_clk),
                          .probe_in0(idelay_rdy),
                          .probe_in1(cur_idelay),
                          .probe_in2(sys_clk_x2_locked),
                          .probe_out0(cout_byte),
                          .probe_out1(cout_load),
                          .probe_out2(idelay_rst),
                          .probe_out3(tgt_idelay),
                          .probe_out4(iserdes_rst),
                          .probe_out5(oserdes_rst),
                          .probe_out6(bitslip),
                          .probe_out7(bitslip_rst));
    turfio_protoila u_ila(.clk(sys_clk),
                          .probe0(cur_data),
                          .probe1(fifo_empty),
                          .probe2(cin_iserdes[3:0]));                          
endmodule

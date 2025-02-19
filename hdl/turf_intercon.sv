`timescale 1ns / 1ps
`include "interfaces.vh"

// TURF interconnect. Plan for 4 slave spaces at the moment, plenty of room for more.
// Only one master planned for the moment since this is only a *local* intercon.
// Probably will have a global intercon for everything.
// Update: Maybe not! We'll try a global intercon here just for funsies. 
module turf_intercon(
        input clk_i,
        input rst_i,
        // Master
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 28, 32 ),
        // Slaves
        `HOST_NAMED_PORTS_WB_IF( turf_id_ctrl_ , 15, 32),
        `HOST_NAMED_PORTS_WB_IF( aurora_ , 15, 32),
        `HOST_NAMED_PORTS_WB_IF( ctl_ , 15, 32),
        `HOST_NAMED_PORTS_WB_IF( evctl_ , 15, 32),
        // Crate bridge space.
        `HOST_NAMED_PORTS_WB_IF( crate_ , 27, 32)     
    );    

    parameter DEBUG = "TRUE";
        
    // Address space selections work by masking off the
    // bit range that corresponds to each one and comparing
    // the inbound address.

    // Need to mask off the bottom 15 bits (those are for the modules to decode)
    // and since we only have 4 modules (2 bits) also mask off top 11 bits, less the top
    // which is used for the crate space.
    // Crate space masks off everything except the top bit.

    localparam [27:0] TURF_ID_CTRL_BASE = 28'h0000000;
    localparam [27:0] TURF_ID_CTRL_MASK = 28'h7FE7FFF;
    localparam [27:0] AURORA_BASE       = 28'h0008000;
    localparam [27:0] AURORA_MASK       = 28'h7FE7FFF;
    localparam [27:0] CTL_BASE          = 28'h0010000;
    localparam [27:0] CTL_MASK          = 28'h7FE7FFF;
    localparam [27:0] EVCTL_BASE       = 28'h0018000;
    localparam [27:0] EVCTL_MASK       = 28'h7FE7FFF;    
    // NOTE: Crate space will ALWAYS be the last listed
    // Add more as needed *above*
    localparam [27:0] CRATE_BASE        = 28'h8000000;
    localparam [27:0] CRATE_MASK        = 28'h7FFFFFF;
    // START BOILERPLATE INTERCONNECT
    localparam NUM_MASTERS = 1;
    localparam NUM_SLAVES = 5;    
    localparam ADDR_WIDTH = 28;
    localparam DATA_WIDTH = 32;
	wire [NUM_MASTERS-1:0] requests;
	wire [NUM_MASTERS-1:0] grants;
	wire [NUM_MASTERS-1:0] strobes;
	wire [NUM_MASTERS-1:0] writes;
	wire [NUM_MASTERS-1:0] acks;
	wire [NUM_MASTERS-1:0] errs;
	wire [NUM_MASTERS-1:0] rtys;
	
    wire [ADDR_WIDTH-1:0] addrs[NUM_MASTERS-1:0];
    wire [DATA_WIDTH-1:0] unmuxed_dat_o[NUM_MASTERS-1:0];
    wire [(DATA_WIDTH/8)-1:0] sels[NUM_MASTERS-1:0];

	wire muxed_ack;
	wire muxed_err;
	wire muxed_rty;
	// data TO the masters
	wire [DATA_WIDTH-1:0] muxed_dat_i;

	`define MASTER(x, y) \
		assign requests[ y ] = x``cyc_i; \
		assign strobes[ y ] = x``stb_i;  \
		assign writes[ y ] = x``we_i;	 \
		assign x``ack_o = acks[ y ];	    \
		assign x``err_o = errs[ y ];     \
		assign x``rty_o = rtys[ y ];     \
		assign addrs[ y ] = x``adr_i;    \
		assign unmuxed_dat_o[ y ] = x``dat_i; \
		assign sels[ y ] = x``sel_i;      \
		assign x``dat_o = muxed_dat_i        
    
    wishbone_arbiter #(.NUM_MASTERS(NUM_MASTERS))
        u_arbiter(.rst_i(rst_i),
                  .clk_i(clk_i),
                  .cyc_i(requests),
                  .gnt_o(grants));

    // Create the "common" WISHBONE bus. Just a reduction-or of the masked-off signals.
    wire cyc = |(requests & grants);
    wire stb = |(strobes & grants);
    wire we  = |(writes & grants);
    // And the returned values are just bitwise ands
    assign acks = {NUM_MASTERS{muxed_ack}} & grants;
    assign rtys = {NUM_MASTERS{muxed_rty}} & grants;
    assign errs = {NUM_MASTERS{muxed_err}} & grants;
    
    // Now do the multiplexed addresses, data, and selects.
    // Multiplexed address.
    wire [ADDR_WIDTH-1:0] adr;
    // Multiplexed to-slave data
    wire [DATA_WIDTH-1:0] dat_o;
    // Multiplexed select
    wire [(DATA_WIDTH/8)-1:0] sel;  
    
    // Let's test the tools
    function integer m_mux_encoder;
        input [NUM_MASTERS-1:0] grants;
        begin
            integer i;
            for (i=NUM_MASTERS-1;i>0;i--) begin
                if (grants[i]) return i;
            end
            return 0;
        end
    endfunction

    assign adr = addrs[m_mux_encoder(grants)];
    assign dat_o = unmuxed_dat_o[m_mux_encoder(grants)];
    assign sel = sels[m_mux_encoder(grants)];
    
    wire [NUM_SLAVES-1:0] selected;
    wire [DATA_WIDTH-1:0] unmuxed_dat_i[NUM_SLAVES-1:0];
    wire [NUM_SLAVES-1:0] s_acks;
    wire [NUM_SLAVES-1:0] s_rtys;
    wire [NUM_SLAVES-1:0] s_errs;
    `define SLAVE_MAP( prefix, number, mask, base)          \
        assign selected[number] = ((adr & ~mask) == base);  \
        assign unmuxed_dat_i[number] = prefix``dat_i;       \
        assign s_acks[number] = prefix``ack_i;              \
        assign s_rtys[number] = prefix``rty_i;              \
        assign s_errs[number] = prefix``err_i;              \
        assign prefix``cyc_o = cyc && selected[number];     \
        assign prefix``stb_o = stb && selected[number];     \
        assign prefix``we_o = we;                           \
        assign prefix``adr_o = (adr & mask);                \
        assign prefix``dat_o = dat_o;                       \
        assign prefix``sel_o = sel

    function integer s_mux_encoder;
        input [NUM_SLAVES-1:0] sels;
        begin
            integer i;
            for (i=NUM_SLAVES-1;i>0;i--) begin
                if (sels[i]) return i;
            end
            return 0;
        end
    endfunction

    assign muxed_ack = s_acks[s_mux_encoder(selected)];
    assign muxed_err = s_errs[s_mux_encoder(selected)];
    assign muxed_rty = s_rtys[s_mux_encoder(selected)];
    assign muxed_dat_i = unmuxed_dat_i[s_mux_encoder(selected)];

    // END BOILERPLATE
    
    // Map masters
    `MASTER( wb_ , 0);
    // Map slaves
    `SLAVE_MAP( turf_id_ctrl_ , 0 , TURF_ID_CTRL_MASK, TURF_ID_CTRL_BASE );
    `SLAVE_MAP( aurora_ , 1, AURORA_MASK, AURORA_BASE);
    `SLAVE_MAP( ctl_ , 2, CTL_MASK, CTL_BASE);
    `SLAVE_MAP( evctl_ , 3, EVCTL_MASK, EVCTL_BASE );

    `SLAVE_MAP( crate_ , NUM_SLAVES-1 , CRATE_MASK, CRATE_BASE );

    generate
        if (DEBUG == "TRUE") begin : ILA
            // Minimal internal WISHBONE bus. Combines bidir data into one.
            reg [DATA_WIDTH-1:0] dbg_data = {32{1'b0}};
            reg [ADDR_WIDTH-1:0] dbg_addr = {22{1'b0}};
            reg [(DATA_WIDTH/8)-1:0] dbg_sel = {(DATA_WIDTH/8){1'b0}};
            reg dbg_cyc = 0;
            reg dbg_stb = 0;
            reg dbg_ack = 0;
            reg dbg_we = 0;
            // I super-don't use err/rty so just combine them
            reg dbg_err_rty = 0;
            reg [NUM_MASTERS-1:0] dbg_gnt = {NUM_MASTERS{1'b0}};
            reg [NUM_SLAVES-1:0] dbg_ssel = {NUM_SLAVES{1'b0}};
            always @(posedge clk_i) begin
                if (we) dbg_data <= dat_o;
                else dbg_data <= muxed_dat_i;
                
                dbg_addr <= adr;
                dbg_cyc <= cyc;
                dbg_stb <= stb;
                dbg_we <= we;
                dbg_sel <= sel;
                dbg_ack <= muxed_ack;
                dbg_err_rty <= muxed_err | muxed_rty;
                dbg_gnt <= grants;
                dbg_ssel <= selected;
            end
            // 32
            // 28
            // 1
            // 1
            // 1
            // 4
            // 1
            // 1
            // 1
            // 5
            intercon_ila u_ila(.clk(clk_i),
                               .probe0(dbg_data),
                               .probe1(dbg_addr),
                               .probe2(dbg_cyc),
                               .probe3(dbg_stb),
                               .probe4(dbg_we),
                               .probe5(dbg_sel),
                               .probe6(dbg_ack),
                               .probe7(dbg_err_rty),
                               .probe8(dbg_gnt),
                               .probe9(dbg_ssel));
        end
    endgenerate
endmodule

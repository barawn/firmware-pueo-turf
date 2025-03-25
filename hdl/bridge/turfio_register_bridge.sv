`timescale 1ns / 1ps
// The TURF module has an overall 28-bit space from the processor.
// To keep things simple, that's what we'll limit ourselves to.
// So 27 bits for the TURF (overkill)
// and 27 bits for the total crate (addr[26:0])
// and 25 bits for each individual TURFIO space (addr[24:0] with [26:25] being the route)
// meaning 22 bits for each individual board
// which, wow, is what I already had
//
// I probably have to expand the board manager interface to add another
// byte to keep things the same between the TURF<->TURFIO interface
// and the debug interface.
//
// The register bridge here will have ALL possible interfaces to the TURFIO
// (Aurora, turfctl, and HK) and will take an input to decide which one to use.
// We also take a timeout parameter as well, which I absolutely need to figure out 
// but *must* occur by at least a second.

// NOTE NOTE NOTE NOTE NOTE
// Bytewise access controls (bridge_sel_i) are TOTALLY IGNORED here
// DON'T DO BYTEWISE ACCESSES TO THE CRATE SPACE

`include "interfaces.vh"
module turfio_register_bridge(
        input wb_clk_i,
        input wb_rst_i,
        // timeout happened. We will need a robust recovery method in case someone borks
        // something at some point. Think about that later. This DOES NOT WANT
        // to be a sticky bit: whatever module (probably turf_id_ctl) which contains
        // the bridge type register will make this sticky.
        output [3:0] timeout_reached_o,
        // invalid bridge transaction occurred. Also a flag.
        output [3:0] invalid_o,
        // x4 for each TURFIO space            
        // 00 = no bridge enabled
        // 01 = Aurora UFC
        // 10 = TURFCTL
        // 11 = HK serial
        input [7:0] bridge_type_i,

        // these jump us out if we already know the bridge isn't working
        // bridge_valid_i[0] is always 1
        // bridge_valid_i[1] is Aurora
        // bridge_valid_i[2] is TURFCTL
        // bridge_valid_i[3] is HK serial
        // x4 for each TURFIO
        input [15:0] bridge_valid_i,
        
        `TARGET_NAMED_PORTS_WB_IF( bridge_ , 27, 32 ),
        // Aurora path output
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_cmd_ , 32 ),
        output [1:0] m_cmd_tdest,
        output       m_cmd_tlast,
        // Aurora path return input. These are muxed. Tuser indicates where they came from.
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_resp_ , 32 ),
        input [1:0]  s_resp_tuser
    );

    parameter DEBUG = "TRUE";

    // worst-case would be a forwarded HK serial, which would require
    // something like 32 (addr) + 32 (data) times 2 since it's forwarded
    // or 128 bits = 16 bytes. at 115200, 1 byte is 0.0868 ms, so 16 = about
    // 1.4 ms. So if we set the timeout to 25 milliseconds, that should be more
    // than enough. With 1 clk = 10 ns, 25 ms = 2.5M
    localparam [47:0] TIMEOUT_VALUE = 48'd2500000;
    
    localparam [1:0] BRIDGE_TYPE_NONE = 2'b00;
    localparam [1:0] BRIDGE_TYPE_AURORA = 2'b01;
    localparam [1:0] BRIDGE_TYPE_TURFCTL = 2'b10;
    localparam [1:0] BRIDGE_TYPE_HKSERIAL = 2'b11;

    localparam FSM_BITS = 4;
    // start off
    localparam [FSM_BITS-1:0] IDLE = 0;
    // response phase
    localparam [FSM_BITS-1:0] RESPOND = 1;
    // Aurora address phase
    localparam [FSM_BITS-1:0] AURORA_ADDR = 2;
    // Aurora data phase if needed
    localparam [FSM_BITS-1:0] AURORA_DATA = 3;
    // Aurora response wait phase
    localparam [FSM_BITS-1:0] AURORA_RESP = 4;
    reg [FSM_BITS-1:0] state = IDLE;

    // vectorized bridge valids
    wire [3:0] bridge_valid_vec[3:0];
    assign bridge_valid_vec[0] = bridge_valid_i[0 +: 4];
    assign bridge_valid_vec[1] = bridge_valid_i[4 +: 4];
    assign bridge_valid_vec[2] = bridge_valid_i[8 +: 4];
    assign bridge_valid_vec[3] = bridge_valid_i[12 +: 4];
    // bridge type register captured
    reg [7:0] bridge_type_reg = {8{1'b0}};
    // and vectored
    wire [1:0] bridge_type_vec[3:0];
    assign bridge_type_vec[0] = bridge_type_reg[0 +: 2];
    assign bridge_type_vec[1] = bridge_type_reg[2 +: 2];
    assign bridge_type_vec[2] = bridge_type_reg[4 +: 2];
    assign bridge_type_vec[3] = bridge_type_reg[6 +: 2];

    // this determines where we're going
    wire [1:0] bridge_selection = bridge_adr_i[26:25];
                                                
    reg timeout_running = 0;

    reg [31:0] response_data = {32{1'b0}};

    wire timeout_reached;           
    dsp_counter_terminal_count #(.FIXED_TCOUNT("TRUE"),
                                 .FIXED_TCOUNT_VALUE(TIMEOUT_VALUE))
        u_timeout_counter( .clk_i(wb_clk_i),
                           .rst_i(!timeout_running),
                           .count_i(timeout_running),
                           .tcount_reached_o( timeout_reached ));                                 
            
    reg invalid = 0;

    // this gives us a way to dump all of the incoming data from resp path.
    reg no_aurora_bridge = 0;

    always @(posedge wb_clk_i) begin
        if (bridge_type_vec[0] != BRIDGE_TYPE_AURORA &&
            bridge_type_vec[1] != BRIDGE_TYPE_AURORA &&
            bridge_type_vec[2] != BRIDGE_TYPE_AURORA &&
            bridge_type_vec[3] != BRIDGE_TYPE_AURORA)
            no_aurora_bridge <= 1;
        else
            no_aurora_bridge <= 0;

        // only update when we're idle
        if (state == IDLE && (!bridge_cyc_i || !bridge_stb_i))
            bridge_type_reg <= bridge_type_i;

        if (wb_rst_i) timeout_running <= 1'b0;
        else begin
            if (state == IDLE && (bridge_cyc_i && bridge_stb_i)) timeout_running <= 1'b1;
            else if (state == RESPOND) timeout_running <= 1'b0;
        end

        if (wb_rst_i) state <= IDLE;
        else begin
            case (state)
                IDLE: if (bridge_cyc_i && bridge_stb_i) begin
                    // First figure out if the bridge is even valid.
                    if (!bridge_valid_vec[bridge_type_vec[bridge_selection]]) state <= RESPOND;
                    else begin
                        if (bridge_type_vec[bridge_selection] == BRIDGE_TYPE_AURORA) state <= AURORA_ADDR;
                        else state <= RESPOND;
                    end
                end
                // we ALWAYS send the address, but we don't always send the data.
                // but if we DON'T send the data we wait for the response.
                AURORA_ADDR: begin
                    if (timeout_reached) state <= RESPOND;
                    else begin
                        if (m_cmd_tready) begin
                            if (bridge_we_i) state <= AURORA_DATA;
                            else state <= AURORA_RESP;
                        end
                    end 
                end
                // if we're here, this is a write transaction
                // wait for data to accept and then we're done
                AURORA_DATA: begin
                    if (timeout_reached || m_cmd_tready) state <= RESPOND;
                end
                // if we're here, this is a read transaction
                // wait for data to arrive and then we're done
                // we also dump all non-requested data here
                AURORA_RESP: begin
                    if (timeout_reached) state <= RESPOND;
                    else begin
                        if (s_resp_tvalid && s_resp_tuser == bridge_selection) state <= RESPOND;
                    end
                end
                RESPOND: state <= IDLE;
            endcase
        end
        
        invalid <= (state == IDLE) && bridge_cyc_i && bridge_stb_i && !bridge_valid_vec[bridge_selection];
        
        if (timeout_reached) response_data <= {32{1'b1}};
        else if (bridge_type_vec[bridge_selection] == BRIDGE_TYPE_NONE) response_data <= {32{1'b1}};
        else if (state == AURORA_RESP && s_resp_tvalid) response_data <= s_resp_tdata;
    end

    generate
        if (DEBUG == "TRUE") begin : DBG
            wire [31:0] bridge_data_dbg = (bridge_we_i) ? bridge_dat_i : bridge_dat_o;
            wire bridge_access = bridge_cyc_i && bridge_stb_i;
            register_bridge_ila u_ila(.clk(wb_clk_i),
                                      .probe0(bridge_access),   // 1 bit                                      
                                      .probe1(bridge_adr_i),    // 27 bits
                                      .probe2(bridge_we_i),     // 1 bit
                                      .probe3(bridge_data_dbg), // 32 bits
                                      .probe4(m_cmd_tready),    // 1 bit
                                      .probe5(s_resp_tvalid),   // 1 bit
                                      .probe6(state));          // 4 bits
        end
    endgenerate

    // m_cmd_tvalid is AURORA_ADDR
    assign m_cmd_tvalid = (state == AURORA_ADDR || state == AURORA_DATA);
    // m_cmd_tdata bounces between data and address
    // address is 25 bits, plus write enable, so we need 6 empty bits
    assign m_cmd_tdata = (state == AURORA_DATA) ? bridge_dat_i :
                        { !bridge_we_i, {6{1'b0}}, bridge_adr_i[24:2], 2'b00 };
    // tlast gets asserted in AURORA_DATA or if there's no write transaction
    assign m_cmd_tlast = (!bridge_we_i || state == AURORA_DATA);
    // tdest is the bridge selection
    assign m_cmd_tdest = bridge_selection;
    // s_resp_tready is AURORA_RESP or always when no aurora bridge is selected
    assign s_resp_tready = (state == AURORA_RESP) || no_aurora_bridge;

    // ack is always RESPOND
    assign bridge_ack_o = (state == RESPOND);
    // both of these could be useful if I, y'know, actually implemented them
    assign bridge_err_o = 1'b0;
    assign bridge_rty_o = 1'b0;
    assign bridge_dat_o = response_data;
    
    assign timeout_reached_o[0] = (bridge_selection == 0) && timeout_reached;
    assign timeout_reached_o[1] = (bridge_selection == 1) && timeout_reached;
    assign timeout_reached_o[2] = (bridge_selection == 2) && timeout_reached;
    assign timeout_reached_o[3] = (bridge_selection == 3) && timeout_reached;

    assign invalid_o[0] = (bridge_selection == 0) && invalid;
    assign invalid_o[1] = (bridge_selection == 1) && invalid;
    assign invalid_o[2] = (bridge_selection == 2) && invalid;
    assign invalid_o[3] = (bridge_selection == 3) && invalid;        
endmodule

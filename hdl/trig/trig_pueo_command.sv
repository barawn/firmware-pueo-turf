`timescale 1ns / 1ps
`include "interfaces.vh"
// this doesn't just send trig commands, it also does runcmds and fwu data
//
// I need to rework the FWU here to match the TURFIO.
// In the TURFIO there's a 32-to-8 FIFO and you just
// blitz the FIFO. 
module trig_pueo_command(
        input wb_clk_i,
        input wb_rst_i,
        // we only need a small register space. Not really sure how to
        // divide up stuff yet for triggers. But we'll only take 8 bits.
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 8, 32 ),
        input sysclk_i,
        input sysclk_phase_i,
        input sysclk_sync_i,
        
        // pps needs to be in sysclk domain anyway and it's
        // stretched to be at least 8 clocks long.
        input pps_i,
        output runrst_o,
        output runstop_o,        
        // this is really only 15 bits
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_trig_ , 16),
        
        output [31:0] command67_o,
        output [31:0] command68_o
    );
    
    parameter WBCLKTYPE = "NONE";
    parameter SYSCLKTYPE = "NONE";
    // set upstream
    parameter [3:0] DEFAULT_RUNDLY = 4'h0;
    
    // Commands are captured BEFORE sysclk_phase_i so we can
    // change *in* sysclk_phase_i.
    // In order to match sysclk_sync_i we try sending when
    // sysclk_phase_i is high. Heck if I know if this works.
    // Honestly it doesn't actually matter except for checking.
    
    // sigh. the command stuff has changed so much.
    // Splitting the command up into message/trigger, we only muck with
    // two portions of the message: either the runcmd, or in FWU mode
    // the FWU data. (OMG WE CAN ACTUALLY DO FWU yes it's true)
    (* CUSTOM_CC_SRC = WBCLKTYPE *)    
    reg en_crate_pps = 0;
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [3:0] rundly = DEFAULT_RUNDLY;
    
    (* CUSTOM_CC_DST = SYSCLKTYPE, ASYNC_REG = "TRUE" *)
    reg [1:0] en_crate_pps_sysclk = {2{1'b0}};
    reg crate_pps = 0;
    
    reg [31:0] command = {32{1'b0}};
    
    wire send_runcmd_wbclk;
    wire send_runcmd;
    wire runcmd_complete;
    wire runcmd_complete_wbclk;
    reg runcmd_pending = 0;
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [1:0] runcmd_data = {2{1'b0}};
    
    wire send_fwu_wbclk;
    wire send_fwu;
    wire fwu_complete;
    wire fwu_complete_wbclk;
    reg fwu_pending = 0;
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg fwu_mark = 0;
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [7:0] fwu_data = {8{1'b0}};

    // source registers for the clock cross    
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg [7:0] dat_hold_wbclk = {8{1'b0}};
    (* CUSTOM_CC_SRC = WBCLKTYPE *)
    reg mark_hold_wbclk = 0;

    // this resolves to a NOOP if no mark is pending
    wire [7:0] mode1data = (fwu_pending && !fwu_mark) ? fwu_data : { {6{1'b0}}, fwu_mark, fwu_data[0] && fwu_mark};
    wire [1:0] mode1type = (fwu_pending && !fwu_mark) ? 2'd3 : 2'd0;    
    // Our sleazeball here is that we only send runcmds during sync
    // intervals. AAUUUGH this logic actually meant you sent TWO
    // of them!!
    wire runcmd_really_pending = runcmd_pending && sysclk_sync_i;
    wire [1:0] runcmd = (runcmd_really_pending) ? runcmd_data : 2'b00;
    
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] ISSUE_CMD = 1;
    localparam [FSM_BITS-1:0] WAIT_COMPLETE = 2;
    localparam [FSM_BITS-1:0] ACK = 3;
    reg [FSM_BITS-1:0] state = IDLE;
    
    // right now this is immensely stupid, we just check adr_i[2]: if it's 0, we're sending a runcmd,
    // otherwise we're sending FWU data, and if we send FWU data, bit 31 determines whether we're
    // sending FWU or mark.
    
    // update: check adr_i[3:2]:
    // 00 -> runcmd
    // 01 -> fwu
    // 10 -> control
    // 11 -> reserved
    wire RUNCMD_ADDR = (wb_adr_i[3:2] == 2'b00);
    wire FWU_ADDR = (wb_adr_i[3:2] == 2'b01);
    wire CONTROL_ADDR = (wb_adr_i[3:2] == 2'b10);
    wire RESERVED_ADDR = (wb_adr_i[3:2] == 2'b11);
        
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) state <= IDLE;
        else case (state)
            IDLE: if (wb_cyc_i && wb_stb_i) begin
                if (RESERVED_ADDR || CONTROL_ADDR) state <= ACK;
                else if (wb_we_i && wb_sel_i[0]) state <= ISSUE_CMD;
                else state <= ACK;
            end                
            ISSUE_CMD: state <= WAIT_COMPLETE;
            WAIT_COMPLETE: if (runcmd_complete_wbclk || fwu_complete_wbclk) state <= ACK;
            ACK: state <= IDLE;
        endcase
        
        if (state == ACK && CONTROL_ADDR && wb_we_i) begin
            if (wb_sel_i[0]) en_crate_pps <= wb_dat_i[0];
            if (wb_sel_i[1]) rundly <= wb_dat_i[8 +: 4];
        end
        
        // ok so this is dumb but it doesn't friggin matter
        if (state == IDLE && wb_cyc_i && wb_stb_i && wb_we_i) begin
            if (wb_sel_i[0]) dat_hold_wbclk <= wb_dat_i[7:0];
            if (wb_sel_i[3]) mark_hold_wbclk <= wb_dat_i[31];
        end        
    end
    
    //
    // The wait doesn't freaking matter. We could even do this with FWU data
    // the way we're doing it right now. But we'll be adding FIFO support
    // to FWU data later so it'll matter then. Blah blah blah.
    always @(posedge sysclk_i) begin
        en_crate_pps_sysclk <= {en_crate_pps_sysclk[0], en_crate_pps};
        crate_pps <= (en_crate_pps_sysclk[1] && pps_i);
        
        // the request ALWAYS has priority.
        // if we're currently IN the phase we're going to send,
        if (send_runcmd) runcmd_pending <= 1;
        else if (sysclk_phase_i && sysclk_sync_i) runcmd_pending <= 0;

        if (send_runcmd) runcmd_data <= dat_hold_wbclk[1:0];

        if (send_fwu) fwu_pending <= 1;
        else if (sysclk_phase_i) fwu_pending <= 0;
        
        if (send_fwu) begin
            fwu_mark <= mark_hold_wbclk;
            fwu_data <= dat_hold_wbclk;
        end
        
        // HANDLE MESSAGE SIDE OF COMMAND
        if (sysclk_phase_i) begin
            command[31] <= ~(runcmd_really_pending || fwu_pending || crate_pps);
            // pps
            command[30] <= crate_pps;
            // reserved
            command[29:28] <= 2'b00;
            // runcmd
            command[27:26] <= runcmd;
            // mode1
            command[25:24] <= mode1type;
            command[23:16] <= mode1data;
            command[15] <= s_trig_tvalid;
            command[14:0] <= s_trig_tdata[14:0];
        end        
    end

    // this makes it so that 0x0 sends a runcmd, 0x4 sends fwu (mark OR data)
    assign send_runcmd_wbclk = (state == ISSUE_CMD && RUNCMD_ADDR);
    assign send_fwu_wbclk = (state == ISSUE_CMD && FWU_ADDR);
    assign fwu_complete = (fwu_pending && sysclk_phase_i);
    assign runcmd_complete = (runcmd_really_pending && sysclk_phase_i);
    
    // flag syncs
    flag_sync u_send_runcmd_sync(.in_clkA(send_runcmd_wbclk),.out_clkB(send_runcmd),
                                 .clkA(wb_clk_i),.clkB(sysclk_i));
    flag_sync u_send_fwu_sync(.in_clkA(send_fwu_wbclk),.out_clkB(send_fwu),
                              .clkA(wb_clk_i),.clkB(sysclk_i));    
    flag_sync u_runcmd_complete_sync(.in_clkA(runcmd_complete),.out_clkB(runcmd_complete_wbclk),
                                     .clkA(sysclk_i),.clkB(wb_clk_i));
    flag_sync u_fwu_complete_sync(.in_clkA(fwu_complete),.out_clkB(fwu_complete_wbclk),
                                  .clkA(sysclk_i),.clkB(wb_clk_i));   

    // the way the programmable rundelay works is that it's an
    // additional delay on top of the 34-clock delay
    // don't even ASK me where the overall 34-clock delay comes from, I am so confused
    wire base_runrst = (sysclk_phase_i && runcmd == 2);
    wire mid_runrst;
    wire fin_runrst;
    // SRLs are both registered and combinatoric, so these have a dest path too
    // It's not asynchronous though because rundly is static when the actually commands are issued.
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg runrst_delayed = 0;
    wire base_runstop = (sysclk_phase_i && runcmd == 3);
    wire mid_runstop;
    wire fin_runstop;
    // ditto to runrst
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg runstop_delayed = 0;
    SRLC32E u_runreset_dlyA(.D(base_runrst),
                            .CE(1'b1),
                            .CLK(sysclk_i),
                            .Q31(mid_runrst));
    SRLC32E u_runstop_dlyA(.D(base_runstop),
                           .CE(1'b1),
                           .CLK(sysclk_i),
                           .Q31(mid_runstop));
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    SRL16E u_runreset_dlyB(.D(mid_runrst),
                           .CE(1'b1),
                           .CLK(sysclk_i),
                           .A0(rundly[0]),
                           .A1(rundly[1]),
                           .A2(rundly[2]),
                           .A3(rundly[3]),
                           .Q(fin_runrst));
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    SRL16E u_runstop_dlyB(.D(mid_runstop),
                          .CE(1'b1),
                          .CLK(sysclk_i),
                          .A0(rundly[0]),
                          .A1(rundly[1]),
                          .A2(rundly[2]),
                          .A3(rundly[3]),
                          .Q(fin_runstop));
    always @(posedge sysclk_i) begin
        runrst_delayed <= fin_runrst;
        runstop_delayed <= fin_runstop;
    end                                 
    // ack
    assign wb_ack_o = (state == ACK);
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    assign wb_dat_o = { {16{1'b0}}, {4{1'b0}}, rundly, {7{1'b0}}, en_crate_pps };
    
    assign s_trig_tready = s_trig_tvalid && sysclk_phase_i;

    assign runrst_o = runrst_delayed;
    assign runstop_o = runstop_delayed;

    assign command67_o = command;
    assign command68_o = command;
        
endmodule

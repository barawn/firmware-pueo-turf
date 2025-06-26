`timescale 1ns / 1ps
`include "interfaces.vh"
// The register core in the time wrapper has a LOT
// of clock domain jumping. Need to be careful, but
// we don't really have to worry about the clock
// not running since it's basically guaranteed.
module pueo_time_wrap_v2 #(parameter SYSCLKTYPE = "NONE",
                        parameter WBCLKTYPE = "NONE",
                        parameter MEMCLKTYPE = "NONE")(
        input wb_clk_i,
        input wb_rst_i,
        `TARGET_NAMED_PORTS_WB_IF( wb_ , 13, 32 ),
        input sys_clk_i,
        input pps_i,
        output pps_dbg_o,
        input runrst_i,
        
        input trig_dead_i,
        
        input [3:0] panic_count_i,
        input panic_count_ce_i,
        input memclk_i,
        
        output pps_pulse_o,
        
        output pps_flag_o,
        output [31:0] cur_sec_o,
        output [31:0] cur_time_o,
        output [31:0] last_pps_o,
        output [31:0] llast_pps_o,
        output [31:0] cur_dead_o,
        output [31:0] last_dead_o,
        output [31:0] llast_dead_o
    );
    
    // whatever just make it work
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [31:0] pps_holdoff_counter = {32{1'b0}};
    // this is upshifted in units of 4096 clocks
    // which puts the max over a second and the min
    // at like 32 microseconds.
    wire [15:0] pps_holdoff;
    // 12 at bottom, 16 programmable, 4 useless at top
    wire [31:0] pps_holdoff_expanded = { {4{1'b0}}, pps_holdoff, {12{1'b1}} };
    
    wire int_pps;
    wire en_int_pps;
    wire use_ext_pps;
    wire update_pps_trim;
    wire [15:0] int_pps_trim;
    wire [15:0] int_pps_trim_out;
    
    internal_pps #(.SYSCLKTYPE(SYSCLKTYPE),
                   .WBCLKTYPE(WBCLKTYPE))
                   u_intpps(.sysclk_i(sys_clk_i),
                            .wbclk_i(wb_clk_i),
                            .en_i(en_int_pps),
                            .trim_i(int_pps_trim),
                            .update_trim_i(update_pps_trim),
                            .trim_o(int_pps_trim_out),
                            .pps_o(int_pps));

    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [1:0] use_ext_pps_sysclk = 2'b00;
    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg pps_reg = 0;
    reg pps_rereg = 0;
    reg pps_flag = 0;
    wire pps_flag_wbclk;
    reg pps_in_holdoff = 0;

    wire [31:0] update_second;  // in wbclk
    wire        load_second;    // in sysclk
    (* CUSTOM_CC_DST = SYSCLKTYPE, CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg [31:0]  cur_second = {32{1'b0}};
    (* USE_DSP = "TRUE" *)
    reg [31:0]  cur_time = {32{1'b0}};
    reg [31:0]  last_pps = {32{1'b0}};
    reg [31:0]  llast_pps = {32{1'b0}};
    (* USE_DSP = "TRUE" *)
    reg [31:0]  cur_dead = {32{1'b0}};
    reg [31:0]  last_dead = {32{1'b0}};
    reg [31:0]  llast_dead = {32{1'b0}};

    (* USE_DSP = "TRUE" *)
    reg [31:0]  cur_panic = {32{1'b0}};
    reg [31:0]  last_panic = {32{1'b0}};
    (* CUSTOM_CC_DST = SYSCLKTYPE, KEEP = "TRUE" *)
    reg [3:0]   cur_count_sysclk = {4{1'b0}};
    reg [3:0]   cur_count_sysclk_sync = {4{1'b0}};
    reg [1:0]   count_sysclk_rereg = {2{1'b0}};
    wire count_sysclk;
    flag_sync u_sync_count(.in_clkA(panic_count_ce_i),.out_clkB(count_sysclk),
                           .clkA(memclk_i),.clkB(sys_clk_i));
        
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0] pps_dbg_wbclk = {2{1'b0}};
    always @(posedge wb_clk_i) pps_dbg_wbclk <= { pps_dbg_wbclk[0], pps_reg };
    
    always @(posedge sys_clk_i) begin
        count_sysclk_rereg <= { count_sysclk_rereg[0], count_sysclk };

        if (count_sysclk) cur_count_sysclk <= panic_count_i;
        if (count_sysclk_rereg[0]) cur_count_sysclk_sync <= cur_count_sysclk;
        
        if (pps_flag) cur_panic <= {32{1'b0}};
        else if (count_sysclk_rereg[1]) cur_panic <= cur_panic + cur_count_sysclk_sync;
        
        if (pps_flag) last_panic <= cur_panic;
         
        // you HAVE to leave it running because you want
        // a posedge no matter what. The holdoff just prevents
        // the flag assertion.
        pps_reg <= pps_i;
        pps_rereg <= pps_reg;

        if (!use_ext_pps_sysclk[1]) pps_in_holdoff <= 0;
        else if (pps_flag) pps_in_holdoff <= 1;
        else if (pps_holdoff_counter == 0) pps_in_holdoff <= 0;
        
        if (!pps_in_holdoff) pps_holdoff_counter <= pps_holdoff_expanded;
        else pps_holdoff_counter <= pps_holdoff_counter - 1;
                
        use_ext_pps_sysclk <= {use_ext_pps_sysclk[0], use_ext_pps};
        pps_flag <= (use_ext_pps_sysclk[1]) ? pps_reg && !pps_rereg && !pps_in_holdoff:
                                              int_pps;

        if (load_second) cur_second <= update_second;
        else if (pps_flag) cur_second <= cur_second + 1;

        if (runrst_i) cur_time <= {32{1'b0}};
        else cur_time <= cur_time + 1;

        if (runrst_i) cur_dead <= {32{1'b0}};
        else if (trig_dead_i) cur_dead <= cur_dead + 1;
                
        if (pps_flag) begin
            last_pps <= cur_time;
            llast_pps <= last_pps;
            last_dead <= cur_dead;
            llast_dead <= last_dead;
        end
    end

    pueo_time_register_core_v2 #(.WBCLKTYPE(WBCLKTYPE),
                              .SYSCLKTYPE(SYSCLKTYPE))
            u_core(.wb_clk_i(wb_clk_i),
                   .wb_rst_i(1'b0),
                   .sys_clk_i(sys_clk_i),
                   `CONNECT_WBS_IFS(wb_ , wb_ ),
                   // pps holdoff
                   .pps_holdoff_o(pps_holdoff),
                   // enable the internal pps
                   .en_int_pps_o(en_int_pps),
                   // use the external PPS
                   .use_ext_pps_o(use_ext_pps),
                   // update the internal PPS trim
                   .update_pps_trim_o(update_pps_trim),
                   // next PPS trim
                   .pps_trim_o(int_pps_trim),
                   // current PPS trim
                   .pps_trim_i(int_pps_trim_out),
                   // update the PPS second to this value
                   .update_sec_o(update_second),
                   // load the updated second
                   .load_sec_o(load_second),
                   // note! these are in sysclk,
                   // so we need ADDITIONAL holding
                   // registers which act as cross-clocks.
                   // JOY.
                   .cur_sec_i(cur_second),
                   .last_pps_i(last_pps),
                   .llast_pps_i(llast_pps),
                   .last_dead_i(last_dead),
                   .llast_dead_i(llast_dead),
                   .last_panic_i(last_panic));    

    assign cur_sec_o = cur_second;
    assign cur_time_o = cur_time;
    assign last_pps_o = last_pps;
    assign llast_pps_o = llast_pps;
    assign cur_dead_o = cur_dead;
    assign last_dead_o = last_dead;
    assign llast_dead_o = llast_dead;
    
    assign pps_pulse_o = pps_in_holdoff;
    assign pps_dbg_o = pps_dbg_wbclk[1];
    assign pps_flag_o = pps_flag;        
endmodule

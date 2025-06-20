`timescale 1ns / 1ps
module pueo_scaler_core #(parameter SYSCLKTYPE="NONE",
                          parameter WBCLKTYPE="NONE",
                          parameter ETHCLKTYPE="NONE")(
        input sysclk_i,
        
        input wb_clk_i,
        input [4:0] wb_adr_i,
        output [15:0] wb_dat_o,
        
        input [4:0] sys_adr_i,
        output [15:0] sys_dat_o,
        
        // in case we actually create a status port
        input eth_clk_i,
        input [4:0] eth_adr_i,
        output [15:0] eth_dat_o,
        
        input pps_i,
        input gate_i,
        input [31:0] gate_en_i,
        input [31:0] trig_i        
    );
    
    // no prescalers right now, I __just__ want to get this working.
    wire [15:0] sysclk_hold[31:0];
    // enable if gate_i or if no gate enable is spec'd
    wire [31:0] channel_gate = {32{gate_i}} | ~gate_en_i;
    generate
        genvar i;
        for (i=0;i<32;i=i+1) begin : CHL
            reg trig_rereg = 0;
            reg [15:0] channel_counter = {16{1'b0}};
            wire [16:0] channel_counter_plus_one = channel_counter + 1;
            reg        saturation = 0;
            reg [15:0] channel_hold = {16{1'b0}};
            always @(posedge sysclk_i) begin : CHLG
                if (pps_i) 
                    channel_counter <= {16{1'b0}};
                else if (trig_i[i] && !trig_rereg && channel_gate[i])
                    channel_counter <= channel_counter_plus_one;
                
                trig_rereg <= trig_i[i];
                
                if (pps_i) 
                    saturation <= 0;
                else if (channel_counter_plus_one[16] && trig_i[i] && channel_gate[i])
                    saturation <= 1'b1;
                    
                if (pps_i) begin
                    if (saturation) channel_hold <= {16{1'b1}};
                    else channel_hold <= channel_counter;
                end
            end
            assign sysclk_hold[i] = channel_hold;            
        end        
    endgenerate    

    (* CUSTOM_CC_SRC = SYSCLKTYPE *)
    reg active_bank = 0;
    (* CUSTOM_CC_DST = WBCLKTYPE *)
    reg [1:0] active_bank_wbclk = {2{1'b0}};
    (* CUSTOM_CC_DST = ETHCLKTYPE *)
    reg [1:0] active_bank_ethclk = {2{1'b0}};


    reg [5:0] update_counter = {6{1'b0}};
    reg [15:0] update_mux_in = {16{1'b0}};
    reg        updating = 0;
    reg        update_wr = 0;
    
    wire [5:0] update_address = { ~active_bank, update_counter[4:0] };
    wire [5:0] wb_address = { active_bank_wbclk[1], wb_adr_i[4:0] };
    wire [5:0] sys_address = { active_bank, sys_adr_i[4:0] };
    wire [5:0] eth_address = { active_bank_ethclk[1], eth_adr_i[4:0] };
    // clk  pps     updating    update_counter  update_wr   update_mux_in
    // 0    1       0           0               0           0
    // 1    0       1           0               0           0
    // 2    0       1           1               1           SC[0]
    // 3    0       1           2               1           SC[1]
    // ..
    // 30   0       1           29              1           SC[28]
    // 31   0       1           30              1           SC[29]
    // 32   0       1           31              1           SC[30]
    // 33   0       1           32              1           SC[31]
    // 34   0       0           1               0           X
    // 35   0       0           0               0           X               
    always @(posedge sysclk_i) begin
        if (pps_i) updating <= 1;
        else if (update_counter[5]) updating <= 0;
        
        if (!updating) update_counter <= {6{1'b0}};
        else update_counter <= update_counter[4:0] + 1;

        if (updating) update_mux_in <= sysclk_hold[update_counter];

        if (update_counter[5]) update_wr <= 0;
        else update_wr <= updating;
        
        if (update_counter[5]) active_bank <= ~active_bank;
    end

    always @(posedge wb_clk_i) begin
        active_bank_wbclk <= {active_bank_wbclk[0], active_bank };
    end
    
    always @(posedge eth_clk_i) begin
        active_bank_ethclk <= {active_bank_ethclk[0], active_bank };
    end        
    
    generate
        genvar d;
        for (d=0;d<16;d=d+1) begin
            (* CUSTOM_CC_SRC = SYSCLKTYPE *)
            RAM64M u_rambit(.DIA(update_mux_in[d]),
                            .DIB(update_mux_in[d]),
                            .DIC(update_mux_in[d]),
                            .DID(update_mux_in[d]),
                            .ADDRA(eth_address),
                            .ADDRB(wb_address),
                            .ADDRC(sys_address),
                            .ADDRD(update_address),
                            .DOA(eth_dat_o[d]),
                            .DOB(wb_dat_o[d]),
                            .DOC(sys_dat_o[d]),
                            .WE(update_wr),
                            .WCLK(sysclk_i));
        end
    endgenerate
endmodule

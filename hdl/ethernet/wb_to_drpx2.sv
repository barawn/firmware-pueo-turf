`timescale 1ns / 1ps
`include "interfaces.vh"
module wb_to_drpx2(
        input wb_clk_i,
        `TARGET_NAMED_PORTS_WB_IF(wb_ , 13, 32),
        output [1:0] drpen,
        output drpwe,
        output [9:0] drpaddr,
        input [1:0] drprdy,
        input [31:0] drpdo,
        output [15:0] drpdi
    );
    
    reg drp_waiting = 0;
    assign drpaddr = wb_adr_i[2 +: 10];
    assign drpdi = wb_dat_i[15:0];
    assign drpwe = wb_we_i;
    assign drpen[0] = !drp_waiting && wb_cyc_i && wb_stb_i && !wb_adr_i[12];
    assign drpen[1] = !drp_waiting && wb_cyc_i && wb_stb_i && wb_adr_i[12];
    
    always @(posedge wb_clk_i) begin
        if ((drprdy[0] && !wb_adr_i[12]) || (drprdy[1] && wb_adr_i[12]))
            drp_waiting <= 1'b0;
        else if (wb_cyc_i && wb_stb_i)
            drp_waiting <= 1'b1;
    end

    assign wb_dat_o[15:0] = (wb_adr_i[12]) ? drpdo[16 +: 16] : drpdo[0 +: 16];
    assign wb_dat_o[31:16] = {16{1'b0}};
    assign wb_ack_o = drp_waiting && 
        ((drprdy[0] && !wb_adr_i[12]) || (drprdy[1] && wb_adr_i[12]));
    assign wb_err_o = 1'b0;
    assign wb_rty_o = 1'b0;
    
endmodule

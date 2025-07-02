`timescale 1ns / 1ps
// handle the GPO multiplexing
// ALL GPOs NEED TO RUN IN SYSCLK DOMAIN
// JUST GODDAMN DEAL WITH IT
module turf_gpo_mux #(parameter SYSCLKTYPE = "NONE")(
        input sysclk_i,
        input gpo_en_i,
        input [2:0] gpo_select_i,
        
        input gpo_sync_ce_i,
        input gpo_sync_d_i,
        
        input gpo_run_ce_i,
        input gpo_run_d_i,
        
        input gpo_trig_ce_i,
        input gpo_trig_d_i,
        
        input gpo_pps_ce_i,
        input gpo_pps_d_i,
        
        output GPO
    );
    
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [1:0] gpo_en_sysclk = {2{1'b0}};
    // only change this when gpo is disabled
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [2:0] gpo_select_sysclk = {3{1'b0}};
        
    always @(posedge sysclk_i) begin
        gpo_en_sysclk <= { gpo_en_sysclk[0], gpo_en_i };
        gpo_select_sysclk <= gpo_select_i;
    end

    wire [3:0] gpo_ce_vec = { gpo_pps_ce_i, gpo_trig_ce_i, gpo_run_ce_i, gpo_sync_ce_i };
    wire [3:0] gpo_d_vec = { gpo_pps_d_i, gpo_trig_d_i, gpo_run_d_i, gpo_sync_d_i };

    wire gpo_ce = gpo_ce_vec[gpo_select_sysclk[1:0]];
    wire gpo_d = gpo_d_vec[gpo_select_sysclk[1:0]];
    
    (* IOB = "TRUE" *)
    FDRE u_gporeg(.R(!gpo_en_sysclk[1]),
                  .C(sysclk_i),
                  .CE(gpo_ce),
                  .D(gpo_d),
                  .Q(GPO));
        
    
endmodule

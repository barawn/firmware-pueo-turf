`timescale 1ns / 1ps
// OK, this needs to be a bit tricky.
// We basically want to define this that the sync command comes out
// when, in the *next phase*, SYNC should go high.
// This means from a bitcommand standpoint we want to send it when
// sync *is* high, because we get
//      <64ns><64ns><64ns>
// sync 1     0     1
// cmd  sync  xxxx  xxxx
// COUT xxxx  sync  xxxx
//
// The command encoder captures on phase 6, so if we want the command
// forwarded, we need to present earlier than that. We can do this on
// phase 2.

// And then the delay we program in ends up being the pure overall
// latencies involved.
// We also don't bother with "acks". We know bitcommands are captured late
// in the phase.
//
// NOTE: Bitcommands can be combined (sync is just bitcommand[0])
// so they can all come from wherever they want.
module sysclk_sync_req(
        input sysclk_i,
        input sysclk_phase_i,
        input sysclk_sync_i,
        input sync_req_i,
        output sync_bitcommand_o
    );
    
    // synchronize the request
    (* ASYNC_REG = "TRUE", CUSTOM_CC_DST = "SYSCLK" *)
    reg [1:0] sync_req = {2{1'b0}};
    
    // phase buffer. this goes high in phase 1
    reg sysclk_phase_1 = 0;
    reg sync_bitcommand = 0;
    reg sync_req_rereg = 0;
    reg sync_pending = 0;
        
    always @(posedge sysclk_i) begin
        sync_req <= {sync_req[0], sync_req_i};
        sysclk_phase_1 <= sysclk_phase_i;
        
        sync_req_rereg <= sync_req[1];
        
        if (sync_req[1] && !sync_req_rereg) sync_pending <= 1;
        else if (sync_bitcommand_o) sync_pending <= 0;
        
        if (sysclk_phase_1) begin
            if (sync_pending && sysclk_sync_i) sync_bitcommand <= 1;
            else sync_bitcommand <= 0;
        end
    end

    assign sync_bitcommand_o = sync_bitcommand;
        
endmodule

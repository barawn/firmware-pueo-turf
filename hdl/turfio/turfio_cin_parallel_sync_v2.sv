`timescale 1ns / 1ps
// This is *almost* the same as the TURFIO's module, except we *also* implement bitslip functionality.
//
// v2 changes things. We ENTIRELY drop locking. We don't need it.
// The SURF syncs up to us, if things aren't aligned, that's bad
// and needs to be fixed.
// We also get rid of the roundtrip delay crap. It's implicitly
// automatic when we program in the phase delay offset.
// And finally, when enabled we actually capture twice, and only output 16 bits
// because triggers have a granularity of 16 bits.
module turfio_cin_parallel_sync_v2(
        // interface clock
        input ifclk_i,
        // interface clock phase (indicates cycle 0 of 8-clock IFCLK cycle)
        input ifclk_phase_i,
        // phase offset
        input [2:0] offset_i,
        // reset the bitslip
        input rst_bitslip_i,
        // parallel, unaligned 4-bit input stream
        input [3:0] cin_i,
        // instruct module to capture even though we're not aligned
        input capture_i,
        // flag indicating that the capture request has completed
        input captured_i,
        // instruct module to slip a bit forward
        input bitslip_i,
        // enable (shuts up the biterr counter and drives valid)
        input enable_i,
        // parallel output. Bottom 16 bits only when properly running.
        output [31:0] cin_parallel_o,
        // output is valid
        output cin_parallel_valid_o,
        // bit error happened (when not locked only!!)
        output cin_biterr_o        
    );
    
    parameter [31:0] TRAIN_SEQUENCE = 32'hA55A6996;
    parameter DEBUG = "TRUE";
    parameter CLKTYPE = "IFCLK67";
    
    wire [3:0] cin_align;
    bit_align u_aligner(.din(cin_i),
                        .dout(cin_align),
                        .slip(bitslip_i),
                        .rst(rst_bitslip_i),
                        .clk(ifclk_i));
    
    reg [27:0] cin_history = {28{1'b0}};
    wire [31:0] current_cin = { cin_align, cin_history };
    // this is TECHNICALLY a clock-crossed register because it thinks capture_i can be async
    (* CUSTOM_CC_DST = CLKTYPE, CUSTOM_CC_SRC = CLKTYPE *)
    reg [31:0] cin_capture = {32{1'b0}};
    
    // The way we handle capturing is to just not update
    // during the time the cross happens.
    reg capture_hold = 0;
    // set when data is valid
    reg valid = 0;
    // when set we capture
    reg enable_capture = 0;
    // when set we shift the output down to reduce to 16 bits.
    // This is a 4 clock delay: we need to go
    // enable_capture   srl     shift_capture
    // 1                0000    0
    // 0                0001    0
    // 0                0002    0
    // 0                0004    0
    // 0                0008    1
    // 0                0010    0
    // 0                0020    0
    // 0                0040    0
    // so we grab address 3
    wire shift_capture;
    SRL16E u_shift_delay(.D(enable_capture),
                         .CE(enable_i),
                         .CLK(ifclk_i),
                         .A0(1),
                         .A1(1),
                         .A2(0),
                         .A3(0),
                         .Q(shift_capture));
    
    
    // this is the sequence track based on the phase input
    reg [2:0] ifclk_phase_counter = {3{1'b0}};
    // this buffers the input signal
    reg ifclk_phase_buf = 0;

    // BIT ERROR GENERATION
    wire [3:0] cin_delayed;
    reg cin_biterr = 0;
    assign cin_biterr_o = cin_biterr;
    srlvec #(.NBITS(4)) u_cin_srl(.clk(ifclk_i),
                                  .ce(1'b1),
                                  .a(4'h7),
                                  .din(cin_history[3:0]),
                                  .dout(cin_delayed));


    // SYNCHRONIZATION
    // We have an 8-clock sequence, so the way this works is:
    //
    // clk  current_cin     enable_lock locked  sysclk_sequence enable_capture  cin_capture
    // 7    TRAIN_SEQUENCE  1           0       0               0               X
    // 0    X               1           1       0               0               X
    // 1    X               1           1       1               0               X
    // 2    X               1           1       2               0               X
    // 3    X               1           1       3               0               X
    // 4    X               1           1       4               0               X
    // 5    X               1           1       5               0               X
    // 6    X               1           1       6               0               X
    // 7    TRAIN_SEQUENCE  1           1       7               1               X
    // 0    X               1           1       8               0               TRAIN_SEQUENCE
    //
    // We delay the locked input because it doesn't matter and it simplifies the counter.
    // It's just a delay so we can use an SRL with address set to 7 for it.
    always @(posedge ifclk_i) begin
        if (capture_i) capture_hold <= 1;
        else if (captured_i) capture_hold <= 0;
    
        ifclk_phase_buf <= ifclk_phase_i;
        // ifclk_phase_i going high means phase 0
        // ifclk_phase_buf going high means phase 1
        // therefore we reset to phase 2
        if (ifclk_phase_buf) ifclk_phase_counter <= 3'd2;
        else ifclk_phase_counter <= ifclk_phase_counter + 1;
            
        cin_history[24 +: 4] <= cin_align;
        cin_history[20 +: 4] <= cin_history[24 +: 4];
        cin_history[16 +: 4] <= cin_history[20 +: 4];
        cin_history[12 +: 4] <= cin_history[16 +: 4];
        cin_history[8 +: 4] <= cin_history[12 +: 4];
        cin_history[4 +: 4] <= cin_history[8 +: 4];
        cin_history[0 +: 4] <= cin_history[4 +: 4];
                
        enable_capture <= ifclk_phase_counter == offset_i;
                
        if (enable_capture && !capture_i && !capture_hold) begin
            cin_capture <= current_cin;
        end else if (shift_capture) begin
            // Always shift down.
            cin_capture[15:0] <= cin_capture[31:16];
        end
        
        valid <= (enable_capture || shift_capture) && enable_i;
        
        if (enable_i) cin_biterr <= 1'b0;
        else cin_biterr <= (cin_history[3:0] != cin_delayed[3:0]);        
    end

    generate
        if (DEBUG == "TRUE") begin : ILA
            // 32 bits: current_cin
            // 3 bits ifclk_phase_counter
            // 1 bit enable_capture
            // 1 bit ifclk_phase_buf
            // 1 bit biterr
            cin_parallel_ila u_ila(.clk(ifclk_i),
                                   .probe0(current_cin),
                                   .probe1(ifclk_phase_counter),
                                   .probe2(enable_capture),
                                   .probe3(ifclk_phase_buf),
                                   .probe4(cin_biterr),
                                   .probe5(shift_capture));
        end
    endgenerate
    assign cin_parallel_valid_o = valid;
    assign cin_parallel_o = cin_capture;
    
endmodule

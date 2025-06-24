`timescale 1ns / 1ps
// This is *almost* the same as the TURFIO's module, except we *also* implement bitslip functionality.
module turfio_cin_parallel_sync(
        // interface clock
        input ifclk_i,
        // interface clock phase (indicates cycle 0 of 8-clock IFCLK cycle)
        input ifclk_phase_i,
        // reset the lock (NOT the bitslip)
        input rst_lock_i,
        // reset the bitslip (NOT the lock)
        input rst_bitslip_i,
        // parallel, unaligned 4-bit input stream
        input [3:0] cin_i,
        // instruct module to capture even though we're not aligned
        input capture_i,
        // instruct module to slip a bit forward
        input bitslip_i,
        // lock onto the next correct training sequence
        input lock_i,
        // training sequence is locked
        output locked_o,
        // parallel output
        output [31:0] cin_parallel_o,
        // output is valid
        output cin_parallel_valid_o,
        // round-trip delay
        output [2:0] cin_roundtrip_o,
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
    reg enable_capture = 0;
    wire do_cin_capture = enable_capture || capture_i;
    reg enable_lock = 0;
    (* CUSTOM_CC_SRC = CLKTYPE *)    
    reg locked = 0;
    // this is the sequence track for the *input*. It is unaligned to phase (other than our sync procedure)
    reg [3:0] ifclk_sequence = {4{1'b0}};

    // this is the sequence track based on the phase input
    reg [2:0] ifclk_phase_counter = {3{1'b0}};
    // this buffers the input signal
    reg ifclk_phase_buf = 0;

    // this is the captured round-trip delay. if the valid is high in clock 0, this measures 0 (so it's mod 8).
    // We don't actually care about the *actual* "round-trip" delay (as in, something like a ping->pong response)
    // we actually just care about when the "sync" command is issued, how long does it take the now-phase locked
    // training output to return back.
    // In other words this is more like a one-way propagation delay.
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg [2:0] roundtrip = {3{1'b0}};

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
    wire [3:0] cin_delayed;
    reg cin_biterr = 0;
    assign cin_biterr_o = cin_biterr;
    srlvec #(.NBITS(4)) u_cin_srl(.clk(ifclk_i),
                                  .ce(1'b1),
                                  .a(4'h7),
                                  .din(cin_history[3:0]),
                                  .dout(cin_delayed));
    always @(posedge ifclk_i) begin
        ifclk_phase_buf <= ifclk_phase_i;
        // ifclk_phase_i going high means phase 0
        // ifclk_phase_buf going high means phase 1
        // therefore we reset to phase 2
        if (ifclk_phase_buf) ifclk_phase_counter <= 3'd2;
        else ifclk_phase_counter <= ifclk_phase_counter + 1;

        if (ifclk_sequence[3]) roundtrip <= ifclk_phase_counter;
    
        if (rst_lock_i) enable_lock <= 1'b0;
        else if (lock_i) enable_lock <= 1'b1;
        
        cin_history[24 +: 4] <= cin_align;
        cin_history[20 +: 4] <= cin_history[24 +: 4];
        cin_history[16 +: 4] <= cin_history[20 +: 4];
        cin_history[12 +: 4] <= cin_history[16 +: 4];
        cin_history[8 +: 4] <= cin_history[12 +: 4];
        cin_history[4 +: 4] <= cin_history[8 +: 4];
        cin_history[0 +: 4] <= cin_history[4 +: 4];
        
        if (rst_lock_i) locked <= 1'b0;
        else if (enable_lock && current_cin == TRAIN_SEQUENCE) locked <= 1'b1;
        
        enable_capture <= ifclk_sequence == 4'h6;
        
        if (!locked) ifclk_sequence <= 4'h0;
        else ifclk_sequence <= ifclk_sequence[2:0] + 1;
        
        if (do_cin_capture) begin
            cin_capture <= current_cin;
        end        
        
        if (locked) cin_biterr <= 1'b0;
        else cin_biterr <= (cin_history[3:0] != cin_delayed[3:0]);        
    end

    assign locked_o = locked;
    assign cin_parallel_valid_o = ifclk_sequence[3];
    assign cin_parallel_o = cin_capture;
    assign cin_roundtrip_o = roundtrip;
    
endmodule

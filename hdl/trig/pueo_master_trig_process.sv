`timescale 1ns / 1ps
`include "interfaces.vh"
// Right now this ASSUMES a 32.768 us SIGBUF!!
// If that gets expanded this needs to change!!
// We're going to factor off the URAM portion.
module pueo_master_trig_process #(parameter NSURF=28,
                                  parameter ADDRBITS = 12,
                                  parameter NBIT=16,
                                  parameter SYSCLKTYPE = "NONE",
                                  parameter [2:0] PHASE_RESET = 4)(
        input sysclk_i,
        input sysclk_phase_i,
        input sysclk_x2_i,
        input sysclk_x2_ce_i,
        
        input                   wb_clk_i,        
        // wishbone side, needs an update since it can change dynamically
        input [27:0]            trigmask_i,
        // flag to update trigmask
        input                   trigmask_update_i,
        // parameters from wishbone captured at runrst
        input [15:0]            trig_offset_i,
        input [15:0]            trig_latency_i,        


        // these get organized as
        // tio3, tio2, tio1, tio0
        // where each tio is 7*NBITs bits
        input [NSURF*NBIT-1:0]  trigin_dat_i,
        // high when dat_i changes
        input                   trigin_dat_valid_i,
        // occurs in sysclk
        // This is muxed externally and is just a fifo
        // that's read out at a fixed point.
        input [11:0]            turf_trig_i,
        input [7:0]             turf_metadata_i,
        input                   turf_valid_i,

        input runrst_i,
        input runstop_i,
        output running_o,
        output [11:0] address_o,
        
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( trigout_ , 16 ),
        // as it is we will currently generate 5 64-bit words I think
        // 1 for each TURFIO's metadata and 1 for event no/trigger number.        
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( turf_hdr_ , 64 )
    );
    
    wire update_trig_mask_sysclk;
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [27:0] trig_mask_sysclk = {28{1'b1}};
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [15:0] trig_offset_sysclk = {16{1'b0}};
    // start off max, reset to max, that way any sane value
    // will work.
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [15:0] trig_latency_sysclk = {16{1'b1}};
    reg [15:0] trig_latency_counter = {16{1'b0}};


    // This was wrong before.
    // We CANNOT cascade the URAMs. At all. It won't work.
    // On the write side we cannot because we need a different
    // address every clock. On the read side we need a different
    // address every OTHER clock, but we need to read/write
    // from all 4 at the same time.    
    wire [ADDRBITS-1:0] address[3:0][7:0];
    wire [7:0] metadata[3:0][7:0];
    // NOTE: this ALSO acts the byte-write enable just as it is.
    wire [7:0] trigger[3:0];
    // We need to mux the addresses, since we only have one port.
    wire [ADDRBITS-1:0] address_muxed[3:0];
    // We do NOT need to mux the metadata!
    // We need to mux the trigger because it's used as the top BWE bit.
    wire [3:0] trigger_muxed;
    wire [7:0] trigger_bwe[3:0];
        
    wire [7:0]  trig_mask_vec[3:0];
    wire [8*NBIT-1:0] trigin_vec[3:0];
    
    reg trig_running = 0;
    reg trig_readout_running = 0;
    
    // this needs to START at runrst, wait until the latency counter expires,
    // then count every clock.
    reg [11:0] readout_address = {12{1'b0}};
    // this is the current address. just duplicate stuff, it ain't bad.
    reg [11:0] current_address = {12{1'b0}};
    
    wire [63:0] metadata_out[3:0];
    wire [3:0]  trigger_out;    

    // x2 phase buffering
    reg [1:0] sysclk_x2_phase_buf = {2{1'b0}};
    // sequence controls the muxing    
    reg [2:0] sysclk_x2_sequence = {3{1'b0}};

    generate
        genvar i,j;
        for (i=0;i<4;i=i+1) begin : TIO
            assign trig_mask_vec[i] = { 1'b0, trig_mask_sysclk[7*i +: 7] };            
            assign trigin_vec[i] = { {NBIT{1'b0}}, trigin_dat_i[7*NBIT*i +: 7*NBIT] };
            for (j=0;j<8;j=j+1) begin : SURF 
                wire [NBIT-1:0] trigin = trigin_vec[i][NBIT*j +: NBIT];
                if (j < 7) begin : RL
                    reg [ADDRBITS-1:0] s_addr = {ADDRBITS{1'b0}};
                    reg [7:0] s_metadata = {8{1'b0}};
                    reg       s_valid = 0;
                    // shift register on s_valid to form s_trigger
                    reg [2:0] s_valid_shreg = {3{1'b0}};
                    wire      s_trigger = s_valid_shreg[2];
                    // The complication here is that the trigger actually consists
                    // of 2 16-bit words. So after we get a trigger, we need to wait
                    // for the metadata to arrive to present it.
                    //
                    // We want to be presenting data/trigger still aligned with the
                    // trigger valid period. It goes high in sequence 3 and 7.
                    // This is sysclk!
                    // clk  sequence    data    s_valid   s_valid_shreg s_addr
                    // 0    0           X       0           000         0
                    // 1    1           X       0           000         0
                    // 2    2           X       0           000         0
                    // 3    3           ADDR    0           000         0
                    // 4    4           ADDR    1           000         ADDR
                    // 5    5           ADDR    1           001         ADDR
                    // 6    6           ADDR    1           011         ADDR
                    // 7    7           DATA    1           111         ADDR    <--- same as incoming data
                    // 8    0           DATA    0           111         ADDR
                    // 9    1           DATA    0           110         ADDR
                    // 10   2           DATA    0           100         ADDR
                    // 
                    // So what we can see here is that we can capture valid, then delay
                    // it by 3 cycles to form our trigger output. In sysclk_x2, that trigger
                    // will only be sampled at 1 point during the sequence so that's fine.
                    // The data output represents our metadata input, and we have to hold addr.
                    // Consider a SECOND trigger IMMEDIATELY coming in:
                    // 11   3           ADR2    0           000         ADDR
                    // 12   4           ADR2    1           000         ADR2
                    //
                    // We can therefore use s_trigger to clear s_valid because s_trigger
                    // will NOT be valid in sequence 3, the same point the input data is.
                    // We also capture ADDR if trigin[15] && !s_valid.
                    // and s_valid is 0 if s_trigger and 1 if trigin[15].
                    // Yipes, this is complicated.
                    always @(posedge sysclk_i) begin : TFORM
                        // clear s_valid when s_trigger asserts
                        if (s_trigger)
                            s_valid <= 0;
                        else if (!trig_mask_vec[i][j] && trig_running && trigin[15])
                            // otherwise if not masked and running and trigger valid, go for it!
                            s_valid <= 1;

                        // delay s_valid by 3 clocks to form a timed-up trigger
                        s_valid_shreg <= { s_valid_shreg[1:0], s_valid };
                        
                        // s_addr is captured with a valid trigger when not already valid.
                        if (trigin_dat_valid_i && !trig_mask_vec[i][j] && 
                            trigin[15] && trig_running && !s_valid) begin
                            // We ALWAYS skip the bottom 2 bits, they're pointless.
                            // Who knows, maybe embed something there???
                            s_addr <= trigin[2 +: ADDRBITS];
                        end
                    end
                    assign trigger[i][j] = s_trigger;
                    assign metadata[i][j] = trigin[7:0];
                    assign address[i][j] = s_addr;
                end else if (i == 3) begin : TF
                    // note the latency is different here but who gives an eff.
                    // the TURF should match to the trig valid (3 clocks post sync
                    // and hold for 4 clocks).
                    assign address[i][j] = turf_trig_i;
                    assign metadata[i][j] = turf_metadata_i;
                    assign trigger[i][j] = turf_valid_i;
                end else begin : FK
                    assign address[i][j] = {ADDRBITS{1'b0}};
                    assign metadata[i][j] = {8{1'b0}};
                    assign trigger[i][j] = 1'b0;
                end
            end
            assign address_muxed[i] = address[i][sysclk_x2_sequence];
            assign trigger_muxed[i] = trigger[i][sysclk_x2_sequence];
            assign trigger_bwe[i] = trigger[i];
            // At this point we now have a clean set of
            // address_muxed
            // metadata
            // trigger_bwe
            // - these are all combinatorially muxed at this point.    
            master_trig_uram u_uram(.clk_i(sysclk_x2_i),
                                    .wr_en_i(   trig_running        ),
                                    .waddr_i(   address_muxed[i]    ),
                                    .metadata_i( { metadata[i][7],
                                                   metadata[i][6],
                                                   metadata[i][5],
                                                   metadata[i][4],
                                                   metadata[i][3],
                                                   metadata[i][2],
                                                   metadata[i][1],
                                                   metadata[i][0] } ),
                                    .we_i( trigger_bwe[i] ),
                                    .trigger_i( trigger_muxed[i] ),
                                    
                                    .raddr_i( readout_address ),
                                    .rd_en_i( trig_readout_running ),
                                    .rd_phase_i( sysclk_x2_sequence[0] ),
                                    .metadata_o( metadata_out[i] ),
                                    .trigger_o( trigger_out[i] ) );                                                                                       
        end
    endgenerate   


    // all this needs to be timed up so that trig_running goes 1
    // in clock 0. therefore trig_latency counter resets itself to 1.
    always @(posedge sysclk_i) begin
//        if (runrst_i) trig_running <= 1;
//        else if (runstop_i) trig_running <= 0;

        if (!trig_running)
            current_address <= 12'd1;
        else
            current_address <= current_address + 1;            
        
//        if (runrst_i) trig_latency_sysclk <= trig_latency_i;
//        else if (runstop_i) trig_latency_sysclk <= {16{1'b1}};
        
//        if (!trig_running) 
//            trig_latency_counter <= 16'd1;
//        else if (!trig_readout_running)
//            trig_latency_counter <= trig_latency_counter + 1;
            
        if (trigmask_update_i)
            trig_mask_sysclk <= trigmask_i;            
    end

    // sysclk x2 needs to run the sequencer.
    // the way this needs to work is that when the data for ch0 becomes valid
    // we need to be in sequence 0. This is why we have the phase offset
    // parameter above.
    // First we need to consider the phase reset and when data FIRST becomes valid.
    // Remember that although the data is split across 2 data valid points, it's timed
    // so that they arrive the same.
    // 
    // sysclk_x2_phase_buf == 10 triggers clk2 sequence 2.
    // Valid triggers in clk sequence 3
    // 
    // clk  clk2    sysclk_phase_i  sysclk_x2_phase_buf     clk sequence    clk2 sequence   valid   sysclk_x2_sequence
    // 1    1       `DLYFF 1        00                      0               0               0           2
    // 1    0       1               00                      0               0               0           2
    // 0    1       1               `DLYFF 01               0               1               0           3
    // 0    0       1               01                      0               1               0           3
    // 1    1       `DLYFF 0        `DLYFF 11               1               2               0           4
    // 1    0       0               11                      1               2               0           4
    // 0    1       0               `DLYFF 10               1               3               0           5
    // 0    0       0               10                      1               3               0           5
    // 1    1       0               `DLYFF 00               2               4               0           6
    // 1    0       0               00                      2               4               0           6
    // 0    1       0               00                      2               5               0           7
    // 0    0       0               00                      2               5               0           7
    // 1    1       0               00                      3               6               `DLYFF 1    0
    // 1    0       0               00                      3               6               1           0
    //
    // because we want sysclk_x2_sequence to be 0 when the first data goes high, we
    // need to reset to 4 if the phase buf is 01.
    always @(posedge sysclk_x2_i) begin
        sysclk_x2_phase_buf <= { sysclk_x2_phase_buf[0], sysclk_phase_i };
        if (sysclk_x2_phase_buf == 2'b01)
            sysclk_x2_sequence <= PHASE_RESET;
        else
            sysclk_x2_sequence <= sysclk_x2_sequence + 1;
            
        if (sysclk_x2_ce_i) begin
            if (runrst_i) trig_running <= 1;
            else if (runstop_i) trig_running <= 0;
        end
        
        if (sysclk_x2_ce_i) begin
            if (runrst_i) trig_latency_sysclk <= trig_latency_i;
            else if (runstop_i) trig_latency_sysclk <= {16{1'b1}};
        end
        
        if (sysclk_x2_ce_i) begin
            if (!trig_running)
                trig_latency_counter <= {16{1'b0}};
            else if (trig_latency_counter < trig_latency_sysclk)
                trig_latency_counter <= trig_latency_counter + 1;
        end
        
        if (sysclk_x2_ce_i) begin
            if (runstop_i) 
                trig_readout_running <= 0;
            else if (trig_latency_counter == trig_latency_sysclk)
                trig_readout_running <= 1;
        end
        if (sysclk_x2_ce_i) begin
            if (!trig_readout_running)
                readout_address <= {12{1'b0}};
            else
                readout_address <= readout_address + 1;
        end                                
    end
    // ok: in the end, if we have |trigger_out we write readout_address into
    // an outbound FIFO for transmission and we capture the metadata into FIFOs
    // along with the address + event number. The address will EVENTUALLY be
    // the time instead so it needs to be 32 bits. Event number will be 32 bits too.
    // this means we need 5x 64-bit FIFOs. On the other side
    // we'll have to demux all of them when outputting a TURF header. Joy.
    //
    // I don't think the time will be that bad - we'll just cascade a DSP
    // and adjust the readout latency I think. The whole thing is going to
    // be very crufty.
    // just... skip going full we're not ever going to fill up.
    trigger_fifo u_fifo( .wr_clk(sysclk_x2_i),
                         .din( { 2'b10, readout_address, {2{1'b0}} } ),
                         .wr_en( |trigger_out[3:0] && sysclk_x2_ce_i ),
                         .rd_clk(sysclk_i),
                         .srst(!trig_running),
                         .valid(trigout_tvalid),
                         .rd_en(trigout_tvalid && trigout_tready),
                         .dout(trigout_tdata));
    // just... shut up headers for now for immediate testing.
    // this whole thing needs to be simulated.
    assign turf_hdr_tvalid = 1'b0;
    
    assign address_o = current_address;
    assign running_o = trig_running;        
endmodule

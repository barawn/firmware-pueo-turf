`timescale 1ns / 1ps
// more headers, more fun.
// now we're adding in real stuff, so we have
// to operate in trig clock domain too.
module turf_header_generator_v2 #(parameter MEMCLKTYPE="NONE",
                                  parameter SYSCLKTYPE="NONE",
                                  parameter META_WINDOW=16,
                                  parameter NUM_META=32,
                                  parameter META_BITS=8)(
        input memclk,
        input memresetn,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_thdr_, 64 ),
        
        input sysclk_i,
        // event counter resets
        input runrst_i,
        // run stop acts as an event reset
        input runstop_i,
        // tio mask
        input [3:0] tio_mask_i,
        // run configuration
        input [11:0] runcfg_i,
        
        output event_o,
        
        input trig_i,
        input [NUM_META*META_BITS-1:0] metadata_i,
        input [31:0] cur_sec_i,
        input [31:0] cur_time_i,
        input [31:0] last_pps_i,
        input [31:0] llast_pps_i
    );
    
    localparam DATA_WIDTH=64;
    localparam [3:0] WINDOW_DELAY = META_WINDOW-1;
    localparam [3:0] SHIFT_DELAY = 4'd3;
    // There are currently 8 dummy qwords: we absorb them into the meta shift
    // because the meta holding register will just shift out to zero anyway.
    // If we fill in additional words here we'll change this and split it
    // off into another state and another SRL.
    localparam [3:0] DUMMY_QWORDS = 4'd8;
    localparam [3:0] FULL_SHIFT_DELAY = DUMMY_QWORDS + SHIFT_DELAY;

    // Header words come first, but we spec it in 16-bit words so
    // currently thats 128 bytes = 64 shorts = 63 remaining 
    localparam [15:0] CONST_HEADER_WORDS = 16'd63;
    localparam [15:0] CONST_EVENT_FORMAT = "E1";
    // SURF header words come LAST, and again it's 16 bit words.
    // Right now that's 64 shorts. The top 16 bits of that value
    // also include the TURFIO mask.
    localparam [15:0] CONST_SURF_WORDS = 16'd64;

    reg [NUM_META*META_BITS-1:0] meta_holding = {NUM_META*META_BITS{1'b0}};
    wire [(NUM_META*META_BITS+DATA_WIDTH)-1:0] 
        meta_expanded = { {DATA_WIDTH{1'b0}}, meta_holding };
    // have to pipeline the comparison, it's too big.
    reg [NUM_META-1:0] meta_valid = {NUM_META{1'b0}};
    wire meta_window_done;
    reg window_complete = 0;  
    wire meta_start_shift;
    wire meta_shifting_done;
    reg meta_in_window = 0;
    reg meta_shifting = 0;
    
    reg [63:0] data_in_holding = {64{1'b0}};
    reg [31:0] event_counter = {32{1'b0}};
    reg [31:0] cur_sec_hold = {32{1'b0}};
    reg [31:0] cur_time_hold = {32{1'b0}};
    reg [31:0] last_pps_hold = {32{1'b0}};
    reg [31:0] llast_pps_hold = {32{1'b0}};

    reg running = 0;
    (* CUSTOM_CC_DST = SYSCLKTYPE *)
    reg [15:0] run_config_word = {16{1'b0}};
            
    // headers go in as 64 bit words = 8 bytes
    // we have 16 of 'em to write
    // qword 0:  { event_counter, constant }
    // qword 1:  { cur_time_hold, cur_sec_hold }
    // qword 2:  { llast_pps_hold, last_pps_hold }
    // qword 3:  { metadata (turfio 0) }
    // qword 4:  { metadata (turfio 1) }
    // qword 5:  { metadata (turfio 2) }
    // qword 6:  { metadata (turfio 3) }
    // qword 7:  { reserved (still metadata but zero) }
    // qword 8:  { reserved (still metadata but zero) }
    // qword 9:  { reserved (still metadata but zero) }
    // qword 10: { reserved (still metadata but zero) }
    // qword 11: { reserved (still metadata but zero) }
    // qword 12: { reserved (still metadata but zero) }
    // qword 13: { reserved (still metadata but zero) }
    // qword 14: { reserved (still metadata but zero) }
    // qword 15: { constant 2, reserved (still metadata) }
    
    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] EVENT_COUNT = 1;
    localparam [FSM_BITS-1:0] CUR_TIME = 2;
    localparam [FSM_BITS-1:0] PPS_HOLD = 3;
    localparam [FSM_BITS-1:0] METADATA_WAIT = 4;
    localparam [FSM_BITS-1:0] METADATA_WRITE = 5;
    localparam [FSM_BITS-1:0] TRAILER = 6;
    reg [FSM_BITS-1:0] state = IDLE;
    
    reg write_header = 0;
    
    reg event_flag = 0;
    
    // we then pop this into a 64-bit FIFO, even the smallest
    // will be awesome.
    
    SRL16E u_window_delay(.D(trig_i),
                          .CE(1'b1),
                          .CLK(sysclk_i),
                          .A0(WINDOW_DELAY[0]),
                          .A1(WINDOW_DELAY[1]),
                          .A2(WINDOW_DELAY[2]),
                          .A3(WINDOW_DELAY[3]),
                          .Q(meta_window_done));
    SRL16E u_shift_delay(.D(meta_start_shift),
                         .CE(1'b1),
                         .CLK(sysclk_i),
                         .A0(SHIFT_DELAY[0]),
                         .A1(SHIFT_DELAY[1]),
                         .A2(SHIFT_DELAY[2]),
                         .A3(SHIFT_DELAY[3]),
                         .Q(meta_shifting_done));

    assign meta_start_shift = (state == METADATA_WAIT && window_complete);
        
    // accumulate the metadata
    integer l,n,m;
    always @(posedge sysclk_i) begin
        if (runrst_i) run_config_word <= { tio_mask_i, runcfg_i };
        
        if (trig_i) window_complete <= 0;
        else if (meta_window_done) window_complete <= 1;
        
        if (trig_i) meta_in_window <= 1;
        else if (meta_window_done) meta_in_window <= 0;

        if (meta_start_shift) meta_shifting <= 1;
        else if (meta_shifting_done) meta_shifting <= 0;

        if (meta_in_window || trig_i) begin
            for (m=0;m<NUM_META;m=m+1) begin
                if (!meta_valid[m])
                    meta_holding[m*META_BITS +: META_BITS] <= metadata_i[m*META_BITS +: META_BITS];
            end
        end else if (meta_shifting) begin
            for (l=0;l<(NUM_META*META_BITS/DATA_WIDTH);l=l+1) begin
                meta_holding[DATA_WIDTH*l +: DATA_WIDTH] <= 
                    meta_expanded[DATA_WIDTH*(l+1) +: DATA_WIDTH];
            end
        end

        for (n=0;n<NUM_META;n=n+1) begin : ML
            if (meta_in_window || trig_i) begin
                if (metadata_i[n*META_BITS +: META_BITS] != {8{1'b0}})
                    meta_valid[n] <= 1;
            end else begin
                meta_valid[n] <= 0;
            end                
        end
        
        if (runrst_i) running <= 1;
        else if (runstop_i) running <= 0;
        
        if (runrst_i) event_counter <= {32{1'b0}};
        else if (state == EVENT_COUNT) event_counter <= event_counter + 1;
        
        // our event time always has a rando-offset compared to when it actually happened.
        // so it doesn't matter if I jump forward to reduce loading on the trigger.
        if (state == EVENT_COUNT) begin
            cur_sec_hold <= cur_sec_i;
            cur_time_hold <= cur_time_i;
            last_pps_hold <= last_pps_i;
            llast_pps_hold <= llast_pps_i;
        end
        
        if (!running) state <= IDLE;
        else case (state)
            IDLE: if (trig_i) state <= EVENT_COUNT;
            EVENT_COUNT: state <= CUR_TIME;
            CUR_TIME: state <= PPS_HOLD;
            PPS_HOLD: state <= METADATA_WAIT;
            METADATA_WAIT: if (window_complete) state <= METADATA_WRITE;
            METADATA_WRITE: if (meta_shifting_done) state <= TRAILER;
            TRAILER: state <= IDLE;
        endcase
        
        event_flag <= (state == EVENT_COUNT);
        
        // this SHOULD match the old setup.
        // This SHOULD show up as little endian as well because the data gets transmitted that way I believe.
        if (state == EVENT_COUNT) data_in_holding <= { event_counter, CONST_EVENT_FORMAT, CONST_HEADER_WORDS };
        else if (state == CUR_TIME) data_in_holding <= { cur_time_hold, cur_sec_hold };
        else if (state == PPS_HOLD) data_in_holding <= { llast_pps_hold, last_pps_hold };
        else if (state == METADATA_WRITE) data_in_holding <= meta_holding[0 +: DATA_WIDTH];
        else if (state == TRAILER) data_in_holding <= { CONST_SURF_WORDS, run_config_word, meta_holding[0 +: 32] };
        
        write_header <= (state != IDLE && state != METADATA_WAIT);
    end
    
    turf_evhdr_fifo u_fifo(.wr_clk(sysclk_i),
                           .din( data_in_holding ),
                           .wr_en(write_header),
                           .srst(!running),
                           .rd_clk(memclk),
                           .dout(m_thdr_tdata),
                           .valid(m_thdr_tvalid),
                           .rd_en(m_thdr_tvalid && m_thdr_tready));    

    assign event_o = event_flag;
    
endmodule

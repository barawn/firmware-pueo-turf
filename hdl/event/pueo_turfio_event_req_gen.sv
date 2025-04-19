`timescale 1ns / 1ps
`include "interfaces.vh"
`include "mem_axi.vh"
// The req gen takes the payload stream from the
// TURFIO accumulator and generates DataMover requests for it.
// In order to generate a DataMover request set, we need to have
// an address available, which comes via the doneaddr links.
// This means we ALSO need to have the base address for this
// TURFIO set.
//
// THIS is where we expand from 12->16 bits, because we've
// got the free bandwidth. Originally we weren't going to
// but I think it'll actually speed things up at the SFC and
// it also matches the DDR page size better.
//
// We can save some buffering here though:
// We take in 64 bits, store, store again to build up to
// 192 bits = 16 samples = 256 expanded bits.
// We then feed that into an asymmetric FIFO expanding up
// to 512 which feeds the DataMover. So we actually
// only need 384 bits, or 256 + 128. This would cut down
// our buffering to 384 bits x 512 entries = 196,608 bits
// = 24,576 bytes. A chunk is only 21,504 bytes, so
// we can still store a full chunk here.
//
// It takes up 5.5 block RAMs for buffering (so 22 total).
// We add a programmable full output which tells when the
// chunk's complete so we can add backpressure in the
// turfio event accumulator.
//
// This means that our fixed BTT length is always
// 2048 * 2 bytes/sample = 4096 bytes.
//
// We also have a separate datamover for the headers,
// we'll have to see if we can shrink that guy maybe?
// We have 4 bytes of headers/SURF + maybe TURFIO +
// maybe some TURF. Easiest to just reserve 512 bytes
// at the moment. This leaves 256 bytes = 64 32-bit words
// from the TURF at the moment, but it would be easy
// to expand larger.
//
// WE MIGHT MAKE THIS PARAMETERIZABLE. I'M NOT SURE
// IT ACTUALLY MATTERS B/C THE PAGE SIZE ON THESE
// THINGS IS 8 KB AND SO YOU DON'T JUMP *THAT* OFTEN
// 
// TOTAL EVENT SIZE IS NOW
// 512 + 28*8*2048 = 459,264 = 448.5 kB
// vs 336.5 kB
// 
// Currently:
// Headers: 0x00_3E00 - 0x00_3FFF
// TIO0/S0  0x00_4000 - 0x00_7FFF
//      S1  0x00_8000 - 0x00_BFFF
//      S2  0x00_C000 - 0x00_FFFF
//      S3  0x01_0000 - 0x01_3FFF
//      S4  0x01_4000 - 0x01_7FFF
//      S5  0x01_8000 - 0x01_BFFF
//      S6  0x01_C000 - 0x01_FFFF
// TIO1/S0  0x02_0000 - 0x02_3FFF
//      S1  0x02_4000 - 0x02_7FFF
//      S2  0x02_8000 - 0x02_BFFF
//      S3  0x02_C000 - 0x02_FFFF
//      S4  0x03_0000 - 0x03_3FFF
//      S5  0x03_4000 - 0x03_7FFF
//      S6  0x03_8000 - 0x03_BFFF
// TIO2/S0  0x03_C000 - 0x03_FFFF
//      S1  0x04_0000 - 0x04_3FFF
//      S2  0x04_4000 - 0x04_7FFF
//      S3  0x04_8000 - 0x04_BFFF
//      S4  0x04_C000 - 0x04_FFFF
//      S5  0x05_0000 - 0x05_3FFF
//      S6  0x05_4000 - 0x05_7FFF
// TIO3/S0  0x05_8000 - 0x05_BFFF
//      S1  0x05_C000 - 0x05_FFFF
//      S2  0x06_0000 - 0x06_3FFF
//      S3  0x06_4000 - 0x06_7FFF
//      S4  0x06_8000 - 0x06_BFFF
//      S5  0x06_C000 - 0x06_FFFF
//      S6  0x07_0000 - 0x07_3FFF
// Obviously done this way the base
// address only needs to be 5 bits
// since it's either
// 0_4000
// 2_0000
// 3_C000
// 5_8000
module pueo_turfio_event_req_gen(
        input memclk,
        input memresetn,

        // This just isn't an AXI4-Stream interface anymore
        // so stop pretending it is. Once payload_valid_i goes high
        // it HAS to be asserted straight. It can only stop on
        // multiples of 3.
        input [63:0] payload_i,
        input        payload_valid_i,
        input [4:0]  payload_ident_i,
        input        payload_last_i,
        output       payload_has_space_o,
        
        `M_AXIM_PORT( m_axi_ , 1 ),
        // our base address is 19 bits, and our full
        // memory space is 4 GB which fills the full 32 bit space.
        // So our done width is 13 bits. Just expand to 16 bits.
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_done_ , 16 ),
        // The completion port needs to store the 13 bit address.
        // We also store the errors although we reduce them:
        // 4 sticky bits for each of the errors
        // 1 bit per SURF chunk (7 SURFs x 4 chunks per event = 28 bits)
        // so 32 total status bits per. So just make this 64 bits.
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_cmpl_ , 64 ),
        
        // bit 0 : command FIFO ran out of space  (??? axi traffic not distributed OK?)
        // bit 1 : doneaddr FIFO ran out of space (either AXI traffic issue or CPU
        //                                         not reading out events fast enough)
        // bit 2 : completion FIFO ran out of space (CPU not reading out events fast enough)
        // bit 3 : doneaddr FIFO underflow (?!?! - no effing clue, logic issue)
        output [3:0] cmd_err_o
    );
    // Our base addresses are either spaced in 4k*4*7 or 3k*4*7 increments.
    // EITHER WAY it's 4k (0x1000) spaced - either 28 (0x1C) or 21 (0x15), and
    // we start at 0x4000 to make sure we page-align.
    // so either 4, 32, 60, 88
    //        or 4, 25, 46, 67
    // need 7 bits
    parameter  [6:0] BASE_ADDRESS_4KB   = 7'd4;
    // expand to 9 bits
    localparam [8:0] BASE_ADDRESS_KB = { BASE_ADDRESS_4KB, 2'b00 };
    // Size of chunk in 1024-byte increments.
    localparam [2:0] CHUNK_SIZE_KB = 3'd4;
    localparam [8:0] SURF_SIZE_KB = 4*CHUNK_SIZE_KB;
    // 10 bits to get to KB
    // 3 bits for chunk size
    // 10 bits BTT padding
    localparam [22:0] CHUNK_SIZE_BTT = { {10{1'b0}}, CHUNK_SIZE_KB, 10'h000 };
    // when we START OFF, our addresses can only be fixed values:
    // just {BASE_ADDRESS_4KB,00},
    //      {BASE_ADDRESS_4KB,00}+CHUNK_SIZE_KB
    //      {BASE_ADDRESS_4KB,00}+2*CHUNK_SIZE_KB
    //      {BASE_ADDRESS_4KB,00}+3*CHUNK_SIZE_KB
    // The MAX RANGE here no matter what is
    // 352 + 12 = 364 so we need 9 bits.
    // It shouldn't be too bad though, it should just be a weird adder.
    // Define the constants here.
    localparam [8:0] START_CHUNK_0 = BASE_ADDRESS_KB;
    localparam [8:0] START_CHUNK_1 = BASE_ADDRESS_KB + CHUNK_SIZE_KB;
    localparam [8:0] START_CHUNK_2 = BASE_ADDRESS_KB + 2*CHUNK_SIZE_KB;
    localparam [8:0] START_CHUNK_3 = BASE_ADDRESS_KB + 3*CHUNK_SIZE_KB;
    
    wire [8:0]  chunk_lookup[3:0];
    assign chunk_lookup[0] = START_CHUNK_0;
    assign chunk_lookup[1] = START_CHUNK_1;
    assign chunk_lookup[2] = START_CHUNK_2;
    assign chunk_lookup[3] = START_CHUNK_3;
    // So in the end our adder is
    // wire [8:0] addr_addend_A = (state == LOAD_BASE_ADDRESS) ? chunk_lookup[payload_ident_i[1:0]] :
    //                                                           this_addr;
    // wire [8:0] addr_addend_B = (state == INCREMENT_ADDRESS) ? SURF_SIZE_KB :
    //                                                           9'h00;
    // should work.
    
    // datamover commands are 72 bits long for us.
    // datamover command packing SUCKS because they DO NOT explain it well
    // it MUST be a multiple of 8 bits (by AXI4-Stream spec)
    // and the packing ALWAYS has 4 bits tag + 4 bits reserved (1 extra byte)
    // Without USER/CACHE it's therefore
    // 32 bits (lower command)
    // + ((ceil(address bits/8)*8) for address
    // + 8 bits (reserved/tag)
    // Literally the only thing that changes for us EVER is the address plus
    // whether it's the final one or not.

    // IF WE DO THIS WITH EXPANDED DATA:
    // the address always increments by 4096 bytes (2 bytes x 2 channels/chunk x 1024)
    // = 0x1000
    // IF WE DO THIS WITH NONEXPANDED DATA:
    // the address always increments by 3072 bytes (1.5 bytes x 2 channels/chunk x 1024)
    // = 0x0C00
    // the SURFs always increment by 4x chunk, so
    // expanded   = 0x4000
    // unexpanded = 0x3000
    // SO NO MATTER WHAT - the bottom 10 bits are ALWAYS zero. So we don't need them.
    // (this is b/c with 2 channels, we are either 3x1024 bytes or 4x1024 bytes)
    // Therefore we need a 22-bit FIFO + a single extra bit for the final command.
    // bits [21:0] are address[31:10]
    // bit 22 is dm_final_command

    wire [22:0] cmd_fifo_out;
    wire [22:0] cmd_fifo_in;
    wire        cmd_fifo_valid;
    wire        cmd_fifo_read;
    wire        cmd_fifo_write;
    wire        cmd_fifo_overflow;
    
    // Build up the command from the cmd_fifo_out
    wire [31:0] dm_full_address = { cmd_fifo_out[21:0], {10{1'b0}} };
    wire [3:0]  dm_tag = { {3{1'b0}}, cmd_fifo_out[22] };
    wire [31:0] dm_lower_command = 
        {   1'b0,       // DRR = 0 (no realignment)
            1'b1,       // EOF = 1 (tlast is expected)
            6'b000000,  // DSA = 000000 (unused)
            1'b1,       // TYPE = 1 (incrementing address)
            CHUNK_SIZE_BTT  // BTT = chunk size = 4096 bytes
            };
    wire [7:0] dm_upper_byte = { {4{1'b0}}, dm_tag };
    wire [71:0] dm_full_command = { dm_upper_byte, dm_full_address, dm_lower_command };

    //////////////////////////////////////////////////////////
    //                  DATA MOVER STREAMS                  //
    //////////////////////////////////////////////////////////
    `DEFINE_AXI4S_MIN_IF( dm_cmd_ , 72 );    
    assign dm_cmd_tdata = dm_full_command;
    assign dm_cmd_tvalid = cmd_fifo_valid;
    assign cmd_fifo_read = dm_cmd_tvalid && dm_cmd_tready;

    `DEFINE_AXI4S_IF( dm_data_ , 512 );
    // 512 bits = 64 bytes = 8 qwords
    // No matter what we send multiples of 8 qwords, either
    // 192 (unexpanded) or 256 (expanded). So just set tkeep
    // to all 1s.
    assign dm_data_tkeep = {64{1'b1}};
    `DEFINE_AXI4S_MIN_IF( dm_stat_ , 8);

    //////////////////////////////////////////////////////////


    // indicates that the FIFO (event_expand_and_store) has space.
    // this plus the availability of an address determines payload_has_space_o.
    wire fifo_has_space;
    
    // we effectively have two DECOUPLED state machines
    // one of which accepts chunks in and generates commands,
    // and the second waits for statuses and issues completions.
    //
    // at IDLE it waits for payload_valid_i, then jumps to LOAD_BASE_ADDRESS.
    // LOAD_BASE_ADDRESS will happen whenever we jump to a new chunk
    // (meaning we see tlast with payload_ident_i[5:2] == 6)
    // LOAD_BASE_ADDRESS captures MY_BASE + (payload_ident_i[1:0])*CHUNK_ADDR_INCR
    // and then goes to WAIT_FOR_TLAST_TO_ISSUE and shoves it in when tlast is seen.
    // If payload_ident_i[5:2] != 6 it then jumps to INCREMENT_ADDRESS
    // where it adds SURF_ADDR_INCR. Otherwise it jumps to LOAD_BASE_ADDRESS
    // where it starts again.
    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] RESET = 0;
    localparam [FSM_BITS-1:0] RESET_WAIT = 1;
    localparam [FSM_BITS-1:0] IDLE = 2;
    localparam [FSM_BITS-1:0] LOAD_BASE_ADDRESS = 3;
    localparam [FSM_BITS-1:0] WAIT_FOR_TLAST_TO_ISSUE = 4;
    localparam [FSM_BITS-1:0] INCREMENT_ADDRESS = 5;
    localparam [FSM_BITS-1:0] WAIT_NEXT_CHUNK = 6;
    reg [FSM_BITS-1:0] state = IDLE;
    
    reg [3:0] reset_counter = {4{1'b0}};
    
    wire dm_cmd_reset = (reset_counter != {4{1'b0}});
    
    // error sticky
    reg [3:0] cmd_err_full = 4'h0;
 
    // address storage
    reg [8:0] this_addr = {9{1'b0}};
      
    // writes to command fifo
    wire   cmd_last_command = (payload_ident_i[2:0] == 6 && payload_ident_i[4:3] == 3);
    assign cmd_fifo_in = { cmd_last_command,
                           s_done_tdata[12:0],    // 13 bits for event address
                           this_addr };     // 9 bits for this address
                                            // 10 bits zero (aligned on 1kb boundaries)
    assign cmd_fifo_write = (state == WAIT_FOR_TLAST_TO_ISSUE) && payload_last_i && payload_valid_i;                                            

    // the address calculation isn't actually hard because we only have 4 chunks
    // so map it out here.
    // except this is TOTALLY WRONG because what we're actually looking for is payload_ident_i[4:3]
    wire [8:0] addr_addend_A = (state == LOAD_BASE_ADDRESS) ? chunk_lookup[payload_ident_i[4:3]] :
                                                              this_addr;
    wire [8:0] addr_addend_B = (state == INCREMENT_ADDRESS) ? SURF_SIZE_KB :
                                                              9'h00;      

    // TECHNICALLY this dumbass thing should be able to do everything from a single adder
    // it's only taking in:
    // state type (1 bit)
    // chunk type (2 bits)
    // current address (1 bit)
    // which is only 4 bits: it can derive all the other logic from that.
    // LET'S SEE IF IT'S DUMB OR NOT


    // OK now this is the OUTPUT side of the datamover. 8 bits only, non-indeterm. BTT mode
    // both tkeep/tlast are ignored, they're pointless.    
    // we always read out the status.
    assign dm_stat_tready = 1'b1;
    
    // First we need sticky registers for the status bits.
    reg [3:0] dm_status_err = {4{1'b0}};
    // redefine the status outputs as pure errors
    wire [3:0] dm_cur_err = { !dm_stat_tdata[7], dm_stat_tdata[6:4] };
    // and extract the last.
    wire dm_last_status = dm_stat_tdata[0];
    
    // and sticky registers for the 28 individual transfers. These are handled as
    // a shift register and reset at the end. So we only need 27, the 28th is in
    // logic.
    // let's combine the status bits.
    wire dm_err_any = |dm_cur_err;
    reg [26:0] dm_err_shreg = {27{1'b0}};
    
    // 4 bits + 28 indivdual errors.
    wire [31:0] dm_err_data = { dm_err_any, dm_err_shreg, dm_status_err | dm_cur_err };
    // And now the doneaddr FIFO...
    wire [12:0] doneaddr_fifo_in = s_done_tdata;
    wire        doneaddr_fifo_write = (cmd_last_command && cmd_fifo_write);
    wire        doneaddr_fifo_overflow;
    wire [12:0] doneaddr_fifo_out;
    wire        doneaddr_fifo_read = (dm_stat_tvalid && dm_last_status);
    wire        doneaddr_fifo_underflow;
    
    // and the outbound completion FIFO, which is 'really' a 32+13 = 45 bit FIFO
    // We ALWAYS just grab from the doneaddr_fifo : it should ALWAYS be valid.
    // I don't know how it couldn't be other than weirdo reset issues.
    wire [44:0] cmpl_fifo_in = { doneaddr_fifo_out, dm_err_data };
    wire        cmpl_fifo_write = { dm_stat_tvalid && dm_last_status };
    wire        cmpl_fifo_overflow;

    // The outbound side of the completion FIFO is a proper AXI4-Stream:
    // it will be combined with all of the other completions to generate a full event
    // ready notification and push to the readout datamover.    
    wire [44:0] cmpl_fifo_out;
    wire        cmpl_fifo_read = m_cmpl_tvalid && m_cmpl_tready;
    wire        cmpl_fifo_valid;
        

    // LOGIC
    always @(posedge memclk) begin
        if (state == RESET || state == RESET_WAIT)
            reset_counter <= reset_counter + 1;
        else
            reset_counter <= {4{1'b0}};
                        
        if (!memresetn) begin
            cmd_err_full <= 4'h0;
        end else begin
            if (cmd_fifo_overflow) cmd_err_full[0] <= 1;
            if (doneaddr_fifo_overflow) cmd_err_full[1] <= 1;
            if (cmpl_fifo_overflow) cmd_err_full[2] <= 1;
            if (doneaddr_fifo_underflow) cmd_err_full[3] <= 1;
        end

        if (state == INCREMENT_ADDRESS ||
            state == LOAD_BASE_ADDRESS) begin
                this_addr <= addr_addend_A + addr_addend_B;
        end
        if (!memresetn) state <= RESET;
        else begin
            case (state)
                RESET: state <= RESET_WAIT;
                RESET_WAIT: if (reset_counter == {4{1'b0}}) state <= IDLE;
                IDLE: if (payload_valid_i && s_done_tvalid) state <= LOAD_BASE_ADDRESS;
                LOAD_BASE_ADDRESS: state <= WAIT_FOR_TLAST_TO_ISSUE;
                WAIT_FOR_TLAST_TO_ISSUE: if (payload_valid_i && payload_last_i) begin
                    // the payload idents go
                    // chunk counter, surf counter
                    // so it's
                    // 0,1,2,3,4,5,6
                    // 8,9,10,11,12,13,14
                    // 16,17,18,19,20,21,22
                    // 24,25,26,27,28,29,30
                    if (payload_ident_i[2:0] == 6) begin
                        if (cmd_last_command) state <= IDLE;
                        // NOTE: this relies on the fact that chunks are delivered
                        // atomically. If it's last_i, we're GOING to transition
                        // to the next SURF, so if it's the last one, jump back to zero
                        // and the chunk indicator WILL increment.
                        else state <= WAIT_NEXT_CHUNK;
                    end else state <= INCREMENT_ADDRESS;
                end
                INCREMENT_ADDRESS: state <= WAIT_FOR_TLAST_TO_ISSUE;
                // generally after a chunk completes we'll be waiting a while for the next
                WAIT_NEXT_CHUNK: if (payload_valid_i) state <= LOAD_BASE_ADDRESS;
            endcase
        end
        
        // error tracking on the status outputs
        if (dm_stat_tvalid && dm_stat_tready) begin
            if (dm_last_status) dm_status_err <= {4{1'b0}};
            else dm_status_err |= dm_cur_err;
            
            dm_err_shreg <= { dm_err_any, dm_err_shreg[26:1] };
        end                
    end

    // command FIFO - written into when a SURF chunk's tlast is seen
    //                read from by the DataMover
    event_dm_cmd_fifo u_cmdfifo( .clk(memclk),
                                 .srst(!memresetn),
                                 .din(cmd_fifo_in),
                                 .wr_en(cmd_fifo_write),
                                 .overflow(cmd_fifo_overflow),
                                 .dout(cmd_fifo_out),
                                 .rd_en(cmd_fifo_read),
                                 .valid(cmd_fifo_valid));
    // completion address FIFO - written into when the last command is issued
    //                           read from by the completion FIFO
    event_done_addrfifo u_doneaddrfifo( .clk(memclk),
                                        .srst(!memresetn),
                                        .din(doneaddr_fifo_in),
                                        .wr_en(doneaddr_fifo_write),
                                        .overflow(doneaddr_fifo_overflow),
                                        .dout(doneaddr_fifo_out),
                                        .rd_en(doneaddr_fifo_read),
                                        .valid(doneaddr_fifo_valid));
                                        
    // completion FIFO - written into when the last command is completed
    //                 - read from by outside
    event_cmpl_fifo u_cmplfifo( .clk(memclk),
                                .srst(!memresetn),
                                .din(cmpl_fifo_in),
                                .wr_en(cmpl_fifo_write),
                                .overflow(cmpl_fifo_overflow),
                                .dout(cmpl_fifo_out),
                                .rd_en(cmpl_fifo_read),
                                .valid(cmpl_fifo_valid));

    // data FIFO
    event_expand_and_store #(.EXPAND_DATA("TRUE"))
        u_fifo( .clk(memclk),
                .rst(!memresetn),
                .payload_i(payload_i),
                .payload_valid_i(payload_valid_i),
                .payload_last_i(payload_last_i),
                .space_avail_o(fifo_has_space),
                `CONNECT_AXI4S_MIN_IF( m_axis_ , dm_data_ ),
                .m_axis_tlast( dm_data_tlast ));
                
    // and the DataMover
    turfio_datamover u_datamover( .m_axi_s2mm_aclk( memclk),
                                  .m_axi_s2mm_aresetn( !dm_cmd_reset),
                                  .m_axis_s2mm_cmdsts_awclk( memclk ),
                                  .m_axis_s2mm_cmdsts_aresetn( !dm_cmd_reset ),
                                  `CONNECT_AXI4S_IF( s_axis_s2mm_ , dm_data_ ),
                                  `CONNECT_AXI4S_MIN_IF( s_axis_s2mm_cmd_ , dm_cmd_ ),
                                  `CONNECT_AXI4S_MIN_IF( m_axis_s2mm_sts_ , dm_stat_ ),
                                  // The DataMover ONLY generates writes, so it ONLY
                                  // connects the write path.
                                  `CONNECT_AXIM_W( m_axi_s2mm_ , m_axi_ ) );
    // and murder the unused read channels (AR outputs/R inputs) to complete us
    `AXIM_NO_READS( m_axi_ );    

    // generate completions
    assign      m_cmpl_tvalid = cmpl_fifo_valid;
    // cmpl_fifo_out[31:0] = errors
    // cmpl_fifo_out[32 +: 13] = address
    assign      m_cmpl_tdata = { {19{1'b0}}, cmpl_fifo_out };    

    // eat up dones
    assign      s_done_tready = doneaddr_fifo_write;

    // assign errors
    assign      cmd_err_o = cmd_err_full;
    
    // and mark our space available.
    // we have space available if we're sitting in WAIT_NEXT_CHUNK (because we already _have_ an address)
    // or if we're sitting in IDLE and we have an address available.
    // Also if the FIFO has enough space to accept a chunk.
    assign      payload_has_space_o = (fifo_has_space && (state == WAIT_NEXT_CHUNK ||
                                       (state == IDLE && s_done_tvalid)));
                                       
endmodule

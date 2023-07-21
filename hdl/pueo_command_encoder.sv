`timescale 1ns / 1ps
// this is the *reverse* of the command decoder.
// It's a little goofy though because we have to define
// priorities and output acknowledges.
// Bit commands have the highest priority and go through
// immediately. They still have an acknowledge to allow
// them to be asserted on any phase, but they *should*
// be asserted at a fixed phase so the timing relation's
// known.
// Command processor data is asserted only if a bit command
// is not asserted.
// Triggers occur at the same time in the low 16 bits.
//
// This encoding is intended to work IN PARALLEL with the training
// output. The training pattern is A55A6996. The top 4 bits of that are 1010.
// We reserve the top 4 bits to indicate what type of message, and obviously
// just leave out 1010 as "no message" (note that bit commands could be a no message too
// but we have enough reserved.)
// We then assign 0001 and 0101 as "command processor bytes" (with 0101 being 'last byte')
// Bit commands get 0000 and the remaining 12 are reserved at the moment.
//
// There are then 12 possible bit commands. 
//
// The trigger data consists of the low 16 bits, with the top bit being a valid.
// (which indicates that the training pattern indicates "not valid").
// NOTE: The way the command capture works is that it captures on the 14th
// clock of the 16-clock sysclkx2 cycle.
// This compares to *our* phases as
// sysclk ifclkx2
// 0      0
// 0      1
// 1      2
// 1      3
// 2      4
// 2      5
// 3      6
// 3      7
// 4      8
// 4      9
// 5      10
// 5      11
// 6      12
// 6      13
// 7      14
// 7      15
// We need to capture in phase 6.
//
// The reason for the training pattern resulting in "nop" and "no trigger"
// is that if an interface is placed into training mode it won't screw things up.
module pueo_command_encoder(
        input sysclk_i,
        input sysclk_phase_i,
        output [31:0] command_o,
        
        input [11:0] bitcommand_i,
        output       bitcommand_ack,
        
        // tuser is the destination target
        input [7:0]  cmdproc_tdata,
        input [3:0]  cmdproc_tuser,
        input        cmdproc_tvalid,
        input        cmdproc_tlast,
        output       cmdproc_tready,
        
        // this is really only a 15-bit entry but screw it
        input [15:0] trig_tdata,
        input        trig_tvalid,
        output       trig_tready
    );

    reg [2:0] sysclk_local_phase = {3{1'b0}};    
    reg       capture_phase = 0;
    
    reg cmdproc_captured = 0;
    reg bitcommand_captured = 0;
    reg trig_captured = 0;
    
    reg [3:0] command_type = 4'b1010;
    reg [11:0] command_data = {12{1'b0}};
    reg [15:0] trig_data = {16{1'b0}};
    
 //   assign cmdproc_tready = (capture_phase && !bitcommand_i && cmdproc_tvalid);
 //   assign bitcommand_ack = (capture_phase && |bitcommand_i);
        
    always @(posedge sysclk_i) begin
        if (sysclk_phase_i) sysclk_local_phase <= 3'h1;
        else sysclk_local_phase <= sysclk_local_phase + 1;
        
        capture_phase <= (sysclk_local_phase == 5);
        bitcommand_captured <= capture_phase && |bitcommand_i;
        cmdproc_captured <= capture_phase && cmdproc_tvalid && !bitcommand_i;        
        trig_captured <= capture_phase && trig_tvalid;
            
        if (capture_phase) begin
            if (|bitcommand_i) begin
                command_type <= 4'b0000;
                command_data <= bitcommand_i;
            end else if (cmdproc_tvalid) begin
                command_type <= { 1'b0, cmdproc_tlast, 2'b01 };
                command_data <= { cmdproc_tuser, cmdproc_tdata };
            end else begin
                // nop. Yes, this could be 0000 as well but this makes it
                // easier for ILAs and such
                command_type <= 4'b1010;
                command_data <= {12{1'b0}};
            end
            trig_data <= { trig_tvalid, trig_tdata };
        end
    end

    assign trig_tready = trig_captured;
    assign cmdproc_tready = cmdproc_captured;
    assign bitcommand_ack = bitcommand_captured;

    assign command_o = { command_type, command_data, trig_data };

endmodule

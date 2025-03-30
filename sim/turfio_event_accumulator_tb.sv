`timescale 1ns / 1ps
module turfio_event_accumulator_tb;
    wire aclk;
    wire memclk;
    tb_rclk #(.PERIOD(8)) u_aclk(.clk(aclk));
    tb_rclk #(.PERIOD(3.333)) u_memclk(.clk(memclk));

    reg start = 0;    
    reg run_indata = 0;
    // this ends up being 24,584: each SURF has (1536*8 + 4) = 12,292 words and it takes
    // 2 clocks to deliver all SURFs.
    reg [15:0] indata_counter = {16{1'b0}};
    reg [31:0] indata = {32{1'b0}};
    reg        indata_valid = 0;
    wire [31:0] indata_tdata = indata;
    wire       indata_tvalid = indata_valid || run_indata;
    reg        indata_tlast = 0;
    wire       indata_tready;
    
    wire [63:0] outdata;
    wire        outdata_valid;
    wire        outdata_ready = 1'b1;
    wire        outdata_tlast;
    wire [4:0]  outdata_tuser;
    
    wire [63:0] hdrdata;
    wire        hdrvalid;
    wire        hdrready = 1'b1;
    wire        hdrtlast;
    
    always @(posedge aclk) begin
        if (start) run_indata <= 1;
        else if (indata_counter == 24582) run_indata <= 0;
        
        if (!run_indata) indata_counter <= {16{1'b0}};
        else indata_counter <= indata_counter + 1;

        indata_tlast <= (indata_counter == 24583);
        if (!run_indata) begin
            indata <= 32'hC0804000;
            indata_valid <= 1'b0;            
        end else begin
            // the way this works, the headers will contain
            // C1 81 41 01 C0 80 40 00
            // C3 83 43 03 C2 82 42 02
            // C5 85 45 05 C4 84 44 04
            // C7 87 47 07 C6 86 46 06
            // which should be interpreted as headers of
            // 00 02 04 06 (SURF0)
            // 40 42 44 46
            // ..
            // 81 83 85 87 (SURF6)
            // C1 C3 C5 C7 (TURFIO - ignored)
            //
            // the output data for SURF0 would then start off
            // 08 0A 0C 0E 10 12 14 16
            // etc. for SURF1/2/3/4/5/6
            indata[0 +: 8] <= indata[0 +: 8] + 1;
            indata[8 +: 8] <= indata[8 +: 8] + 1;
            indata[16 +: 8] <= indata[16 +: 8] + 1;
            indata[24 +: 8] <= indata[24 +: 8] + 1;
            indata_valid <= 1'b1;
        end
    end
    
    turfio_event_accumulator uut( .aclk(aclk),
                                  .aresetn(1'b1),
                                  .memclk(memclk),
                                  .memresetn(1'b1),
                                  .s_axis_tdata( indata_tdata ),
                                  .s_axis_tvalid(indata_tvalid),
                                  .s_axis_tready(indata_tready),
                                  .s_axis_tlast( indata_tlast),
                                  .m_hdr_tdata( hdrdata ),
                                  .m_hdr_tvalid(hdrvalid),
                                  .m_hdr_tready(hdrready),
                                  .m_hdr_tlast(hdrtlast),
                                  .m_payload_tdata(outdata ),
                                  .m_payload_tvalid(outdata_valid),
                                  .m_payload_tready(outdata_ready),
                                  .m_payload_tlast(outdata_tlast),
                                  .m_payload_tuser(outdata_tuser));
    initial begin
        #100;
        @(posedge aclk);
        #1 start = 1;
        @(posedge aclk);
        #1 start = 0;
    end                                  

endmodule

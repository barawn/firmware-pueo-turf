`timescale 1ns / 1ps
// Completion collector.
// The completion collector takes the completions from
// the various TURFIOs, reduces their errors and shoves
// the error and the address into a small FIFO.
// (plus same thing for the TURF headers)
// The output of those FIFOs is then checked to see if
// the addresses match and those are then fed as an output.
`include "interfaces.vh"
module event_completion_collector #(parameter MEMCLKTYPE="NONE")(
        input memclk,
        input memresetn,
        
        output err_any_o,
        output [13:0] cmpl_count_o,
        
        input [3:0] tio_mask_i,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_hdr_ , 24 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t0_ , 64 ), 
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t1_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t2_ , 64 ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_t3_ , 64 ),
        
        // completion is just the 13-bit addr, whatever
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_cmpl_ , 16 )
    );
    
    // The TURFIOs are structured as:
    // (doneaddr_fifo_out , dm_err_data )
    // where dm_err_data is a 32-bit error from tons o sources
    // and doneaddr_fifo_out is the 13-bit address.

    wire [3:0] turfio_tvalid;
    wire [3:0] turfio_tready;
    wire [15:0] turfio_tdata[3:0];
    
    assign turfio_tvalid = { s_t3_tvalid, s_t2_tvalid, s_t1_tvalid, s_t0_tvalid };
    assign s_t0_tready = turfio_tready[0];
    assign s_t1_tready = turfio_tready[1];
    assign s_t2_tready = turfio_tready[2];
    assign s_t3_tready = turfio_tready[3];
    
    assign turfio_tdata[0] = { {2{1'b0}}, |s_t0_tdata[31:0], s_t0_tdata[32 +: 13] };
    assign turfio_tdata[1] = { {2{1'b0}}, |s_t1_tdata[31:0], s_t1_tdata[32 +: 13] };
    assign turfio_tdata[2] = { {2{1'b0}}, |s_t2_tdata[31:0], s_t2_tdata[32 +: 13] };
    assign turfio_tdata[3] = { {2{1'b0}}, |s_t3_tdata[31:0], s_t3_tdata[32 +: 13] };

    `DEFINE_AXI4S_MIN_IFV( tio_ , 16, [3:0] );
    `DEFINE_AXI4S_MIN_IF( turf_ , 16);
    generate
        genvar i;
        for (i=0;i<4;i=i+1) begin : TIO
            `DEFINE_AXI4S_MIN_IF( tio_pf_ , 16 );
            event_collecter_slice u_slice(.aclk(memclk),
                                          .aresetn(memresetn),
                                          `CONNECT_AXI4S_MIN_IFV( s_axis_ , turfio_ , [i]),
                                          `CONNECT_AXI4S_MIN_IF( m_axis_ , tio_pf_ ));
            wire tiofifo_full;
            assign tio_pf_tready = !tiofifo_full;
            tio_cmpl_fifo u_fifo(.clk(memclk),
                                 .srst(!memresetn),
                                 .din(tio_pf_tdata),
                                 .full(tiofifo_full),
                                 .wr_en(tio_pf_tvalid && tio_pf_tready),
                                 .dout( tio_tdata[i] ),
                                 .valid( tio_tvalid[i] ),
                                 .rd_en( tio_tvalid[i] && tio_tready[i]));
        end
    endgenerate    
    
    // we also use a tio cmpl fifo for the TURF but we don't really need the register slice I think
    wire thdr_full;
    assign s_hdr_tready = !thdr_full;
    tio_cmpl_fifo u_turf_fifo(.clk(memclk),
                              .srst(!memresetn),
                              .din( { {2{1'b0}}, |s_hdr_tdata[7:0], s_hdr_tdata[8 +: 12] } ),
                              .full(thdr_full),
                              .wr_en( s_hdr_tvalid && s_hdr_tready ),
                              .dout( turf_tdata ),
                              .valid(turf_tvalid ),
                              .rd_en(turf_tvalid && turf_tready));
    reg [4:0] err_single = {5{1'b0}};
    (* CUSTOM_CC_SRC = MEMCLKTYPE *)
    reg err_any = 0;
    `DEFINE_AXI4S_MIN_IF( cmpl_in_ , 13 );

    wire [3:0] tio_masked = { (tio_tvalid[3] || tio_mask_i[3]),
                              (tio_tvalid[2] || tio_mask_i[2]),
                              (tio_tvalid[1] || tio_mask_i[1]),
                              (tio_tvalid[0] || tio_mask_i[0]) };

    // merge
    assign cmpl_in_tdata = turf_tdata[12:0];    
    assign cmpl_in_tvalid = turf_tvalid && (&tio_masked);
    assign turf_tready = cmpl_in_tvalid && cmpl_in_tready;
    assign tio_tready[0] = (cmpl_in_tvalid && cmpl_in_tready) || tio_mask_i[0];
    assign tio_tready[1] = (cmpl_in_tvalid && cmpl_in_tready) || tio_mask_i[1];
    assign tio_tready[2] = (cmpl_in_tvalid && cmpl_in_tready) || tio_mask_i[2];
    assign tio_tready[3] = (cmpl_in_tvalid && cmpl_in_tready) || tio_mask_i[3];    
    
    always @(posedge memclk) begin
        if (!memresetn) begin
            err_single <= {5{1'b0}};
        end else if (cmpl_in_tvalid && cmpl_in_tready) begin
            if (!tio_mask_i[0] && tio_tdata[0][13]) err_single[0] <= 1;
            if (!tio_mask_i[1] && tio_tdata[1][13]) err_single[1] <= 1;
            if (!tio_mask_i[2] && tio_tdata[2][13]) err_single[2] <= 1;
            if (!tio_mask_i[3] && tio_tdata[3][13]) err_single[3] <= 1;
            if (turf_tdata[13]) err_single[4] <= 1;
        end
        if (!memresetn) err_any <= 0;
        else err_any <= |err_single;
    end

    wire cmpl_fifo_full;
    assign cmpl_in_tready = !cmpl_fifo_full;
    cmpl_fifo u_fifo(.clk(memclk),
                     .srst(!memresetn),
                     .din( cmpl_in_tdata ),
                     .wr_en( cmpl_in_tvalid && cmpl_in_tready),
                     .full(cmpl_fifo_full),
                     .dout( m_cmpl_tdata ),
                     .valid( m_cmpl_tvalid ),
                     .rd_en( m_cmpl_tvalid && m_cmpl_tready ),
                     .data_count( cmpl_count_o ));
        
endmodule

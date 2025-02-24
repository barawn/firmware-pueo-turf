`timescale 1ns / 1ps
`include "interfaces.vh"
// EXTREMELY simplified AXI4-Lite to WB-type interface.
//
// The highly simplified version of this relies on the
// fact that a slave CAN WAIT for AWVALID *and* WVALID
// BEFORE asserting AWREADY (and WREADY).
//
// We therefore have three states:
// IDLE, WAITING_ACK, WAITING_READY
// We only transition from IDLE to WAITING_ACK when
// (awaddr_valid && wdata_valid) || (araddr_valid)
// and this signaling plus IDLE (or being in WAITING_ACK)
// generates cyc_o/stb_o.
// 
// In WAITING_ACK we transition back to IDLE if
// ack && ((is_write_txn && bready) || (!is_write_txn && rready))
// and of course WAITING_READY transitions back to IDLE
// on the same second qualifier.
// bvalid is generated by (is_write_txn && (state == WAITING_READY || (state == WAITING_ACK && ack_i))
// rvalid is generated by (!is_write_txn && (state == WAITING_READY || (state == WAITING_ACK && ack_i))
// rdata is (state == WAITING_ACK) ? dat_i : dat_hold
// dat_o is (state == IDLE) ? wdata : dat_hold
// sel_o is (state == IDLE) ? wstrb : strb_hold
module axil2wb #( parameter ADDR_WIDTH = 32,
                  parameter DATA_WIDTH = 32,
                  parameter DEBUG = "TRUE"
                 )( 
           input clk_i,
           input rst_i,
           `TARGET_NAMED_PORTS_AXI4L_IF( s_axi_ , ADDR_WIDTH, DATA_WIDTH ),
           `HOST_NAMED_PORTS_WB_IF( wb_ , ADDR_WIDTH, DATA_WIDTH )
    );

    // our transactions are minimum 2 clocks:
    // write:
    // clk  awvalid wvalid awready wready cyc/stb we ack bvalid bready state
    // 0    1       1      0       0      1       1  X   0      1      IDLE
    // 1    1       1      1       1      1       1  1   1      1      WAIT_ACK
    // 2    0       0      0       0      0       0  0   0      0      IDLE
    // read:
    // clk  arvalid arready rvalid rready cyc/stb ack state
    // 0    1       0       0      1      1       x   IDLE
    // 1    1       1       1      1      1       1   WAIT_ACK
    // 2    0       0       0      0      0       0   IDLE
    //

    // We DO NOT need to hold the write data out, because we can just
    // hold off on AWREADY/WREADY until ACK comes in.
    // We DO need to possibly hold the read data.
    reg [DATA_WIDTH-1:0] dat_hold = {DATA_WIDTH{1'b0}};
    
    reg is_write_txn = 0;
    
    localparam FSM_BITS = 2;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] WAIT_ACK = 1;
    localparam [FSM_BITS-1:0] WAIT_READY = 2;
    reg [FSM_BITS-1:0] state = IDLE;
    
    always @(posedge clk_i) begin
        if (state == WAIT_ACK && wb_ack_i && wb_we_o) dat_hold <= wb_dat_i;
        if (state == IDLE) is_write_txn <= (s_axi_awvalid && s_axi_wvalid);
        
        if (rst_i) state <= IDLE;
        else begin
            case (state)
                IDLE: if ((s_axi_awvalid && s_axi_wvalid) ||
                          (s_axi_arvalid)) state <= WAIT_ACK;
                WAIT_ACK: if (wb_ack_i) begin
                    if (is_write_txn && s_axi_bready) state <= IDLE;
                    else if (!is_write_txn && s_axi_rready) state <= IDLE;
                    else state <= WAIT_READY;
                end
                WAIT_READY: begin
                    if (is_write_txn && s_axi_bready) state <= IDLE;
                    else if (!is_write_txn && s_axi_rready) state <= IDLE;
                end
            endcase
        end
    end

    // the intercon gives us the WB-side debug, we really need the AXI-side
    // debug here, sigh.
    generate
        if (DEBUG == "TRUE") begin : DBG
            // MINIMAL ila: 12 probes
            wire [ADDR_WIDTH-1:0] axi_addr = (s_axi_awvalid) ? s_axi_awaddr : s_axi_araddr;
            wire [DATA_WIDTH-1:0] axi_data = (s_axi_wvalid) ? s_axi_wdata : s_axi_rdata;
            // probes:
            // axi_addr
            // axi_data
            // awvalid
            // awready
            // arvalid
            // arready
            // rvalid
            // rready
            // wvalid
            // wready
            // bvalid
            // bready
            axil2wb_ila u_ila(.clk(clk_i),
                              .probe0(axi_addr),
                              .probe1(axi_data),
                              .probe2(s_axi_awvalid),
                              .probe3(s_axi_awready),
                              .probe4(s_axi_arvalid),
                              .probe5(s_axi_arready),
                              .probe6(s_axi_wvalid),
                              .probe7(s_axi_wready),
                              .probe8(s_axi_rvalid),
                              .probe9(s_axi_rready),
                              .probe10(s_axi_bvalid),
                              .probe11(s_axi_bready));
        end
    endgenerate    

    assign wb_dat_o = s_axi_wdata;
    assign wb_adr_o = (wb_we_o) ? s_axi_awaddr : s_axi_araddr;
    assign wb_we_o = is_write_txn || (state == IDLE && (s_axi_awvalid && s_axi_wvalid));
    assign wb_cyc_o = (state == IDLE && ((s_axi_awvalid && s_axi_wvalid) || s_axi_arvalid)) ||
                      (state == WAIT_ACK);
    assign wb_stb_o = wb_cyc_o;
    assign wb_sel_o = s_axi_wstrb;
    
    assign s_axi_awready = is_write_txn && (state == WAIT_ACK && wb_ack_i);
    assign s_axi_wready = s_axi_awready;
    assign s_axi_arready = !is_write_txn && (state == WAIT_ACK && wb_ack_i);
    // note this still satisfies the slave write response handshake dependency:
    // s_axi_awvalid is asserted in WAIT_ACK if is_write_txn
    // s_axi_wvalid is asserted in WAIT_ACK if is_write_txn
    // s_axi_awready is asserted in WAIT_ACK if is_write_txn and wb_ack_i
    // s_axi_wready is equivalent to awready
    // so asserting bvalid in WAIT_ACK *if* wb_ack_i is OK
    assign s_axi_bvalid = is_write_txn && ((state == WAIT_ACK && wb_ack_i)||(state == WAIT_READY));    
    assign s_axi_bresp = 2'b00;
    assign s_axi_rvalid = !is_write_txn && ((state == WAIT_ACK && wb_ack_i) || (state == WAIT_READY));
    assign s_axi_rresp = 2'b00;    
    assign s_axi_rdata = (state == WAIT_ACK) ? wb_dat_i : dat_hold;
    
endmodule

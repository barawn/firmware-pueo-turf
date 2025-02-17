`timescale 1ns / 1ps
// Dumb module to assist with block diagrams. Often times
// in block diagrams AXI4 connects are "autodetected"
// - except that rarely works, and the "manual" methods
// also don't always work (sigh). It definitely doesn't work
// if you want to make an external one. So this module
// allows you to basically just define an AXI4-Lite interface
// space and hook it up. For instance, if you want an external
// AXI4-Lite interface, you just create this module, specify
// the address/data widths/etc., and hook one side up to the
// interconnect and the other as an external port.

// N.B.: This would be a damn lot of typing so I predefine
// a macro here (and then undefine it at the end)
// I don't use the big interface macros just because
// I want to include them all here.

// use STRB_TRUE for channels with STRB
`define STRB_TRUE
// use RESP_TRUE for channels with RESP in addition to data
`define RESP_TRUE

`define AXI_IN_CHANNEL( pfx, dname, width, has_strb, has_resp )    \
    input [ width - 1 : 0] pfx``dname, \
    `ifdef has_strb                   \
    input [( width /8)-1:0] pfx``strb, \
    `endif                             \
    `ifdef has_resp                    \
    input [1:0]            pfx``resp,  \
    `endif                             \
    input                  pfx``valid, \
    output                 pfx``ready

`define AXI_OUT_CHANNEL( pfx, dname, width, has_strb, has_resp )   \
    output [ width - 1 : 0] pfx``dname,  \
    `ifdef has_strb                     \
    output [( width /8)-1:0] pfx``strb, \
    `endif                               \
    `ifdef has_resp                    \
    output [1:0]            pfx``resp,  \
    `endif                             \
    output                  pfx``valid, \
    input                   pfx``ready

`define AXI_CONNECT( in_pfx, out_pfx, dname, has_strb, has_resp)    \
    assign out_pfx``dname = in_pfx``dname;                          \
    `ifdef has_strb                                                \
    assign out_pfx``strb = in_pfx``strb;                            \
    `endif                                                          \
    `ifdef has_resp                                                 \
    assign out_pfx``resp = in_pfx``resp;                            \
    `endif                                                          \
    assign out_pfx``valid = in_pfx``valid;                          \
    assign in_pfx``ready = out_pfx``ready                  

module axilite_bridge #(
        parameter C_AXI_DATA_WIDTH = 32,
        parameter C_AXI_ADDR_WIDTH = 32
    )(
        input aclk,
        input aresetn,
        `AXI_IN_CHANNEL(  s_axi_ar , addr, C_AXI_ADDR_WIDTH, STRB_FALSE, RESP_FALSE ),
        `AXI_IN_CHANNEL(  s_axi_aw , addr, C_AXI_ADDR_WIDTH, STRB_FALSE, RESP_FALSE ),
        `AXI_IN_CHANNEL(  s_axi_w ,  data, C_AXI_DATA_WIDTH, STRB_TRUE, RESP_FALSE ),
        `AXI_OUT_CHANNEL( s_axi_r ,  data, C_AXI_DATA_WIDTH, STRB_FALSE, RESP_TRUE ),
        `AXI_OUT_CHANNEL( s_axi_b ,  resp, 2, STRB_FALSE, RESP_FALSE ),

        `AXI_OUT_CHANNEL(  m_axi_ar , addr, C_AXI_ADDR_WIDTH, STRB_FALSE, RESP_FALSE ),
        `AXI_OUT_CHANNEL(  m_axi_aw , addr, C_AXI_ADDR_WIDTH, STRB_FALSE, RESP_FALSE ),
        `AXI_OUT_CHANNEL(  m_axi_w ,  data, C_AXI_DATA_WIDTH, STRB_TRUE, RESP_FALSE ),
        `AXI_IN_CHANNEL( m_axi_r ,  data, C_AXI_DATA_WIDTH, STRB_FALSE, RESP_TRUE ),
        `AXI_IN_CHANNEL( m_axi_b ,  resp, 2, STRB_FALSE, RESP_FALSE )
    );

    // now just hook 'em up.    
    `AXI_CONNECT( s_axi_ar , m_axi_ar , addr , STRB_FALSE, RESP_FALSE );
    `AXI_CONNECT( s_axi_aw , m_axi_aw , addr , STRB_FALSE, RESP_FALSE );
    `AXI_CONNECT( s_axi_w  , m_axi_w  , data , STRB_TRUE , RESP_FALSE );
    `AXI_CONNECT( m_axi_r  , s_axi_r  , data , STRB_FALSE , RESP_TRUE );
    `AXI_CONNECT( m_axi_b  , s_axi_b  , resp , STRB_FALSE , RESP_FALSE );
     
endmodule

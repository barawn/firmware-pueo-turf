    `define DEFINE_URAM_CASCADE_VEC( name, len , dir, ch )    \
        wire [22:0] name``cas_``dir``_addr_``ch [ len - 1:0];  \
        wire [8:0] name``cas_``dir``_bwe_``ch [ len - 1:0];    \
        wire name``cas_``dir``_dbiterr_``ch [ len - 1:0];      \
        wire [71:0] name``cas_``dir``_din_``ch [ len - 1:0];   \
        wire [71:0] name``cas_``dir``_dout_``ch [ len - 1:0];  \
        wire name``cas_``dir``_en_``ch [ len - 1:0];           \
        wire name``cas_``dir``_rdaccess_``ch [ len - 1:0];     \
        wire name``cas_``dir``_rdb_wr_``ch [ len - 1:0];       \
        wire name``cas_``dir``_sbiterr_``ch [ len - 1:0]
        
    `define DEFINE_URAM_FULL_CASCADE_VEC( name, len ) \
        `DEFINE_URAM_CASCADE_VEC( name, len , in , a );   \
        `DEFINE_URAM_CASCADE_VEC( name, len , in , b );   \
        `DEFINE_URAM_CASCADE_VEC( name, len , out , a );  \
        `DEFINE_URAM_CASCADE_VEC( name, len , out , b )  
        
    // horrible metaprogramming hacks
    `define URAM_PORT( name, dir, ch) .CAS_``dir``name``ch

    `define CONNECT_URAM_CASC_VEC_HELPER( name, dir, chsuffix, udir, uch)    \
        `URAM_PORT( _ADDR_ , udir, uch) ( name``cas_``dir``_addr_``chsuffix ),  \
        `URAM_PORT( _BWE_ , udir, uch) ( name``cas_``dir``_bwe_``chsuffix ),           \
        `URAM_PORT( _DBITERR_ , udir, uch) ( name``cas_``dir``_dbiterr_``chsuffix ),  \
        `URAM_PORT( _DIN_ , udir, uch) ( name``cas_``dir``_din_``chsuffix ), \
        `URAM_PORT( _DOUT_ , udir, uch) ( name``cas_``dir``_dout_``chsuffix ), \
        `URAM_PORT( _EN_ , udir, uch) ( name``cas_``dir``_en_``chsuffix ), \
        `URAM_PORT( _RDACCESS_, udir, uch) ( name``cas_``dir``_rdaccess_``chsuffix ), \
        `URAM_PORT( _RDB_WR_, udir, uch) ( name``cas_``dir``_rdb_wr_``chsuffix ), \
        `URAM_PORT( _SBITERR_, udir, uch) ( name``cas_``dir``_sbiterr_``chsuffix )        

    `define CONNECT_URAM_ACASCIN_VEC( name, suffix)  \
        `CONNECT_URAM_CASC_VEC_HELPER( name, in, a``suffix, IN, A )
    `define CONNECT_URAM_ACASCOUT_VEC( name, suffix)  \
        `CONNECT_URAM_CASC_VEC_HELPER( name, out, a``suffix, OUT, A )
    `define CONNECT_URAM_BCASCIN_VEC( name, suffix)  \
        `CONNECT_URAM_CASC_VEC_HELPER( name, in, b``suffix, IN, B )
    `define CONNECT_URAM_BCASCOUT_VEC( name, suffix)  \
        `CONNECT_URAM_CASC_VEC_HELPER( name, out, b``suffix, OUT, B )            

    `define HOOKUP_URAM_CASCADE_HELPER( inname , outname, chinsuffix, choutsuffix )   \
        assign inname``cas_in_addr_``chinsuffix = outname``cas_out_addr_``choutsuffix;   \
        assign inname``cas_in_bwe_``chinsuffix = outname``cas_out_bwe_``choutsuffix;     \
        assign inname``cas_in_dbiterr_``chinsuffix = outname``cas_out_dbiterr_``choutsuffix; \
        assign inname``cas_in_din_``chinsuffix = outname``cas_out_din_``choutsuffix; \
        assign inname``cas_in_dout_``chinsuffix = outname``cas_out_dout_``choutsuffix; \
        assign inname``cas_in_en_``chinsuffix = outname``cas_out_en_``choutsuffix; \
        assign inname``cas_in_rdaccess_``chinsuffix = outname``cas_out_rdaccess_``choutsuffix; \
        assign inname``cas_in_rdb_wr_``chinsuffix = outname``cas_out_rdb_wr_``choutsuffix; \
        assign inname``cas_in_sbiterr_``chinsuffix = outname``cas_out_sbiterr_``choutsuffix

    `define HOOKUP_URAM_CASCADE( inname, outname, ch, insuffix, outsuffix )    \
        `HOOKUP_URAM_CASCADE_HELPER( inname, outname, ch``insuffix , ch``outsuffix )

    `define TERMINATE_URAM_CASCADE_INPUT_HELPER( inname , chinsuffix )  \
        assign inname``cas_in_addr_``chinsuffix = {23{1'b0}};           \
        assign inname``cas_in_bwe_``chinsuffix = {9{1'b0}};             \
        assign inname``cas_in_dbiterr_``chinsuffix = 1'b0;              \
        assign inname``cas_in_din_``chinsuffix = {72{1'b0}};            \
        assign inname``cas_in_dout_``chinsuffix = {72{1'b0}};           \
        assign inname``cas_in_en_``chinsuffix = 1'b0;                   \
        assign inname``cas_in_rdaccess_``chinsuffix = 1'b0;             \
        assign inname``cas_in_rdb_wr_``chinsuffix = 1'b0;                            \
        assign inname``cas_in_sbiterr_``chinsuffix = 1'b0
        
     `define TERMINATE_URAM_CASCADE_INPUT( inname, ch, insuffix )   \
        `TERMINATE_URAM_CASCADE_INPUT_HELPER( inname, ch``insuffix )
        
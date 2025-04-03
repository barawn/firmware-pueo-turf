# These ALL get pullups because they can be turned into I2C magically.
# B2B1 126 is C1 and labelled TTXA - this is OUT to TURFIO (so still TX)
# B2B1 130 is C6 and labelled TRXA - this is IN from TURFIO (so still RX)
set_property IOSTANDARD LVCMOS25 [get_ports TTXA]
set_property PACKAGE_PIN C1 [get_ports TTXA]
set_property PULLUP true [get_ports TTXA]
set_property IOSTANDARD LVCMOS25 [get_ports TRXA]
set_property PACKAGE_PIN C6 [get_ports TRXA]
set_property PULLUP true [get_ports TRXA]

# B2B1 89 is F4 and labelled TTXB
# B2B1 87 is F5 and labelled TRXB
set_property IOSTANDARD LVCMOS25 [get_ports TTXB]
set_property PACKAGE_PIN F4 [get_ports TTXB]
set_property PULLUP true [get_ports TTXB]
set_property IOSTANDARD LVCMOS25 [get_ports TRXB]
set_property PACKAGE_PIN F5 [get_ports TRXB]
set_property PULLUP true [get_ports TRXB]

# B2B1 91 is E5 and labelled TTXC
# B2B1 93 is F5 and labelled TRXC
set_property IOSTANDARD LVCMOS25 [get_ports TTXC]
set_property PACKAGE_PIN E5 [get_ports TTXC]
set_property PULLUP true [get_ports TTXC]
set_property IOSTANDARD LVCMOS25 [get_ports TRXC]
set_property PACKAGE_PIN E4 [get_ports TRXC]
set_property PULLUP true [get_ports TRXC]

# B2B1 142 is C3 and labelled TTXD - NO! TRXD!
# B2B1 144 is C4 and labelled TRXD - NO! TTXD!
set_property IOSTANDARD LVCMOS25 [get_ports TTXD]
set_property PACKAGE_PIN C4 [get_ports TTXD]
set_property PULLUP true [get_ports TTXD]
set_property IOSTANDARD LVCMOS25 [get_ports TRXD]
set_property PACKAGE_PIN C3 [get_ports TRXD]
set_property PULLUP true [get_ports TRXD]

# these do NOT get any pullups: they can be used to detect
# presence of a programmed TURFIO D2/B3/E2/E1
set_property -dict { IOSTANDARD LVCMOS25 PACKAGE_PIN D2 } [get_ports TRESETB_A]
set_property -dict { IOSTANDARD LVCMOS25 PACKAGE_PIN B3 } [get_ports TRESETB_B]
set_property -dict { IOSTANDARD LVCMOS25 PACKAGE_PIN E2 } [get_ports TRESETB_C]
set_property -dict { IOSTANDARD LVCMOS25 PACKAGE_PIN E1 } [get_ports TRESETB_D]

# B2B1 30 is F9 and labelled GPS_TX but it is FROM GPS (so RX here!)
# B2B1 28 is E9 and labelled GPS_RX but it is TO GPS   (so TX here!)
set_property IOSTANDARD LVCMOS25 [get_ports GPS_RX]
set_property PACKAGE_PIN F9 [get_ports GPS_RX]
set_property PULLUP true [get_ports GPS_RX]
set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN E9} [get_ports GPS_TX]

# B2B1 22 is C8 and labelled SCL_2V5
# B2B1 24 is D8 and labelled SDA_2V5
set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN C8} [get_ports CLK_SCL]
set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN D8} [get_ports CLK_SDA]

# HSK REMAPPING:
# HSK REMAPPING VERSION 2! THE ODDS AND EVENS SWAP, DAMNIT
# WE OBVIOUSLY HAVE TO REMAP F_TOUT0/3.3V, EVERYONE ELSE IN FIRMWARE

# ODDS
# HSK_RX1 -> TGP1   B2B-1 31  B7    -> E6
# HSK_TX1 -> TGP2   B2B-1 33  A7    -> G8
# GPIO0 -> TIN0     B2B-1 40  D6    -> F8
# GPIO1 -> TIN1     B2B-1 42  F6    -> D9
# GPIO2 -> TGP0     B2B-1 44  G6    -> C9
# GPIO3 -> CAL_SDA  B2B-1 56  D7    -> E7

# EVENS
# TRIG_IN -> IRQ_B  B2B-1 38  E6    -> B7
# CAL_SCL -> SCLK   B2B-1 84  G8    -> A7
# CAL_SDA -> MISO   B2B-1 82  F8    -> D6
# HSK_RX0 -> MOSI   B2B-1 32  D9    -> F6
# HSK_TX0 -> CS_B   B2B-1 34  C9    -> G6
# GPIO4 -> CAL_SCL  B2B-1 58  E7    -> D7

# TRIG_OUT -> TOUT0 B2B-1 29  H8

set_property IOSTANDARD LVCMOS25 [get_ports CAL_SCL]
set_property PACKAGE_PIN D7 [get_ports CAL_SCL]
set_property PULLUP true [get_ports CAL_SCL]
set_property IOSTANDARD LVCMOS25 [get_ports CAL_SDA]
set_property PACKAGE_PIN E7 [get_ports CAL_SDA]
set_property PULLUP true [get_ports CAL_SDA]

set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN A7} [get_ports UART_SCLK]
set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN F6} [get_ports UART_MOSI]
set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN D6} [get_ports UART_MISO]
set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN G6} [get_ports UART_CS_B]
set_property IOSTANDARD LVCMOS25 [get_ports UART_IRQ_B]
set_property PACKAGE_PIN B7 [get_ports UART_IRQ_B]
set_property PULLUP true [get_ports UART_IRQ_B]

set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN AR12} [get_ports SYSCLK_P]
set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN AR13} [get_ports SYSCLK_N]

set_property -dict {IOSTANDARD LVDS PACKAGE_PIN AM10} [get_ports {TXCLK_P[0]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN AN10} [get_ports {TXCLK_N[0]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN B15} [get_ports {TXCLK_P[1]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN C15} [get_ports {TXCLK_N[1]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN P16} [get_ports {TXCLK_P[2]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN N16} [get_ports {TXCLK_N[2]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN AW10} [get_ports {TXCLK_P[3]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN AW11} [get_ports {TXCLK_N[3]}]

set_property -dict {IOSTANDARD LVDS PACKAGE_PIN AL15 UNAVAILABLE_DURING_CALIBRATION 1} [get_ports {COUT_P[0]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN AM15} [get_ports {COUT_N[0]}]

set_property -dict {IOSTANDARD LVDS PACKAGE_PIN A18} [get_ports {COUT_P[1]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN B18} [get_ports {COUT_N[1]}]

set_property -dict {IOSTANDARD LVDS PACKAGE_PIN C13} [get_ports {COUT_P[2]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN D13} [get_ports {COUT_N[2]}]

set_property -dict {IOSTANDARD LVDS PACKAGE_PIN AY9} [get_ports {COUT_P[3]}]
set_property -dict {IOSTANDARD LVDS PACKAGE_PIN AW9 UNAVAILABLE_DURING_CALIBRATION 1} [get_ports {COUT_N[3]}]

set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN B13} [get_ports {CINTIO_P[0]}]
set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN A12} [get_ports {CINTIO_N[0]}]

set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN A14} [get_ports {CINTIO_P[1]}]
set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN A13} [get_ports {CINTIO_N[1]}]

set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN A14} [get_ports {CINTIO_P[1]}]
set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN A13} [get_ports {CINTIO_N[1]}]

set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN BB8} [get_ports {CINTIO_P[2]}]
set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN BB9} [get_ports {CINTIO_N[2]}]

set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN AN13} [get_ports {CINTIO_P[3]}]
set_property -dict {IOSTANDARD LVDS DIFF_TERM_ADV TERM_100 PACKAGE_PIN AM13} [get_ports {CINTIO_N[3]}]

set_property IOSTANDARD LVDS [get_ports {CINA_P[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_P[0]}]
set_property IOSTANDARD LVDS [get_ports {CINA_P[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_P[1]}]
set_property IOSTANDARD LVDS [get_ports {CINA_P[2]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_P[2]}]
set_property IOSTANDARD LVDS [get_ports {CINA_P[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_P[3]}]
set_property IOSTANDARD LVDS [get_ports {CINA_P[4]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_P[4]}]
set_property IOSTANDARD LVDS [get_ports {CINA_P[5]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_P[5]}]
set_property IOSTANDARD LVDS [get_ports {CINA_P[6]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_P[6]}]

set_property IOSTANDARD LVDS [get_ports {CINA_N[0]}]
set_property PACKAGE_PIN J16 [get_ports {CINA_P[0]}]
set_property PACKAGE_PIN H16 [get_ports {CINA_N[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_N[0]}]
set_property IOSTANDARD LVDS [get_ports {CINA_N[1]}]
set_property PACKAGE_PIN D18 [get_ports {CINA_N[1]}]
set_property PACKAGE_PIN C18 [get_ports {CINA_P[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_N[1]}]
set_property IOSTANDARD LVDS [get_ports {CINA_N[2]}]
set_property PACKAGE_PIN E16 [get_ports {CINA_P[2]}]
set_property PACKAGE_PIN D16 [get_ports {CINA_N[2]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_N[2]}]
set_property IOSTANDARD LVDS [get_ports {CINA_N[3]}]
set_property PACKAGE_PIN G18 [get_ports {CINA_P[3]}]
set_property PACKAGE_PIN F18 [get_ports {CINA_N[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_N[3]}]
set_property IOSTANDARD LVDS [get_ports {CINA_N[4]}]
set_property PACKAGE_PIN G16 [get_ports {CINA_P[4]}]
set_property PACKAGE_PIN F15 [get_ports {CINA_N[4]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_N[4]}]
set_property IOSTANDARD LVDS [get_ports {CINA_N[5]}]
set_property PACKAGE_PIN P15 [get_ports {CINA_P[5]}]
set_property PACKAGE_PIN N15 [get_ports {CINA_N[5]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_N[5]}]
set_property IOSTANDARD LVDS [get_ports {CINA_N[6]}]
set_property PACKAGE_PIN F14 [get_ports {CINA_P[6]}]
set_property PACKAGE_PIN E14 [get_ports {CINA_N[6]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINA_N[6]}]

set_property IOSTANDARD LVDS [get_ports {CINB_P[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_P[0]}]
set_property IOSTANDARD LVDS [get_ports {CINB_P[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_P[1]}]
set_property IOSTANDARD LVDS [get_ports {CINB_P[2]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_P[2]}]
set_property IOSTANDARD LVDS [get_ports {CINB_P[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_P[3]}]
set_property IOSTANDARD LVDS [get_ports {CINB_P[4]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_P[4]}]
set_property IOSTANDARD LVDS [get_ports {CINB_P[5]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_P[5]}]
set_property IOSTANDARD LVDS [get_ports {CINB_P[6]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_P[6]}]

set_property IOSTANDARD LVDS [get_ports {CINB_N[0]}]
set_property PACKAGE_PIN L17 [get_ports {CINB_N[0]}]
set_property PACKAGE_PIN K17 [get_ports {CINB_P[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_N[0]}]
set_property IOSTANDARD LVDS [get_ports {CINB_N[1]}]
set_property PACKAGE_PIN C16 [get_ports {CINB_N[1]}]
set_property PACKAGE_PIN B16 [get_ports {CINB_P[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_N[1]}]
set_property IOSTANDARD LVDS [get_ports {CINB_N[2]}]
set_property PACKAGE_PIN E17 [get_ports {CINB_P[2]}]
set_property PACKAGE_PIN D17 [get_ports {CINB_N[2]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_N[2]}]
set_property IOSTANDARD LVDS [get_ports {CINB_N[3]}]
set_property PACKAGE_PIN B17 [get_ports {CINB_N[3]}]
set_property PACKAGE_PIN A17 [get_ports {CINB_P[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_N[3]}]
set_property IOSTANDARD LVDS [get_ports {CINB_N[4]}]
set_property PACKAGE_PIN J18 [get_ports {CINB_P[4]}]
set_property PACKAGE_PIN H18 [get_ports {CINB_N[4]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_N[4]}]
set_property IOSTANDARD LVDS [get_ports {CINB_N[5]}]
set_property PACKAGE_PIN M15 [get_ports {CINB_P[5]}]
set_property PACKAGE_PIN L15 [get_ports {CINB_N[5]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_N[5]}]
set_property IOSTANDARD LVDS [get_ports {CINB_N[6]}]
set_property PACKAGE_PIN K16 [get_ports {CINB_P[6]}]
set_property PACKAGE_PIN K15 [get_ports {CINB_N[6]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINB_N[6]}]

set_property IOSTANDARD LVDS [get_ports {CINC_P[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_P[0]}]
set_property IOSTANDARD LVDS [get_ports {CINC_P[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_P[1]}]
set_property IOSTANDARD LVDS [get_ports {CINC_P[2]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_P[2]}]
set_property IOSTANDARD LVDS [get_ports {CINC_P[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_P[3]}]
set_property IOSTANDARD LVDS [get_ports {CINC_P[4]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_P[4]}]
set_property IOSTANDARD LVDS [get_ports {CINC_P[5]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_P[5]}]
set_property IOSTANDARD LVDS [get_ports {CINC_P[6]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_P[6]}]

set_property IOSTANDARD LVDS [get_ports {CINC_N[0]}]
set_property PACKAGE_PIN AM11 [get_ports {CINC_N[0]}]
set_property PACKAGE_PIN AN11 [get_ports {CINC_P[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_N[0]}]
set_property IOSTANDARD LVDS [get_ports {CINC_N[1]}]
set_property PACKAGE_PIN AN14 [get_ports {CINC_N[1]}]
set_property PACKAGE_PIN AP14 [get_ports {CINC_P[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_N[1]}]
set_property IOSTANDARD LVDS [get_ports {CINC_N[2]}]
set_property PACKAGE_PIN AJ15 [get_ports {CINC_N[2]}]
set_property PACKAGE_PIN AK15 [get_ports {CINC_P[2]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_N[2]}]
set_property IOSTANDARD LVDS [get_ports {CINC_N[3]}]
set_property PACKAGE_PIN AJ14 [get_ports {CINC_N[3]}]
set_property PACKAGE_PIN AK14 [get_ports {CINC_P[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_N[3]}]
set_property IOSTANDARD LVDS [get_ports {CINC_N[4]}]
set_property PACKAGE_PIN AR15 [get_ports {CINC_N[4]}]
set_property PACKAGE_PIN AR14 [get_ports {CINC_P[4]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_N[4]}]
set_property IOSTANDARD LVDS [get_ports {CINC_N[5]}]
set_property PACKAGE_PIN AL14 [get_ports {CINC_N[5]}]
set_property PACKAGE_PIN AM14 [get_ports {CINC_P[5]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_N[5]}]
set_property IOSTANDARD LVDS [get_ports {CINC_N[6]}]
set_property PACKAGE_PIN AU11 [get_ports {CINC_N[6]}]
set_property PACKAGE_PIN AV11 [get_ports {CINC_P[6]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CINC_N[6]}]

# NOTE: These are the non-prototype definitions for CIND. The prototype can't be used for C/D anyway.
set_property IOSTANDARD LVDS [get_ports {CIND_P[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_P[0]}]
set_property IOSTANDARD LVDS [get_ports {CIND_P[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_P[1]}]
set_property IOSTANDARD LVDS [get_ports {CIND_P[2]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_P[2]}]
set_property IOSTANDARD LVDS [get_ports {CIND_P[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_P[3]}]
set_property IOSTANDARD LVDS [get_ports {CIND_P[4]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_P[4]}]
set_property IOSTANDARD LVDS [get_ports {CIND_P[5]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_P[5]}]
set_property IOSTANDARD LVDS [get_ports {CIND_P[6]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_P[6]}]

set_property IOSTANDARD LVDS [get_ports {CIND_N[0]}]
set_property PACKAGE_PIN BA8 [get_ports {CIND_N[0]}]
set_property PACKAGE_PIN BA7 [get_ports {CIND_P[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_N[0]}]
set_property IOSTANDARD LVDS [get_ports {CIND_N[1]}]
set_property PACKAGE_PIN AW8 [get_ports {CIND_N[1]}]
set_property PACKAGE_PIN AY8 [get_ports {CIND_P[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_N[1]}]
set_property IOSTANDARD LVDS [get_ports {CIND_N[2]}]
set_property PACKAGE_PIN AP10 [get_ports {CIND_N[2]}]
set_property PACKAGE_PIN AR10 [get_ports {CIND_P[2]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_N[2]}]
set_property IOSTANDARD LVDS [get_ports {CIND_N[3]}]
set_property PACKAGE_PIN BA6 [get_ports {CIND_P[3]}]
set_property PACKAGE_PIN BB6 [get_ports {CIND_N[3]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_N[3]}]
set_property IOSTANDARD LVDS [get_ports {CIND_N[4]}]
set_property PACKAGE_PIN AV12 [get_ports {CIND_P[4]}]
set_property PACKAGE_PIN AW12 [get_ports {CIND_N[4]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_N[4]}]
set_property IOSTANDARD LVDS [get_ports {CIND_N[5]}]
set_property PACKAGE_PIN AV9 [get_ports {CIND_N[5]}]
set_property PACKAGE_PIN AV8 [get_ports {CIND_P[5]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_N[5]}]
set_property IOSTANDARD LVDS [get_ports {CIND_N[6]}]
set_property PACKAGE_PIN AN12 [get_ports {CIND_N[6]}]
set_property PACKAGE_PIN AP12 [get_ports {CIND_P[6]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {CIND_N[6]}]


#set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN D6} [get_ports {GPIO[0]}]
#set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN F6} [get_ports {GPIO[1]}]
#set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN G6} [get_ports {GPIO[2]}]
#set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN D7} [get_ports {GPIO[3]}]
#set_property -dict {IOSTANDARD LVCMOS25 PACKAGE_PIN E7} [get_ports {GPIO[4]}]

set_property -dict {PACKAGE_PIN AD12} [get_ports MGTCLK_N]
set_property -dict {PACKAGE_PIN AD11} [get_ports MGTCLK_P]
set_property -dict {PACKAGE_PIN AG2} [get_ports {MGTRX_P[0]}]
set_property -dict {PACKAGE_PIN AG1} [get_ports {MGTRX_N[0]}]
set_property -dict {PACKAGE_PIN AF4} [get_ports {MGTRX_P[1]}]
set_property -dict {PACKAGE_PIN AF3} [get_ports {MGTRX_N[1]}]
set_property -dict {PACKAGE_PIN AE2} [get_ports {MGTRX_P[2]}]
set_property -dict {PACKAGE_PIN AE1} [get_ports {MGTRX_N[2]}]
set_property -dict {PACKAGE_PIN AH4} [get_ports {MGTRX_P[3]}]
set_property -dict {PACKAGE_PIN AH3} [get_ports {MGTRX_N[3]}]

set_property -dict {PACKAGE_PIN AF8} [get_ports {MGTTX_P[0]}]
set_property -dict {PACKAGE_PIN AF7} [get_ports {MGTTX_N[0]}]
set_property -dict {PACKAGE_PIN AE6} [get_ports {MGTTX_P[1]}]
set_property -dict {PACKAGE_PIN AE5} [get_ports {MGTTX_N[1]}]
set_property -dict {PACKAGE_PIN AD8} [get_ports {MGTTX_P[2]}]
set_property -dict {PACKAGE_PIN AD7} [get_ports {MGTTX_N[2]}]
set_property -dict {PACKAGE_PIN AG6} [get_ports {MGTTX_P[3]}]
set_property -dict {PACKAGE_PIN AG5} [get_ports {MGTTX_N[3]}]


##set_property -dict { PACKAGE_PIN AN2 } [get_ports { NC_RX_P[1] }]
##set_property -dict { PACKAGE_PIN AN1 } [get_ports { NC_RX_N[1] }]
##set_property -dict { PACKAGE_PIN AP4 } [get_ports { NC_RX_P[0] }]
##set_property -dict { PACKAGE_PIN AP3 } [get_ports { NC_RX_N[0] }]
##set_property -dict { PACKAGE_PIN AM8 } [get_ports { NC_TX_P[1] }]
##set_property -dict { PACKAGE_PIN AM7 } [get_ports { NC_TX_N[1] }]
##set_property -dict { PACKAGE_PIN AN6 } [get_ports { NC_TX_P[0] }]
##set_property -dict { PACKAGE_PIN AN5 } [get_ports { NC_TX_N[0] }]

set_property -dict {PACKAGE_PIN AH12} [get_ports GBE_CLK_P]
set_property -dict {PACKAGE_PIN AH11} [get_ports GBE_CLK_N]

# these are labelled GBEB
set_property -dict {PACKAGE_PIN AR6} [get_ports {GBE_TX_P[1]}]
set_property -dict {PACKAGE_PIN AR5} [get_ports {GBE_TX_N[1]}]
set_property -dict {PACKAGE_PIN AT4} [get_ports {GBE_RX_P[1]}]
set_property -dict {PACKAGE_PIN AT3} [get_ports {GBE_RX_N[1]}]
# these are labelled GBEA
set_property -dict {PACKAGE_PIN AP8} [get_ports {GBE_TX_P[0]}]
set_property -dict {PACKAGE_PIN AP7} [get_ports {GBE_TX_N[0]}]
set_property -dict {PACKAGE_PIN AR2} [get_ports {GBE_RX_P[0]}]
set_property -dict {PACKAGE_PIN AR1} [get_ports {GBE_RX_N[0]}]

##set_property -dict { PACKAGE_PIN AG10 } [get_ports { NC_GCLK_P }]
##set_property -dict { PACKAGE_PIN AG9 }  [get_ports { NC_GCLK_N }]

set_property IOSTANDARD LVDS [get_ports {DDR_CLK_N[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {DDR_CLK_N[0]}]
set_property PACKAGE_PIN AT22 [get_ports {DDR_CLK_P[0]}]
set_property PACKAGE_PIN AT21 [get_ports {DDR_CLK_N[0]}]
set_property IOSTANDARD LVDS [get_ports {DDR_CLK_P[0]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {DDR_CLK_P[0]}]
set_property IOSTANDARD LVDS [get_ports {DDR_CLK_N[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {DDR_CLK_N[1]}]
set_property PACKAGE_PIN E32 [get_ports {DDR_CLK_P[1]}]
set_property PACKAGE_PIN D32 [get_ports {DDR_CLK_N[1]}]
set_property IOSTANDARD LVDS [get_ports {DDR_CLK_P[1]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {DDR_CLK_P[1]}]

#set_property -dict {PACKAGE_PIN B6 IOSTANDARD LVCMOS25} [get_ports {LGPIO[0]}]
#set_property -dict {PACKAGE_PIN B5 IOSTANDARD LVCMOS25} [get_ports {LGPIO[1]}]

# these do not matter


set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
# this is TURF 1, gets replaced
set_property BITSTREAM.CONFIG.USR_ACCESS 0xD555E94A [current_design]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets ps_clk]

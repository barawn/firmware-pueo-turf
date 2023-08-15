# The dipshit Aurora IP brings out DMONITOR, but it *doesn't*
# let you hook up DMONITORCLK.
#
# So eff it, we'll forcibly do it here after place/before route.

puts "Forcibly connecting DMONITORCLK!"

set gtlist [ get_cells -hier -filter { NAME =~ u_aurora/ALN[?].u_aurora/*GTHE4_CHANNEL_PRIM_INST } ]
set psclknet [ get_nets -hier -filter { NAME =~ "ps_clk" }]

foreach gt $gtlist {
    set dmonitorclk [get_pins -of_objects $gt -filter { NAME =~ *DMONITORCLK* }]
    disconnect_net -pinlist $dmonitorclk
    connect_net -hier -net $psclknet -objects $dmonitorclk
}

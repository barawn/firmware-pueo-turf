# The dipshit Aurora IP brings out DMONITOR, but it *doesn't*
# let you hook up DMONITORCLK.
#
# So eff it, we'll forcibly do it here after place/before route.

puts "Forcibly connecting DMONITORCLK!"

set gtlist [ get_cells -hier -filter { NAME =~ u_aurora/ALN[?].u_aurora/*GTHE4_CHANNEL_PRIM_INST } ]
set psclknet [ get_nets -hier -filter { NAME =~ "ps_clk" }]

foreach gt $gtlist {
    # this works as long as we don't change the above
    set idx [string index $gt 13]
    set dmonitorclk [get_pins -of_objects $gt -filter { NAME =~ *DMONITORCLK* }]
    disconnect_net -pinlist $dmonitorclk
    connect_net -hier -net $psclknet -objects $dmonitorclk
    # dipshit Aurora IP #2: ALSO doesn't bring out DRPRESET despite it
    # being 100% necessary.
    set drprstin [get_pins -of_objects $gt -filter { NAME =~ *DRPRST* }]
    disconnect_net -pinlist $drprstin
    # now find the actual reset we want...
    set rstnetnm u_aurora/drp_reset[$idx]
    set thisFilt "NAME =~ $rstnetnm"
    set drprst [get_nets -hier -filter $thisFilt]
    connect_net -hier -net $drprst -objects $drprstin
}



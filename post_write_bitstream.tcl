# post_write_bitstream hook
#
# For the TURF because we have overlays, we need to do buckets and
# buckets of work here. Sigh.

# search_repo_dir finds the repo dir so long as we were called ANYWHERE
# in the project AND the project dir is called vivado_project
proc search_repo_dir {} {
    set projdir [get_property DIRECTORY [current_project]]
    set fullprojdir [file normalize $projdir]
    set projdirlist [ file split $fullprojdir ]
    set projindex [lsearch $projdirlist "vivado_project"]
    set basedirlist [lrange $projdirlist 0 [expr $projindex - 1]]
    return [ file join {*}$basedirlist ]
}

# convenience function add a UART fragment
# note: removed the final close to factor it out as a function
proc addUart { f nextFragment } {
    puts $f ""
    puts $f "\tfragment@${nextFragment} \{"
    puts $f "\t\ttarget = <&spi0>;"
    puts $f "\t\tfrag1: __overlay__ \{"
    puts $f "\t\t\t#address-cells = <1>;"
    puts $f "\t\t\t#size-cells = <0>;"
    puts $f "\t\t\tstatus = \"okay\";"
    puts $f "\t\t\t"
    puts $f "\t\t\tsc16is752: sc16is752@0 \{"
    puts $f "\t\t\t\tcompatible = \"nxp,sc16is752\";"
    puts $f "\t\t\t\treg = <0>;"
    puts $f "\t\t\t\tclock-frequency = <14745600>;"
    puts $f "\t\t\t\tinterrupt-parent = <&gpio>;"
    # this is on EMIO 0 so it's 78, 2 is IRQ_TYPE_EDGE_FALLING
    puts $f "\t\t\t\tinterrupts = <78 2>;"
    puts $f "\t\t\t\t#gpio-controller;"
    puts $f "\t\t\t\t#gpio-cells = <2>;"
    puts $f "\t\t\t\tspi-max-frequency = <4000000>;"
    # clock probing fails or some shit
    #    puts $f "\t\t\t\t"
    #    puts $f "\t\t\t\tsc16is752_clk: sc16is752_clk \{"
    #    puts $f "\t\t\t\t\tcompatible = \"fixed-clock\";"
    #    puts $f "\t\t\t\t\t#clock-cells = <0>;"
    #    puts $f "\t\t\t\t\tclock-frequency = <14745600>;"
    #    puts $f "\t\t\t\t\t\};"
    puts $f "\t\t\t\};"
    puts $f "\t\t\};"
    puts $f "\t\};"
}

# ethernet is at 156.25 MHz so at 30 MHz it has 5 samples
# per clock, plenty to detect rise/fall I hope
proc addHsk { f nextFragment } {
    puts $f ""
    puts $f "\tfragment@${nextFragment} \{"
    puts $f "\t\ttarget = <&spi1>;"
    puts $f "\t\tfrag2: __overlay__ \{"
    puts $f "\t\t\t#address-cells = <1>;"
    puts $f "\t\t\t#size-cells = <0>;"
    puts $f "\t\t\tstatus = \"okay\";"
    puts $f "\t\t\t"
    puts $f "\t\t\tturfhskRead: turfhskRead@0 \{"
    puts $f "\t\t\t\tcompatible = \"osu,turfhskRead\";"
    puts $f "\t\t\t\treg = <0>;"
    puts $f "\t\t\t\tspi-max-frequency = <30000000>;"
    puts $f "\t\t\t\};"
    puts $f "\t\t\tturfhskWrite: turfhskWrite@1 \{"
    puts $f "\t\t\t\tcompatible = \"osu,turfhskWrite\";"
    puts $f "\t\t\t\treg = <1>;"
    puts $f "\t\t\t\tspi-max-frequency = <30000000>;"
    puts $f "\t\t\t\};"
    puts $f "\t\t\};"
    puts $f "\t\};"
}

# add housekeeping gpio-keys interrupt
proc addHskInterrupt { f nextFragment } {
    puts $f ""
    puts $f "\tfragment@${nextFragment} \{"
    puts $f "\t\ttarget-path = \"/\";"
    puts $f "\t\t__overlay__ \{"
    puts $f "\t\t\thsk-gpio-keys \{"
    puts $f "\t\t\t\tcompatible = \"gpio-keys\";"
    puts $f "\t\t\t\thsk0 \{"
    puts $f "\t\t\t\t\tlabel = \"hsk0\";"
    puts $f "\t\t\t\t\tgpios = <&gpio 79 0>;"
    puts $f "\t\t\t\t\tlinux,code = <30>;"
    puts $f "\t\t\t\t\tgpio-key,wakeup;"
    puts $f "\t\t\t\t\};"
    puts $f "\t\t\t\};"
    puts $f "\t\t\};"
    puts $f "\t\};"    
}

proc finishOverlay { f } {
    puts $f "\};"
}

# post_write_bitstream is called out of flow so we need to
# get our fancy-pants stuff back

set projdir [search_repo_dir]
source [file join $projdir project_utility.tcl]
# get the build dtbo script
source [file join $projdir tcl build_dtbo.tcl]
# add hsi to our search path
lappend auto_path [file join $projdir tcl hsi]
# specify our device-tree-xlnx path
set dtxpath [file join $projdir hw device-tree-xlnx]
# specify our dtc path (note I haven't added a static dtc for linux yet!!)
if { $tcl_platform(platform) == "windows" } {
    set dtcpath [file join $projdir bin win dtc.exe]
} else {
    set dtcpath [file join $projdir bin lin dtc]
}

# set up all the names
set curdir [pwd]
set ver [get_built_project_version]
puts "ver $ver"
set verstring [pretty_version $ver]
puts "verstring $verstring"
set topname [get_property TOP [current_design]]
set origbit [format "%s.bit" $topname]
set origltx [format "%s.ltx" $topname]
set origxsa [format "%s.xsa" $topname]

set fullbitname [format "%s_%s.bit" $topname $verstring]
set fullltxname [format "%s_%s.ltx" $topname $verstring]
set fulldtboname [format "%s_%s.dtbo" $topname $verstring]
set fullxsaname [format "%s_%s.xsa" $topname $verstring]

set build_dir [file join $projdir build]

set bitfn [file join $build_dir $fullbitname]
set ltxfn [file join $build_dir $fullltxname]
set xsafn [file join $build_dir $fullxsaname]
set dtbofn [file join $build_dir $fulldtboname]

file copy -force $origbit $bitfn
puts "Built bitstream: $bitfn"

write_debug_probes -force $ltxfn
puts "Wrote debug probes: $ltxfn"

# sigh, write_hw_platform hilariously generates the bitstream again
write_hw_platform -fixed -include_bit -force [file join $projdir hw $xsafn]
puts "Created XSA: $xsafn"

# and now build the dtsi
set dtsifn [build_dtsi $xsafn $dtxpath]
puts "Built dtsi: $dtsifn"

# and now replace the compatible strings
package require fileutil
set fromCompat "xlnx,axi-uartlite2-2.1"
set toCompat "xlnx,xps-uartlite-1.00.a"
set replCmd [list string map [list $fromCompat $toCompat]]
fileutil::updateInPlace $dtsifn $replCmd

# figure out how many fragments there are
set numFragments [fileutil::grep fragment $dtsifn]
# we start at 0 so the next one is just the length of the list
set nextFragment [llength $numFragments]

# set the newline
set newline "\n\r"

# read in the dtsi
set f [open $dtsifn]
set lines [split [read $f] $newline]
close $f

# remove last two elements in list b/c split above yields a final empty
set lines [lreplace [lreplace $lines end end] end end]

# now write the altered dtsi
set f [open $dtsifn "w"]
puts -nonewline $f [join $lines $newline]
addUart $f $nextFragment
set nextFragment [ expr $nextFragment + 1 ]
addHsk $f $nextFragment
set nextFragment [ expr $nextFragment + 1 ]
addHskInterrupt $f $nextFragment
finishOverlay $f
close $f

# and now build the dtbo
set dtbofn [build_dtbo $dtsifn $dtcpath]
puts "Built dtbo: $dtbofn"


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

# and now build the dtbo
set dtbofn [build_dtbo $dtsifn $dtcpath]
puts "Built dtbo: $dtbofn"


package require fileutil

# you need to pass:
#   xsa filename
#   device-tree-xlnx repo
if { [llength $argv] < 2 } {
    error "must pass 2 arguments: xsa_filename and repo_path (path to device-treee-xlnx)"
}

set xsa_filename [lindex $argv 0]
set dtx_path [lindex $argv 1]
set projname [file rootname [file tail $xsa_filename]]
set bitname "${projname}.bit"
set dtsi_path "tmp_${projname}"
set dtsi "pl.dtsi"
set newdtsi "${projname}.dtsi"

puts "xsa: ${xsa_filename}"
puts "dtx_path: ${dtx_path}"
puts "projname: ${projname}"
puts "bitname: ${bitname}"
puts "dtsi_path: ${dtsi_path}"
puts "dtsi: ${dtsi}"
puts "newdtsi: ${newdtsi}"

# blow away the old one
file delete ${newdtsi}

set design [hsi open_hw_design $xsa_filename]
hsi set_repo_path $dtx_path
hsi create_sw_design device-tree -os device_tree -proc psu_cortexa53_0
hsi set_property CONFIG.dt_overlay true [hsi::get_os]
hsi generate_target -dir ${dtsi_path}
hsi close_hw_design $design

# now we need to grab the dtsi, it's called pl.dtsi
file copy [file join ${dtsi_path} ${dtsi}] ${newdtsi}
# and delete the original
file delete -force ${dtsi_path}
# and fix its dumbassery
set allres [fileutil::grep "firmware-name" ${newdtsi}]
set res [lindex $allres 0]
set splitapart [split $res "="]
set origfn [lindex $splitapart 1]
set nqfn [format {%s} [string map {{"} {}} $origfn]]
set nsfn [format {%s} [string map {{ } {}} $nqfn]]
set fn [format {%s} [string map {{;} {}} $nsfn]]
puts "Original filename was ${fn}"
puts "New filename is ${bitname}"
fileutil::updateInPlace $newdtsi {string map "$fn $bitname"}
puts "Built $newdtsi"

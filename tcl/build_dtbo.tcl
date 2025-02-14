# I FINALLY FIGURED THIS OUT
# We CAN import the HSI stuff into Vivado's build process.
# The key is to make sure the device-tree-xlnx checkout
# MATCHES THE RELEASE YOU'RE USING.
# So you need to checkout v2022.2 on 2022.2, for instance
# Do git tag to see the tag list

# NOTE NOTE NOTE: this only works for ultrascale
# change the processor if it's a zynq

# NOTE: THIS ASSUMES IF THE XSA HAS THE NAME
# this_is_the_name.xsa
# THAT THE BITFILE WILL BE NAMED
# this_is_the_name.bit
# AND YOU WANT THE DTSI NAMED
# this_is_the_name.dtsi
# AND THEN WHEN YOU CALL build_dtbo YOU WANT IT NAMED
# this_is_the_name.dtbo
# !!!

# THIS IS SPLIT IN TWO:
# First, call
#
# build_dtsi this_is_the_name.xsa path-to-device-tree-xlnx
#
# Next, call
#
# build_dtbo this_is_the_name.dtsi
#
# It is split in two to allow edits inbetween!
#

# Build the dtsi file using the hsi package.
# You need to make sure hsi is available:
# lappend auto_path path_to_hsi
proc build_dtsi { xsa dtx } {
    package require hsi
    package require fileutil
    
    set projname [file rootname [file tail $xsa]]
    set dtsiname "${projname}.dtsi" 
    set bitname "${projname}.bit"
    set tmpdir "tmp_${projname}"
    set origdtsi "pl.dtsi"
    
    puts "xsa filename: ${xsa}"
    puts "device-tree-xlnx repository path: ${dtx}"
    puts "base project name: ${projname}"
    puts "creating: ${dtsiname}"
    puts "using bitfile name: ${bitname}"

    # blow away the original, I don't care
    file delete ${dtsiname}
    file delete -force ${tmpdir}
    
    set design [hsi::open_hw_design $xsa]
    hsi::set_repo_path $dtx
    hsi::create_sw_design device-tree -os device_tree -proc psu_cortexa53_0
    common::set_property CONFIG.dt_overlay true [hsi::get_os]
    hsi::generate_target -dir ${tmpdir}
    hsi::close_hw_design $design

    # now so so much more work

    # now we need to grab the dtsi, it's called pl.dtsi
    puts "Moving ${origdtsi} to ${dtsiname}"    
    file copy [file join ${tmpdir} ${origdtsi}] ${dtsiname}
    # and delete the original
    file delete -force ${tmpdir}

    # and fix its dumbassery
    set allres [fileutil::grep "firmware-name" ${dtsiname}]
    set res [lindex $allres 0]
    set splitapart [split $res "="]
    set origfn [lindex $splitapart 1]
    set nqfn [format {%s} [string map {{"} {}} $origfn]]
    set nsfn [format {%s} [string map {{ } {}} $nqfn]]
    set fn [format {%s} [string map {{;} {}} $nsfn]]
    puts "Original bitfile: ${fn}"
    puts "New bitfile: ${bitname}"

    # based on rosetta code due to list stupidity issues
    # https://rosettacode.org/wiki/Globally_replace_text_in_several_files#Tcl
    set replCmd [list string map [list $fn $bitname]]    
    fileutil::updateInPlace $dtsiname $replCmd
    puts "dtsi: $dtsiname"
    return $dtsiname
}

# YOU NEED TO PASS THE PATH TO AN EXECUTABLE DTC HERE
# YOU MAY NEED TO COMPILE IT!
proc build_dtbo { dtsi dtcpath } {
    if { ![file executable $dtcpath] } {
	puts "$dtcpath is not executable!!"
	return
    }
    # build the arguments
    set projname [file rootname [file tail $dtsi]]
    set dtbo "${projname}.dtbo"
    set dtcargs "-@ -O dtb -o ${dtbo} ${dtsi}"
    set dtccmd [list $dtcpath $dtcargs]
    exec {*}$dtccmd
    return $dtbo
}

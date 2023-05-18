# utility function
proc get_repo_dir {} {
    set projdir [get_property DIRECTORY [current_project]]
    set projdirlist [ file split $projdir ]
    set basedirlist [ lreplace $projdirlist end end ]
    return [ file join {*}$basedirlist ]
}

# update include paths
puts "Updating Verilog include path..."
set include_dir [file join [get_repo_dir] "verilog-library-barawn" "include"]
set_property include_dirs [list $include_dir] [current_fileset]

# Make sure the project behavior stays the same.
#set f [open [ file join [get_repo_dir] "barawn_repository" ] ]
#set repo [read $f]
#if {$repo in [get_property ip_repo_paths [current_project]]} {
#    puts "Skipping IP repo update, already done"
#} else {
#    puts "Updating IP repo with ${repo}"
#    set_property ip_repo_paths $repo [current_project]
#}

# check for pre-init script
set pre [ file join [get_repo_dir] "pre_synthesis.tcl"]
if [ file exists $pre ] {
    if {$pre in [get_files -of_objects [get_filesets utils_1]]} {
	puts "Skipping pre init script update"
    } else {
	puts "Updating pre init script"
	add_files -fileset utils_1 -norecurse $pre
	set_property STEPS.SYNTH_DESIGN.TCL.PRE [ get_files $pre -of [get_fileset utils_1] ] [get_runs synth_1]
    }
}



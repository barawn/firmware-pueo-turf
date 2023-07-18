# utility function
proc get_repo_dir {} {
    set projdir [get_property DIRECTORY [current_project]]
    set projdirlist [ file split $projdir ]
    set basedirlist [ lreplace $projdirlist end end ]
    return [ file join {*}$basedirlist ]
}

# source scripts
set tclbits_dir [file join [get_repo_dir] "verilog-library-barawn" "tclbits"]
source [file join $tclbits_dir "utility.tcl"]
source [file join $tclbits_dir "repo_files.tcl"]

# update include paths
add_include_dir [file join [get_repo_dir] "verilog-library-barawn" "include"]

# set pre-synthesis script
set_pre_synthesis_tcl [file join [get_repo_dir] "pre_synthesis.tcl"]

# add local repository
add_ip_repository [file join [get_repo_dir] "repository"]

# last thing to do before opening
check_all



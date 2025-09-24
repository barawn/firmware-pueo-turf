set we_are_synthesis [info exists are_we_synthesis]
puts "we are synthesis: $we_are_synthesis"

######## CONVENIENCE FUNCTIONS
# These all have escape clauses because clocks sometimes don't exist in the elaboration/synthesis
# steps.

# i hate you xilinx
proc get_all_cells { theFilter { opts "-hier" } } {
    set optsList [ split $opts ]    
    set basicFilt "$theFilter && PRIMITIVE_LEVEL != MACRO"
    set macroFilt "$theFilter && PRIMITIVE_LEVEL == MACRO"
    set basicCells [get_cells {*}$optsList -filter $basicFilt ]
    # for macros, we segregate them off, and then ALSO pick up all cells which have it as their parent.
    # this also picks up DSPs, I think, but I hope that's okay??
    # The overall problem is a bug in Vivado, I think. But this works around it.
    set macroCells [get_cells {*}$optsList -filter $macroFilt ]
    foreach m $macroCells {
        set parentFilt "PARENT == $m"
        set macroChildren [get_cells -hier -filter $parentFilt ]
        lappend basicCells $macroChildren
    }
    return $basicCells
}

proc set_cc_paths { srcClk dstClk ctlist } {
    if {$srcClk eq ""} {
        puts "set_cc_paths: No source clock: returning."
        return
    }
    if {$dstClk eq ""} {
        puts "set_cc_paths: No destination clock: returning."
        return
    }
    array set ctypes $ctlist
    set srcType $ctypes($srcClk)
    set dstType $ctypes($dstClk)
    set maxTime [get_property PERIOD $srcClk]
    
    set srcRegs [get_all_cells "CUSTOM_CC_SRC == $srcType" ]
    set dstRegs [get_all_cells "CUSTOM_CC_DST == $dstType" ]
    
    if {[llength $srcRegs] == 0} {
        puts "set_cc_paths: No registers flagged with CUSTOM_CC_SRC $srcType: returning."
        return
    }
    if {[llength $dstRegs] == 0} {
        puts "set_cc_paths: No registers flagged with CUSTOM_CC_DST $dstType: returning."
        return
    }
    set_max_delay -datapath_only -from $srcRegs -to $dstRegs $maxTime
}

proc set_gray_paths { srcClk dstClk ctlist } {
    if {$srcClk eq ""} {
        puts "set_gray_paths: No source clock: returning."
        return
    }
    if {$dstClk eq ""} {
        puts "set_gray_paths: No destination clock: returning."
        return
    }
    array set ctypes $ctlist
    set srcType $ctypes($srcClk)
    set dstType $ctypes($dstClk)
    set maxTime [get_property PERIOD $srcClk]
    set maxSkew [expr min([get_property PERIOD $srcClk], [get_property PERIOD $dstClk])]

    set srcRegs [get_all_cells "CUSTOM_GRAY_SRC == $srcType" ]
    set dstRegs [get_all_cells "CUSTOM_GRAY_DST == $dstType" ]
    
    if {[llength $srcRegs] == 0} {
        puts "set_gray_paths: No registers flagged with CUSTOM_GRAY_SRC $srcType: returning."
        return
    }
    if {[llength $dstRegs] == 0} {
        puts "set_gray_paths: No registers flagged with CUSTOM_GRAY_DST $dstType: returning."
        return
    }
    set_max_delay -datapath_only -from $srcRegs -to $dstRegs $maxTime
    set_bus_skew -from $srcRegs -to $dstRegs $maxSkew
}

proc set_ignore_paths { srcClk dstClk ctlist } {
    if {$srcClk eq ""} {
        puts "set_ignore_paths: No source clock: returning."
        return
    }
    if {$dstClk eq ""} {
        puts "set_ignore_paths: No destination clock: returning."
        return
    }
    array set ctypes $ctlist
    set srcType $ctypes($srcClk)
    set dstType $ctypes($dstClk)
    
    set srcRegs [get_all_cells "CUSTOM_IGN_SRC == $srcType" ]
    set dstRegs [get_all_cells "CUSTOM_IGN_DST == $dstType" ]

    if {[llength $srcRegs] == 0} {
        puts "set_ignore_paths: No registers flagged with CUSTOM_IGN_SRC $srcType: returning."
        return
    }
    if {[llength $dstRegs] == 0} {
        puts "set_ignore_paths: No registers flagged with CUSTOM_IGN_DST $dstType: returning."
        return
    }
    set_false_path -from $srcRegs -to $dstRegs
}

# The standard multicycle path calls don't actually use "set_multicycle_path" because
# that whole procedure is dopestick annoying and often DOES NOT WORK if you're going
# between domains that don't have an integer relationship.
# Instead we just friggin' embed the min delay/max delays in UNITS OF THE SOURCE CLOCK.
#
# To have a destination be included in MULTIPLE tags you include them SEPARATED BY SPACES
# you CANNOT HAVE A MULTICYCLE PATH with one source to multiple destinations in this syntax:
# you have to break it up somewhere.
#
# TAGS HAVE TO JUST BE SIMPLE ALPHANUMERICS
#
# convenience function
proc build_multicycle_re_dst { tag } {
    # this works out to be "($tag)|($tag .*)|(.* $tag .*)|(.* $tag$)"
    # it'd be awesome if I could figure out how to make a word boundary work,
    # but I can't.
    set RE_DST {"(}    
    append RE_DST $tag
    append RE_DST {)|(}
    append RE_DST $tag
    append RE_DST { .*)|(.* }
    append RE_DST $tag
    append RE_DST { .*)|(.* }
    append RE_DST $tag
    append RE_DST {$)"}
    return $RE_DST
}

# note: the min/max delay attributes are set ONLY ON THE SOURCE REGISTER.
# EXAMPLE
# (* CUSTOM_MC_SRC_TAG = "ATOP_XFER", CUSTOM_MC_MIN = -2.5, CUSTOM_MC_MAX = 3.0 *)
# reg atop = 0;
# (* CUSTOM_MC_SRC_TAG = "BTOP_XFER", CUSTOM_MC_MIN = -3, CUSTOM_MC_MAX = 4.5 *)
# reg btop = 0;
# (* CUSTOM_MC_DST_TAG = "ATOP_XFER BTOP_XFER" *)
# reg dest = 0;
proc set_mc_paths { tag } {
    set RE_DST [build_multicycle_re_dst $tag]
    set srcRegs [get_all_cells "CUSTOM_MC_SRC_TAG == $tag" ] 
    set dstRegs [get_cells -hier -regexp -filter "CUSTOM_MC_DST_TAG =~ $RE_DST"]
    if {[llength $srcRegs] == 0} {
        puts "set_mc_paths: No registers flagged with CUSTOM_MC_SRC_TAG $tag: returning."
        return
    }
    if {[llength $dstRegs] == 0} {
        puts "set_mc_paths: No registers flagged with CUSTOM_MC_DST_TAG $tag: returning."
        return
    }
    set thisReg [lindex $srcRegs 0]
    set srcClk [get_clocks -of_objects [get_cells $thisReg]]
    set thisSourceClockPeriod [get_property PERIOD $srcClk]
    set thisMin [get_property CUSTOM_MC_MIN [get_cells $thisReg]]
    if {[llength $thisMin] == 0} {
        puts "set_mc_paths: No minimum delay specified in tag $tag: returning."
        return
    }        
    set thisMax [get_property CUSTOM_MC_MAX [get_cells $thisReg]]
    if {[llength $thisMax] == 0} {
        puts "set_mc_paths: No maximum delay specified in tag $tag: returning."
        return
    }        
    set minTime [expr $thisMin*$thisSourceClockPeriod]
    set maxTime [expr $thisMax*$thisSourceClockPeriod]
    puts "set_mc_paths: $tag min $minTime max $maxTime"
    set_min_delay -from $srcRegs -to $dstRegs $minTime
    set_max_delay -from $srcRegs -to $dstRegs $maxTime
}    


######## END CONVENIENCE FUNCTIONS

######## CLOCK DEFINITIONS

if {[info exists clktypes]} {
    unset clktypes
}

#### PIN CLOCKS
set mgt_clk [create_clock -period 7.999 -name mgt_clock [get_ports -filter { NAME =~ "MGTCLK_N" && DIRECTION == "IN" }]]
set clktypes($mgt_clk) MGTCLK

set sys_clk [create_clock -period 8.000 -name sys_clock [get_ports -filter { NAME =~ "SYSCLK_N" && DIRECTION == "IN" }]]
set clktypes($sys_clk) SYSCLK

set gbeclk [create_clock -period 6.400 -name gbe_clock [get_ports -filter { NAME =~ "GBE_CLK_P" && DIRECTION == "IN" }]]
set clktypes($gbeclk) GBECLK

#set ddr_clk0 [create_clock -period 3.333 -name ddr_clk0 [get_ports -filter { NAME =~ "DDR_CLK_P[0]" && DIRECTION == "IN" }]]
#set clktypes($ddr_clk0) DDRCLK0
set ddr_genclk [get_clocks -of_objects [get_cells u_tioctl/u_idelayctrl67] ]
puts "DDR clock was named ${ddr_genclk} - renaming to ddr_clk0"
set isgenclk [get_property -quiet IS_GENERATED $ddr_genclk]
set isusergenclk [get_property -quiet IS_USER_GENERATED $ddr_genclk]
if {[llength $isgenclk] && [expr $isgenclk == 1] && [llength $isusergenclk] && [expr $isusergenclk == 0]} {
    puts "DDR clk was generated: checking to see if we need to rename it"
    if {[get_property IS_RENAMED $ddr_genclk ]} {
        puts "Already renamed, skipping."
        set userclk $user_genclk
    } else {
        puts "Renaming $ddr_genclk to ddrclk0."
        set ddr_genclkpin [get_property SOURCE_PINS $ddr_genclk]
        create_generated_clock -name ddr_clk0 [get_pins $ddr_genclkpin]
        set ddrclk0 [get_clocks ddr_clk0]
    }
} else {
    puts "Cannot rename $ddr_genclk!"
}
if {[info exists ddrclk0]} {
    set clktypes($ddrclk0) DDRCLK0
}

set ddrclk1 [create_clock -period 3.334 -name ddr_clk1 [get_ports -filter { NAME =~ "DDR_CLK_P[1]" && DIRECTION == "IN" }]]
set clktypes($ddrclk1) DDRCLK1

#### INTERNAL CLOCKS
set ifclk67 [get_clocks -of_objects [get_cells -hier -filter { NAME =~ "u_tioctl/u_clocks/u_ifclk67_buf" }]]
set clktypes($ifclk67) IFCLK67

set ifclk68 [get_clocks -of_objects [get_cells -hier -filter { NAME =~ "u_tioctl/u_clocks/u_ifclk68_buf" }]]
set clktypes($ifclk68) IFCLK68

set psclk [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "ps_clk" }]]
set clktypes($psclk) PSCLK

## just for safety we're going to try avoiding the [] name here and create a new one
set userbuf [get_cells -hier -filter { NAME =~ "u_aurora/u_clock/user_clk_buf_i"}]
if { [info exists userbuf] } {
    puts "Found userclk buf: $userbuf"
    set user_genclk [get_clocks -of_objects $userbuf]
    puts "Userclk was named ${user_genclk}"
    # In synthesis, this is a USER generated clock because of the way the IP
    # works. In implementation it's an ACTUAL generated clock, so we can rename it.
    # Dodge that issue here.
    set isgenclk [get_property -quiet IS_GENERATED $user_genclk]
    set isusergenclk [get_property -quiet IS_USER_GENERATED $user_genclk]
    if {[llength $isgenclk] && [expr $isgenclk == 1] && [llength $isusergenclk] && [expr $isusergenclk == 0]} {
        puts "Userclk was generated: checking to see if we need to rename it"
        if {[get_property IS_RENAMED $user_genclk]} {
            puts "Already renamed, skipping."
            set userclk $user_genclk
        } else {
            puts "Renaming $user_genclk to userclk."
            set userclkpin [get_property SOURCE_PINS $user_genclk]
            create_generated_clock -name user_clock [get_pins $userclkpin]
            set userclk [get_clocks user_clock]
        }
    } else {
        puts "Cannot rename $user_genclk!"
    }
} else {
    puts "Cannot find userclk buffer, skipping!"
}

if {[info exists userclk]} {
    set clktypes($userclk) USERCLK
}

# create the clktypelist variable to save
set clktypelist [array get clktypes]

######## END CLOCK DEFINITIONS

# EVERYTHING AFTER THIS IS IMPLEMENTATION ONLY

if { $we_are_synthesis != 1 } {
    puts "Processing timing constraints."


    # magic grab all of the flag_sync'd guys. This is not ideal but it'll work for now.
    set sync_flag_regs [get_cells -hier -filter {NAME =~ *FlagToggle_clkA_reg*}]
    set sync_sync_regs [get_cells -hier -filter {NAME =~ *SyncA_clkB_reg*}]
    set sync_syncB_regs [get_cells -hier -filter {NAME =~ *SyncB_clkA_reg*}]
    
    set_max_delay -datapath_only -from $sync_flag_regs -to $sync_sync_regs 10.000
    set_max_delay -datapath_only -from $sync_sync_regs -to $sync_syncB_regs 10.000
    
    # magic grab all of the clockmon regs
    set clockmon_level_regs [ get_cells -hier -filter {NAME =~ *u_clkmon/*clk_32x_level_reg*} ]
    set clockmon_cc_regs [ get_cells -hier -filter {NAME =~ *u_clkmon/*level_cdc_ff1_reg*}]
    set clockmon_run_reset_regs [ get_cells -hier -filter {NAME =~ *u_clkmon/clk_running_reset_reg*}]
    set clockmon_run_regs [get_cells -hier -filter {NAME=~ *u_clkmon/*u_clkmon*}]
    set clockmon_run_cc_regs [get_cells -hier -filter {NAME=~ *u_clkmon/clk_running_status_cdc1_reg*}]
    set_max_delay -datapath_only -from $clockmon_level_regs -to $clockmon_cc_regs 10.000
    set_max_delay -datapath_only -from $clockmon_run_reset_regs -to $clockmon_run_regs 10.000
    set_max_delay -datapath_only -from $clockmon_run_regs -to $clockmon_run_cc_regs 10.000
    
    # more magic grabs
    set async_regs_A [get_cells -hier -filter {NAME=~u_aurora*loopback_sync*reg_clkA_reg*}]
    set async_regs_B [get_cells -hier -filter {NAME=~u_aurora*loopback_sync*pipe_clkB_reg*}]
    set_max_delay -datapath_only -from $async_regs_A -to $async_regs_B 10.000
    
    # don't want to dig into the core, sigh.
    set lock_regs [get_cells -hier -filter {NAME=~u_ethernet/SFP[*]*rx_block_lock_reg_reg}]
    set ber_regs [get_cells -hier -filter {NAME=~u_ethernet/SFP[*]*rx_high_ber_reg_reg}]
    set stat_regs [get_cells -hier -filter {NAME=~u_ethernet/gbe_status_reg[*]}]
    set_max_delay -datapath_only -from $lock_regs -to $stat_regs 10.0
    set_max_delay -datapath_only -from $ber_regs -to $stat_regs 10.0
    
    # just.... blanket for now
    #set_max_delay -datapath_only -from $psclk -to $userclk 10.0
    #set_max_delay -datapath_only -from $userclk -to $psclk 10.0
    
    # guard on userclk/ddrclk0 due to generated crap
    if {[info exists userclk]} {
        set_cc_paths $psclk $userclk $clktypelist
        set_cc_paths $userclk $psclk $clktypelist
    }
    
    if {[info exists ddrclk0]} {
        set_cc_paths $psclk $ddrclk0 $clktypelist
        # now ddr -> ethernet
        set_cc_paths $ddrclk0 $gbeclk $clktypelist
        # only have a flag going this direction, leave it alone for now
        #set_cc_paths $gbeclk $ddrclk0 $clktypelist
    }
    
    set_cc_paths $psclk $ifclk67 $clktypelist
    set_cc_paths $ifclk67 $psclk $clktypelist
    
    set_cc_paths $psclk $ifclk68 $clktypelist
    set_cc_paths $ifclk68 $psclk $clktypelist
    
    set_cc_paths $psclk $sys_clk $clktypelist
    set_cc_paths $sys_clk $psclk $clktypelist
    
    set_cc_paths $psclk $gbeclk $clktypelist
    set_cc_paths $gbeclk $psclk $clktypelist
    
    set_cc_paths $sys_clk $gbeclk $clktypelist
    set_cc_paths $gbeclk $sys_clk $clktypelist
    
    set_cc_paths $sys_clk $userclk $clktypelist
    
    set_cc_paths $ddrclk0 $psclk $clktypelist
    set_cc_paths $ddrclk0 $sys_clk $clktypelist
    
    set_cc_paths $gbeclk $ddrclk0 $clktypelist
    set_cc_paths $ddrclk0 $gbeclk $clktypelist
    
    set_mc_paths TRIG_META
    set_mc_paths TRIG_DEAD
    set_mc_paths TRIG_HELDOFF
}

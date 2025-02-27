######## CONVENIENCE FUNCTIONS
# These all have escape clauses because clocks sometimes don't exist in the elaboration/synthesis
# steps.

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
    set srcRegs [get_cells -hier -filter "CUSTOM_CC_SRC == $srcType"]
    set dstRegs [get_cells -hier -filter "CUSTOM_CC_DST == $dstType"]
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
    set srcRegs [get_cells -hier -filter "CUSTOM_GRAY_SRC == $srcType"]
    set dstRegs [get_cells -hier -filter "CUSTOM_GRAY_DST == $dstType"]
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
    set srcRegs [get_cells -hier -filter "CUSTOM_IGN_SRC == $srcType"]
    set dstRegs [get_cells -hier -filter "CUSTOM_IGN_DST == $dstType"]
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

######## END CONVENIENCE FUNCTIONS

######## CLOCK DEFINITIONS

#### PIN CLOCKS
set mgt_clk [create_clock -period 7.999 -name mgt_clock [get_ports -filter { NAME =~ "MGTCLK_N" && DIRECTION == "IN" }]]
set clktypes($mgt_clk) MGTCLK

set sys_clk [create_clock -period 8.000 -name sys_clock [get_ports -filter { NAME =~ "SYSCLK_N" && DIRECTION == "IN" }]]
set clktypes($sys_clk) SYSCLK

set gbe_clk [create_clock -period 6.400 -name gbe_clock [get_ports -filter { NAME =~ "GBE_CLK_P" && DIRECTION == "IN" }]]
set clktypes($gbe_clk) GBECLK

set ddr_clk0 [create_clock -period 3.333 -name ddr_clk0 [get_ports -filter { NAME =~ "DDR_CLK_P[0]" && DIRECTION == "IN" }]]
set clktypes($ddr_clk0) DDRCLK0

set ddr_clk1 [create_clock -period 3.334 -name ddr_clk1 [get_ports -filter { NAME =~ "DDR_CLK_P[1]" && DIRECTION == "IN" }]]
set clktypes($ddr_clk1) DDRCLK1

#### INTERNAL CLOCKS
set ifclk67 [get_clocks -of_objects [get_cells -hier -filter { NAME =~ "u_tioctl/u_clocks/u_ifclk67_buf" }]
set clktypes($ifclk67) IFCLK67

set ifclk68 [get_clocks -of_objects [get_cells -hier -filter { NAME =~ "u_tioctl/u_clocks/u_ifclk68_buf" }]
set clktypes($ifclk68) IFCLK68

set psclk [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "ps_clk" }]]
set clktypes($psclk) PSCLK

set userclk [get_clocks -of_objects [get_pins -hier -filter { NAME =~ "u_aurora/u_clock/user_clk_buf_i/O" }]]
set clktypes($userclk) USERCLK

# create the clktypelist variable to save
set clktypelist [array get clktypes]

######## END CLOCK DEFINITIONS

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

# just.... blanket for now
set_max_delay -datapath_only -from $psclk -to $userclk 10.0
set_max_delay -datapath_only -from $userclk -to $psclk 10.0

# OK, now use the *proper* functions. Let's see what happens!
set_cc_paths $psclk $ifclk67 $clktypelist
set_cc_paths $ifclk67 $psclk $clktypelist

set_cc_paths $psclk $ifclk68 $clktypelist
set_cc_paths $ifclk68 $psclk $clktypelist

set_cc_paths $psclk $ddr_clk0 $clktypelist

set_cc_paths $psclk $sys_clk $clktypelist

set_cc_path $psclk $gbe_clk $clktypelist
set_cc_path $gbe_clk $psclk $clktypelist

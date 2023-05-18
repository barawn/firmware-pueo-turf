set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN D9 } [get_ports { HSK_UART_txd }]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN C9 } [get_ports { HSK_UART_rxd }]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN C8 } [get_ports { CLK_IIC_scl_io }]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN D8 } [get_ports { CLK_IIC_sda_io }]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN A7 } [get_ports { HSK2_UART_txd }]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN B7 } [get_ports { HSK2_UART_rxd }]
set_property -dict { IOSTANDARD LVDS PACKAGE_PIN AR12 DIFF_TERM TRUE} [get_ports { SYSCLK_P }]
set_property -dict { IOSTANDARD LVDS PACKAGE_PIN AR13 DIFF_TERM TRUE} [get_ports { SYSCLK_N }]

set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN D6 } [get_ports { GPIO[0] }]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN F6 } [get_ports { GPIO[1] }]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN G6 } [get_ports { GPIO[2] }]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN D7 } [get_ports { GPIO[3] }]
set_property -dict { IOSTANDARD LVCMOS33 PACKAGE_PIN E7 } [get_ports { GPIO[4] }]

set_property -dict { PACKAGE_PIN AD12 } [get_ports { MGTCLK_N } ]
set_property -dict { PACKAGE_PIN AD11 } [get_ports { MGTCLK_P } ]
set_property -dict { PACKAGE_PIN AG2 } [get_ports { MGTRX_P[0] }]
set_property -dict { PACKAGE_PIN AG1 } [get_ports { MGTRX_N[0] }]
set_property -dict { PACKAGE_PIN AF4 } [get_ports { MGTRX_P[1] }]
set_property -dict { PACKAGE_PIN AF3 } [get_ports { MGTRX_N[1] }]
set_property -dict { PACKAGE_PIN AE2 } [get_ports { MGTRX_P[2] }]
set_property -dict { PACKAGE_PIN AE1 } [get_ports { MGTRX_N[2] }]
set_property -dict { PACKAGE_PIN AH4 } [get_ports { MGTRX_P[3] }]
set_property -dict { PACKAGE_PIN AH3 } [get_ports { MGTRX_N[3] }]

set_property -dict { PACKAGE_PIN AF8 } [get_ports { MGTTX_P[0] }]
set_property -dict { PACKAGE_PIN AF7 } [get_ports { MGTTX_N[0] }]
set_property -dict { PACKAGE_PIN AE6 } [get_ports { MGTTX_P[1] }]
set_property -dict { PACKAGE_PIN AE5 } [get_ports { MGTTX_N[1] }]
set_property -dict { PACKAGE_PIN AD8 } [get_ports { MGTTX_P[2] }]
set_property -dict { PACKAGE_PIN AD7 } [get_ports { MGTTX_N[2] }]
set_property -dict { PACKAGE_PIN AG6 } [get_ports { MGTTX_P[3] }]
set_property -dict { PACKAGE_PIN AG5 } [get_ports { MGTTX_N[3] }]

create_clock -period 8.00 -name mgt_clock [get_ports -filter { NAME =~ "MGTCLK_N" && DIRECTION == "IN" }]
create_clock -period 8.00 -name sys_clock [get_ports -filter { NAME =~ "SYSCLK_P" && DIRECTION == "IN" }]

set clk_count_sysclk [get_cells -hier -filter {NAME =~ *clk_full_count_reg*}]
set clk_count_psclk [get_cells -hier -filter {NAME =~ *clk_full_count_psclk_reg*}]
set_max_delay -datapath_only -from $clk_count_sysclk -to $clk_count_psclk 10.000

set sync_flag_regs [get_cells -hier -filter {NAME =~ *FlagToggle_clkA_reg*}]
set sync_sync_regs [get_cells -hier -filter {NAME =~ *SyncA_clkB_reg*}]
set sync_syncB_regs [get_cells -hier -filter {NAME =~ *SyncB_clkA_reg*}]

set_max_delay -datapath_only -from $sync_flag_regs -to $sync_sync_regs 10.000
set_max_delay -datapath_only -from $sync_sync_regs -to $sync_syncB_regs 10.000

set vio_out_regs [get_cells -hier -filter {NAME=~u_aurora/u_vio/*Probe_out_reg*}]
set reset_resync_regs [get_cells -hier -filter {NAME =~ u_aurora/reset_in_resync0*}]
set_max_delay -datapath_only -from $vio_out_regs -to $reset_resync_regs 10.000
set vio_stat_regs [get_cells -hier -filter {NAME =~ u_aurora/vio_status_0_reg*}]
set aurora_regs [get_cells -hier -filter {NAME=~u_aurora/ALN[0].u_aurora/* && IS_SEQUENTIAL}]
set_max_delay -datapath_only -from $aurora_regs -to $vio_stat_regs 10.000

# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set IP_Configuration [ipgui::add_page $IPINST -name "IP Configuration"]
  set PARITY [ipgui::add_param $IPINST -name "PARITY" -parent ${IP_Configuration} -layout horizontal]
  set_property tooltip {Determines whether parity is used or not. If used whether parity is odd or even.} ${PARITY}

  ipgui::add_param $IPINST -name "C_S_AXI_ACLK_FREQ_HZ_d"
  ipgui::add_static_text $IPINST -name "ST1" -text {[10-300]MHz}
  set C_BAUDRATE [ipgui::add_param $IPINST -name "C_BAUDRATE"]
  set_property tooltip {Baud rate of the AXI UART Lite in bits per second (pointless since baud en is external)} ${C_BAUDRATE}
  ipgui::add_param $IPINST -name "C_DATA_BITS"
  ipgui::add_param $IPINST -name "C_USE_PARITY"
  ipgui::add_param $IPINST -name "C_ODD_PARITY"
  ipgui::add_param $IPINST -name "C_S_AXI_ACLK_FREQ_HZ"
  #Adding Page
  set _Clocks_ [ipgui::add_page $IPINST -name "_Clocks_"]
  ipgui::add_static_text $IPINST -name "clock_text" -parent ${_Clocks_} -text {Enter the target frequency for the input clock(s) for the IP.
These frequencies will be used during the default out-of-context synthesis flow}


}

proc update_PARAM_VALUE.PARITY { PARAM_VALUE.PARITY } {
	# Procedure called to update PARITY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PARITY { PARAM_VALUE.PARITY } {
	# Procedure called to validate PARITY
	return true
}

proc update_PARAM_VALUE.C_USE_PARITY { PARAM_VALUE.C_USE_PARITY } {
	# Procedure called to update C_USE_PARITY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_USE_PARITY { PARAM_VALUE.C_USE_PARITY } {
	# Procedure called to validate C_USE_PARITY
	return true
}

proc update_PARAM_VALUE.C_ODD_PARITY { PARAM_VALUE.C_ODD_PARITY } {
	# Procedure called to update C_ODD_PARITY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_ODD_PARITY { PARAM_VALUE.C_ODD_PARITY } {
	# Procedure called to validate C_ODD_PARITY
	return true
}

proc update_PARAM_VALUE.USE_BOARD_FLOW { PARAM_VALUE.USE_BOARD_FLOW } {
	# Procedure called to update USE_BOARD_FLOW when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.USE_BOARD_FLOW { PARAM_VALUE.USE_BOARD_FLOW } {
	# Procedure called to validate USE_BOARD_FLOW
	return true
}

proc update_PARAM_VALUE.UARTLITE_BOARD_INTERFACE { PARAM_VALUE.UARTLITE_BOARD_INTERFACE } {
	# Procedure called to update UARTLITE_BOARD_INTERFACE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.UARTLITE_BOARD_INTERFACE { PARAM_VALUE.UARTLITE_BOARD_INTERFACE } {
	# Procedure called to validate UARTLITE_BOARD_INTERFACE
	return true
}

proc update_PARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ_d { PARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ_d } {
	# Procedure called to update C_S_AXI_ACLK_FREQ_HZ_d when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ_d { PARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ_d } {
	# Procedure called to validate C_S_AXI_ACLK_FREQ_HZ_d
	return true
}

proc update_PARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ { PARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ } {
	# Procedure called to update C_S_AXI_ACLK_FREQ_HZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ { PARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ } {
	# Procedure called to validate C_S_AXI_ACLK_FREQ_HZ
	return true
}

proc update_PARAM_VALUE.C_BAUDRATE { PARAM_VALUE.C_BAUDRATE } {
	# Procedure called to update C_BAUDRATE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_BAUDRATE { PARAM_VALUE.C_BAUDRATE } {
	# Procedure called to validate C_BAUDRATE
	return true
}

proc update_PARAM_VALUE.C_DATA_BITS { PARAM_VALUE.C_DATA_BITS } {
	# Procedure called to update C_DATA_BITS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_DATA_BITS { PARAM_VALUE.C_DATA_BITS } {
	# Procedure called to validate C_DATA_BITS
	return true
}


proc update_MODELPARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ { MODELPARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ PARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ}] ${MODELPARAM_VALUE.C_S_AXI_ACLK_FREQ_HZ}
}

proc update_MODELPARAM_VALUE.C_S_AXI_ADDR_WIDTH { MODELPARAM_VALUE.C_S_AXI_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	# WARNING: There is no corresponding user parameter named "C_S_AXI_ADDR_WIDTH". Setting updated value from the model parameter.
set_property value 4 ${MODELPARAM_VALUE.C_S_AXI_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.C_S_AXI_DATA_WIDTH { MODELPARAM_VALUE.C_S_AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	# WARNING: There is no corresponding user parameter named "C_S_AXI_DATA_WIDTH". Setting updated value from the model parameter.
set_property value 32 ${MODELPARAM_VALUE.C_S_AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.C_BAUDRATE { MODELPARAM_VALUE.C_BAUDRATE PARAM_VALUE.C_BAUDRATE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_BAUDRATE}] ${MODELPARAM_VALUE.C_BAUDRATE}
}

proc update_MODELPARAM_VALUE.C_DATA_BITS { MODELPARAM_VALUE.C_DATA_BITS PARAM_VALUE.C_DATA_BITS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_DATA_BITS}] ${MODELPARAM_VALUE.C_DATA_BITS}
}

proc update_MODELPARAM_VALUE.C_USE_PARITY { MODELPARAM_VALUE.C_USE_PARITY PARAM_VALUE.C_USE_PARITY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_USE_PARITY}] ${MODELPARAM_VALUE.C_USE_PARITY}
}

proc update_MODELPARAM_VALUE.C_ODD_PARITY { MODELPARAM_VALUE.C_ODD_PARITY PARAM_VALUE.C_ODD_PARITY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_ODD_PARITY}] ${MODELPARAM_VALUE.C_ODD_PARITY}
}


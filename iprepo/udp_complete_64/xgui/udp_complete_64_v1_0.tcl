# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "ARP_CACHE_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ARP_CLOCK_PER_SEC" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ARP_REQUEST_RETRY_COUNT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ARP_REQUEST_RETRY_INTERVAL_SEC" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ARP_REQUEST_TIMEOUT_SEC" -parent ${Page_0}
  ipgui::add_param $IPINST -name "UDP_CHECKSUM_GEN_ENABLE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "UDP_CHECKSUM_HEADER_FIFO_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH" -parent ${Page_0}


}

proc update_PARAM_VALUE.ARP_CACHE_ADDR_WIDTH { PARAM_VALUE.ARP_CACHE_ADDR_WIDTH } {
	# Procedure called to update ARP_CACHE_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ARP_CACHE_ADDR_WIDTH { PARAM_VALUE.ARP_CACHE_ADDR_WIDTH } {
	# Procedure called to validate ARP_CACHE_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.ARP_CLOCK_PER_SEC { PARAM_VALUE.ARP_CLOCK_PER_SEC } {
	# Procedure called to update ARP_CLOCK_PER_SEC when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ARP_CLOCK_PER_SEC { PARAM_VALUE.ARP_CLOCK_PER_SEC } {
	# Procedure called to validate ARP_CLOCK_PER_SEC
	return true
}

proc update_PARAM_VALUE.ARP_REQUEST_RETRY_COUNT { PARAM_VALUE.ARP_REQUEST_RETRY_COUNT } {
	# Procedure called to update ARP_REQUEST_RETRY_COUNT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ARP_REQUEST_RETRY_COUNT { PARAM_VALUE.ARP_REQUEST_RETRY_COUNT } {
	# Procedure called to validate ARP_REQUEST_RETRY_COUNT
	return true
}

proc update_PARAM_VALUE.ARP_REQUEST_RETRY_INTERVAL_SEC { PARAM_VALUE.ARP_REQUEST_RETRY_INTERVAL_SEC } {
	# Procedure called to update ARP_REQUEST_RETRY_INTERVAL_SEC when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ARP_REQUEST_RETRY_INTERVAL_SEC { PARAM_VALUE.ARP_REQUEST_RETRY_INTERVAL_SEC } {
	# Procedure called to validate ARP_REQUEST_RETRY_INTERVAL_SEC
	return true
}

proc update_PARAM_VALUE.ARP_REQUEST_TIMEOUT_SEC { PARAM_VALUE.ARP_REQUEST_TIMEOUT_SEC } {
	# Procedure called to update ARP_REQUEST_TIMEOUT_SEC when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ARP_REQUEST_TIMEOUT_SEC { PARAM_VALUE.ARP_REQUEST_TIMEOUT_SEC } {
	# Procedure called to validate ARP_REQUEST_TIMEOUT_SEC
	return true
}

proc update_PARAM_VALUE.UDP_CHECKSUM_GEN_ENABLE { PARAM_VALUE.UDP_CHECKSUM_GEN_ENABLE } {
	# Procedure called to update UDP_CHECKSUM_GEN_ENABLE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.UDP_CHECKSUM_GEN_ENABLE { PARAM_VALUE.UDP_CHECKSUM_GEN_ENABLE } {
	# Procedure called to validate UDP_CHECKSUM_GEN_ENABLE
	return true
}

proc update_PARAM_VALUE.UDP_CHECKSUM_HEADER_FIFO_DEPTH { PARAM_VALUE.UDP_CHECKSUM_HEADER_FIFO_DEPTH } {
	# Procedure called to update UDP_CHECKSUM_HEADER_FIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.UDP_CHECKSUM_HEADER_FIFO_DEPTH { PARAM_VALUE.UDP_CHECKSUM_HEADER_FIFO_DEPTH } {
	# Procedure called to validate UDP_CHECKSUM_HEADER_FIFO_DEPTH
	return true
}

proc update_PARAM_VALUE.UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH { PARAM_VALUE.UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH } {
	# Procedure called to update UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH { PARAM_VALUE.UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH } {
	# Procedure called to validate UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH
	return true
}


proc update_MODELPARAM_VALUE.ARP_CACHE_ADDR_WIDTH { MODELPARAM_VALUE.ARP_CACHE_ADDR_WIDTH PARAM_VALUE.ARP_CACHE_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ARP_CACHE_ADDR_WIDTH}] ${MODELPARAM_VALUE.ARP_CACHE_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.ARP_REQUEST_RETRY_COUNT { MODELPARAM_VALUE.ARP_REQUEST_RETRY_COUNT PARAM_VALUE.ARP_REQUEST_RETRY_COUNT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ARP_REQUEST_RETRY_COUNT}] ${MODELPARAM_VALUE.ARP_REQUEST_RETRY_COUNT}
}

proc update_MODELPARAM_VALUE.ARP_CLOCK_PER_SEC { MODELPARAM_VALUE.ARP_CLOCK_PER_SEC PARAM_VALUE.ARP_CLOCK_PER_SEC } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ARP_CLOCK_PER_SEC}] ${MODELPARAM_VALUE.ARP_CLOCK_PER_SEC}
}

proc update_MODELPARAM_VALUE.ARP_REQUEST_RETRY_INTERVAL_SEC { MODELPARAM_VALUE.ARP_REQUEST_RETRY_INTERVAL_SEC PARAM_VALUE.ARP_REQUEST_RETRY_INTERVAL_SEC } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ARP_REQUEST_RETRY_INTERVAL_SEC}] ${MODELPARAM_VALUE.ARP_REQUEST_RETRY_INTERVAL_SEC}
}

proc update_MODELPARAM_VALUE.ARP_REQUEST_TIMEOUT_SEC { MODELPARAM_VALUE.ARP_REQUEST_TIMEOUT_SEC PARAM_VALUE.ARP_REQUEST_TIMEOUT_SEC } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ARP_REQUEST_TIMEOUT_SEC}] ${MODELPARAM_VALUE.ARP_REQUEST_TIMEOUT_SEC}
}

proc update_MODELPARAM_VALUE.UDP_CHECKSUM_GEN_ENABLE { MODELPARAM_VALUE.UDP_CHECKSUM_GEN_ENABLE PARAM_VALUE.UDP_CHECKSUM_GEN_ENABLE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.UDP_CHECKSUM_GEN_ENABLE}] ${MODELPARAM_VALUE.UDP_CHECKSUM_GEN_ENABLE}
}

proc update_MODELPARAM_VALUE.UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH { MODELPARAM_VALUE.UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH PARAM_VALUE.UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH}] ${MODELPARAM_VALUE.UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH}
}

proc update_MODELPARAM_VALUE.UDP_CHECKSUM_HEADER_FIFO_DEPTH { MODELPARAM_VALUE.UDP_CHECKSUM_HEADER_FIFO_DEPTH PARAM_VALUE.UDP_CHECKSUM_HEADER_FIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.UDP_CHECKSUM_HEADER_FIFO_DEPTH}] ${MODELPARAM_VALUE.UDP_CHECKSUM_HEADER_FIFO_DEPTH}
}


# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "AXIS_DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "AXIS_KEEP_ENABLE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "AXIS_KEEP_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CTRL_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ENABLE_DIC" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ENABLE_PADDING" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MIN_FRAME_LENGTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PTP_PERIOD_FNS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PTP_PERIOD_NS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PTP_TAG_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PTP_TS_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PTP_USE_SAMPLE_CLOCK" -parent ${Page_0}
  ipgui::add_param $IPINST -name "RX_DROP_BAD_FRAME" -parent ${Page_0}
  ipgui::add_param $IPINST -name "RX_DROP_OVERSIZE_FRAME" -parent ${Page_0}
  ipgui::add_param $IPINST -name "RX_DROP_WHEN_FULL" -parent ${Page_0}
  ipgui::add_param $IPINST -name "RX_FIFO_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "RX_FIFO_RAM_PIPELINE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "RX_FRAME_FIFO" -parent ${Page_0}
  ipgui::add_param $IPINST -name "RX_PTP_TS_ENABLE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "RX_USER_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TX_DROP_BAD_FRAME" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TX_DROP_OVERSIZE_FRAME" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TX_DROP_WHEN_FULL" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TX_FIFO_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TX_FIFO_RAM_PIPELINE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TX_FRAME_FIFO" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TX_PTP_TAG_ENABLE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TX_PTP_TS_ENABLE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TX_PTP_TS_FIFO_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TX_USER_WIDTH" -parent ${Page_0}


}

proc update_PARAM_VALUE.AXIS_DATA_WIDTH { PARAM_VALUE.AXIS_DATA_WIDTH } {
	# Procedure called to update AXIS_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.AXIS_DATA_WIDTH { PARAM_VALUE.AXIS_DATA_WIDTH } {
	# Procedure called to validate AXIS_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.AXIS_KEEP_ENABLE { PARAM_VALUE.AXIS_KEEP_ENABLE } {
	# Procedure called to update AXIS_KEEP_ENABLE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.AXIS_KEEP_ENABLE { PARAM_VALUE.AXIS_KEEP_ENABLE } {
	# Procedure called to validate AXIS_KEEP_ENABLE
	return true
}

proc update_PARAM_VALUE.AXIS_KEEP_WIDTH { PARAM_VALUE.AXIS_KEEP_WIDTH } {
	# Procedure called to update AXIS_KEEP_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.AXIS_KEEP_WIDTH { PARAM_VALUE.AXIS_KEEP_WIDTH } {
	# Procedure called to validate AXIS_KEEP_WIDTH
	return true
}

proc update_PARAM_VALUE.CTRL_WIDTH { PARAM_VALUE.CTRL_WIDTH } {
	# Procedure called to update CTRL_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CTRL_WIDTH { PARAM_VALUE.CTRL_WIDTH } {
	# Procedure called to validate CTRL_WIDTH
	return true
}

proc update_PARAM_VALUE.DATA_WIDTH { PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to update DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DATA_WIDTH { PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to validate DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.ENABLE_DIC { PARAM_VALUE.ENABLE_DIC } {
	# Procedure called to update ENABLE_DIC when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ENABLE_DIC { PARAM_VALUE.ENABLE_DIC } {
	# Procedure called to validate ENABLE_DIC
	return true
}

proc update_PARAM_VALUE.ENABLE_PADDING { PARAM_VALUE.ENABLE_PADDING } {
	# Procedure called to update ENABLE_PADDING when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ENABLE_PADDING { PARAM_VALUE.ENABLE_PADDING } {
	# Procedure called to validate ENABLE_PADDING
	return true
}

proc update_PARAM_VALUE.MIN_FRAME_LENGTH { PARAM_VALUE.MIN_FRAME_LENGTH } {
	# Procedure called to update MIN_FRAME_LENGTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MIN_FRAME_LENGTH { PARAM_VALUE.MIN_FRAME_LENGTH } {
	# Procedure called to validate MIN_FRAME_LENGTH
	return true
}

proc update_PARAM_VALUE.PTP_PERIOD_FNS { PARAM_VALUE.PTP_PERIOD_FNS } {
	# Procedure called to update PTP_PERIOD_FNS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PTP_PERIOD_FNS { PARAM_VALUE.PTP_PERIOD_FNS } {
	# Procedure called to validate PTP_PERIOD_FNS
	return true
}

proc update_PARAM_VALUE.PTP_PERIOD_NS { PARAM_VALUE.PTP_PERIOD_NS } {
	# Procedure called to update PTP_PERIOD_NS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PTP_PERIOD_NS { PARAM_VALUE.PTP_PERIOD_NS } {
	# Procedure called to validate PTP_PERIOD_NS
	return true
}

proc update_PARAM_VALUE.PTP_TAG_WIDTH { PARAM_VALUE.PTP_TAG_WIDTH } {
	# Procedure called to update PTP_TAG_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PTP_TAG_WIDTH { PARAM_VALUE.PTP_TAG_WIDTH } {
	# Procedure called to validate PTP_TAG_WIDTH
	return true
}

proc update_PARAM_VALUE.PTP_TS_WIDTH { PARAM_VALUE.PTP_TS_WIDTH } {
	# Procedure called to update PTP_TS_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PTP_TS_WIDTH { PARAM_VALUE.PTP_TS_WIDTH } {
	# Procedure called to validate PTP_TS_WIDTH
	return true
}

proc update_PARAM_VALUE.PTP_USE_SAMPLE_CLOCK { PARAM_VALUE.PTP_USE_SAMPLE_CLOCK } {
	# Procedure called to update PTP_USE_SAMPLE_CLOCK when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PTP_USE_SAMPLE_CLOCK { PARAM_VALUE.PTP_USE_SAMPLE_CLOCK } {
	# Procedure called to validate PTP_USE_SAMPLE_CLOCK
	return true
}

proc update_PARAM_VALUE.RX_DROP_BAD_FRAME { PARAM_VALUE.RX_DROP_BAD_FRAME } {
	# Procedure called to update RX_DROP_BAD_FRAME when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.RX_DROP_BAD_FRAME { PARAM_VALUE.RX_DROP_BAD_FRAME } {
	# Procedure called to validate RX_DROP_BAD_FRAME
	return true
}

proc update_PARAM_VALUE.RX_DROP_OVERSIZE_FRAME { PARAM_VALUE.RX_DROP_OVERSIZE_FRAME } {
	# Procedure called to update RX_DROP_OVERSIZE_FRAME when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.RX_DROP_OVERSIZE_FRAME { PARAM_VALUE.RX_DROP_OVERSIZE_FRAME } {
	# Procedure called to validate RX_DROP_OVERSIZE_FRAME
	return true
}

proc update_PARAM_VALUE.RX_DROP_WHEN_FULL { PARAM_VALUE.RX_DROP_WHEN_FULL } {
	# Procedure called to update RX_DROP_WHEN_FULL when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.RX_DROP_WHEN_FULL { PARAM_VALUE.RX_DROP_WHEN_FULL } {
	# Procedure called to validate RX_DROP_WHEN_FULL
	return true
}

proc update_PARAM_VALUE.RX_FIFO_DEPTH { PARAM_VALUE.RX_FIFO_DEPTH } {
	# Procedure called to update RX_FIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.RX_FIFO_DEPTH { PARAM_VALUE.RX_FIFO_DEPTH } {
	# Procedure called to validate RX_FIFO_DEPTH
	return true
}

proc update_PARAM_VALUE.RX_FIFO_RAM_PIPELINE { PARAM_VALUE.RX_FIFO_RAM_PIPELINE } {
	# Procedure called to update RX_FIFO_RAM_PIPELINE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.RX_FIFO_RAM_PIPELINE { PARAM_VALUE.RX_FIFO_RAM_PIPELINE } {
	# Procedure called to validate RX_FIFO_RAM_PIPELINE
	return true
}

proc update_PARAM_VALUE.RX_FRAME_FIFO { PARAM_VALUE.RX_FRAME_FIFO } {
	# Procedure called to update RX_FRAME_FIFO when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.RX_FRAME_FIFO { PARAM_VALUE.RX_FRAME_FIFO } {
	# Procedure called to validate RX_FRAME_FIFO
	return true
}

proc update_PARAM_VALUE.RX_PTP_TS_ENABLE { PARAM_VALUE.RX_PTP_TS_ENABLE } {
	# Procedure called to update RX_PTP_TS_ENABLE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.RX_PTP_TS_ENABLE { PARAM_VALUE.RX_PTP_TS_ENABLE } {
	# Procedure called to validate RX_PTP_TS_ENABLE
	return true
}

proc update_PARAM_VALUE.RX_USER_WIDTH { PARAM_VALUE.RX_USER_WIDTH } {
	# Procedure called to update RX_USER_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.RX_USER_WIDTH { PARAM_VALUE.RX_USER_WIDTH } {
	# Procedure called to validate RX_USER_WIDTH
	return true
}

proc update_PARAM_VALUE.TX_DROP_BAD_FRAME { PARAM_VALUE.TX_DROP_BAD_FRAME } {
	# Procedure called to update TX_DROP_BAD_FRAME when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TX_DROP_BAD_FRAME { PARAM_VALUE.TX_DROP_BAD_FRAME } {
	# Procedure called to validate TX_DROP_BAD_FRAME
	return true
}

proc update_PARAM_VALUE.TX_DROP_OVERSIZE_FRAME { PARAM_VALUE.TX_DROP_OVERSIZE_FRAME } {
	# Procedure called to update TX_DROP_OVERSIZE_FRAME when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TX_DROP_OVERSIZE_FRAME { PARAM_VALUE.TX_DROP_OVERSIZE_FRAME } {
	# Procedure called to validate TX_DROP_OVERSIZE_FRAME
	return true
}

proc update_PARAM_VALUE.TX_DROP_WHEN_FULL { PARAM_VALUE.TX_DROP_WHEN_FULL } {
	# Procedure called to update TX_DROP_WHEN_FULL when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TX_DROP_WHEN_FULL { PARAM_VALUE.TX_DROP_WHEN_FULL } {
	# Procedure called to validate TX_DROP_WHEN_FULL
	return true
}

proc update_PARAM_VALUE.TX_FIFO_DEPTH { PARAM_VALUE.TX_FIFO_DEPTH } {
	# Procedure called to update TX_FIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TX_FIFO_DEPTH { PARAM_VALUE.TX_FIFO_DEPTH } {
	# Procedure called to validate TX_FIFO_DEPTH
	return true
}

proc update_PARAM_VALUE.TX_FIFO_RAM_PIPELINE { PARAM_VALUE.TX_FIFO_RAM_PIPELINE } {
	# Procedure called to update TX_FIFO_RAM_PIPELINE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TX_FIFO_RAM_PIPELINE { PARAM_VALUE.TX_FIFO_RAM_PIPELINE } {
	# Procedure called to validate TX_FIFO_RAM_PIPELINE
	return true
}

proc update_PARAM_VALUE.TX_FRAME_FIFO { PARAM_VALUE.TX_FRAME_FIFO } {
	# Procedure called to update TX_FRAME_FIFO when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TX_FRAME_FIFO { PARAM_VALUE.TX_FRAME_FIFO } {
	# Procedure called to validate TX_FRAME_FIFO
	return true
}

proc update_PARAM_VALUE.TX_PTP_TAG_ENABLE { PARAM_VALUE.TX_PTP_TAG_ENABLE } {
	# Procedure called to update TX_PTP_TAG_ENABLE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TX_PTP_TAG_ENABLE { PARAM_VALUE.TX_PTP_TAG_ENABLE } {
	# Procedure called to validate TX_PTP_TAG_ENABLE
	return true
}

proc update_PARAM_VALUE.TX_PTP_TS_ENABLE { PARAM_VALUE.TX_PTP_TS_ENABLE } {
	# Procedure called to update TX_PTP_TS_ENABLE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TX_PTP_TS_ENABLE { PARAM_VALUE.TX_PTP_TS_ENABLE } {
	# Procedure called to validate TX_PTP_TS_ENABLE
	return true
}

proc update_PARAM_VALUE.TX_PTP_TS_FIFO_DEPTH { PARAM_VALUE.TX_PTP_TS_FIFO_DEPTH } {
	# Procedure called to update TX_PTP_TS_FIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TX_PTP_TS_FIFO_DEPTH { PARAM_VALUE.TX_PTP_TS_FIFO_DEPTH } {
	# Procedure called to validate TX_PTP_TS_FIFO_DEPTH
	return true
}

proc update_PARAM_VALUE.TX_USER_WIDTH { PARAM_VALUE.TX_USER_WIDTH } {
	# Procedure called to update TX_USER_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TX_USER_WIDTH { PARAM_VALUE.TX_USER_WIDTH } {
	# Procedure called to validate TX_USER_WIDTH
	return true
}


proc update_MODELPARAM_VALUE.DATA_WIDTH { MODELPARAM_VALUE.DATA_WIDTH PARAM_VALUE.DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DATA_WIDTH}] ${MODELPARAM_VALUE.DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.CTRL_WIDTH { MODELPARAM_VALUE.CTRL_WIDTH PARAM_VALUE.CTRL_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CTRL_WIDTH}] ${MODELPARAM_VALUE.CTRL_WIDTH}
}

proc update_MODELPARAM_VALUE.AXIS_DATA_WIDTH { MODELPARAM_VALUE.AXIS_DATA_WIDTH PARAM_VALUE.AXIS_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.AXIS_DATA_WIDTH}] ${MODELPARAM_VALUE.AXIS_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.AXIS_KEEP_ENABLE { MODELPARAM_VALUE.AXIS_KEEP_ENABLE PARAM_VALUE.AXIS_KEEP_ENABLE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.AXIS_KEEP_ENABLE}] ${MODELPARAM_VALUE.AXIS_KEEP_ENABLE}
}

proc update_MODELPARAM_VALUE.AXIS_KEEP_WIDTH { MODELPARAM_VALUE.AXIS_KEEP_WIDTH PARAM_VALUE.AXIS_KEEP_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.AXIS_KEEP_WIDTH}] ${MODELPARAM_VALUE.AXIS_KEEP_WIDTH}
}

proc update_MODELPARAM_VALUE.ENABLE_PADDING { MODELPARAM_VALUE.ENABLE_PADDING PARAM_VALUE.ENABLE_PADDING } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ENABLE_PADDING}] ${MODELPARAM_VALUE.ENABLE_PADDING}
}

proc update_MODELPARAM_VALUE.ENABLE_DIC { MODELPARAM_VALUE.ENABLE_DIC PARAM_VALUE.ENABLE_DIC } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ENABLE_DIC}] ${MODELPARAM_VALUE.ENABLE_DIC}
}

proc update_MODELPARAM_VALUE.MIN_FRAME_LENGTH { MODELPARAM_VALUE.MIN_FRAME_LENGTH PARAM_VALUE.MIN_FRAME_LENGTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MIN_FRAME_LENGTH}] ${MODELPARAM_VALUE.MIN_FRAME_LENGTH}
}

proc update_MODELPARAM_VALUE.TX_FIFO_DEPTH { MODELPARAM_VALUE.TX_FIFO_DEPTH PARAM_VALUE.TX_FIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TX_FIFO_DEPTH}] ${MODELPARAM_VALUE.TX_FIFO_DEPTH}
}

proc update_MODELPARAM_VALUE.TX_FIFO_RAM_PIPELINE { MODELPARAM_VALUE.TX_FIFO_RAM_PIPELINE PARAM_VALUE.TX_FIFO_RAM_PIPELINE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TX_FIFO_RAM_PIPELINE}] ${MODELPARAM_VALUE.TX_FIFO_RAM_PIPELINE}
}

proc update_MODELPARAM_VALUE.TX_FRAME_FIFO { MODELPARAM_VALUE.TX_FRAME_FIFO PARAM_VALUE.TX_FRAME_FIFO } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TX_FRAME_FIFO}] ${MODELPARAM_VALUE.TX_FRAME_FIFO}
}

proc update_MODELPARAM_VALUE.TX_DROP_OVERSIZE_FRAME { MODELPARAM_VALUE.TX_DROP_OVERSIZE_FRAME PARAM_VALUE.TX_DROP_OVERSIZE_FRAME } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TX_DROP_OVERSIZE_FRAME}] ${MODELPARAM_VALUE.TX_DROP_OVERSIZE_FRAME}
}

proc update_MODELPARAM_VALUE.TX_DROP_BAD_FRAME { MODELPARAM_VALUE.TX_DROP_BAD_FRAME PARAM_VALUE.TX_DROP_BAD_FRAME } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TX_DROP_BAD_FRAME}] ${MODELPARAM_VALUE.TX_DROP_BAD_FRAME}
}

proc update_MODELPARAM_VALUE.TX_DROP_WHEN_FULL { MODELPARAM_VALUE.TX_DROP_WHEN_FULL PARAM_VALUE.TX_DROP_WHEN_FULL } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TX_DROP_WHEN_FULL}] ${MODELPARAM_VALUE.TX_DROP_WHEN_FULL}
}

proc update_MODELPARAM_VALUE.RX_FIFO_DEPTH { MODELPARAM_VALUE.RX_FIFO_DEPTH PARAM_VALUE.RX_FIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.RX_FIFO_DEPTH}] ${MODELPARAM_VALUE.RX_FIFO_DEPTH}
}

proc update_MODELPARAM_VALUE.RX_FIFO_RAM_PIPELINE { MODELPARAM_VALUE.RX_FIFO_RAM_PIPELINE PARAM_VALUE.RX_FIFO_RAM_PIPELINE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.RX_FIFO_RAM_PIPELINE}] ${MODELPARAM_VALUE.RX_FIFO_RAM_PIPELINE}
}

proc update_MODELPARAM_VALUE.RX_FRAME_FIFO { MODELPARAM_VALUE.RX_FRAME_FIFO PARAM_VALUE.RX_FRAME_FIFO } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.RX_FRAME_FIFO}] ${MODELPARAM_VALUE.RX_FRAME_FIFO}
}

proc update_MODELPARAM_VALUE.RX_DROP_OVERSIZE_FRAME { MODELPARAM_VALUE.RX_DROP_OVERSIZE_FRAME PARAM_VALUE.RX_DROP_OVERSIZE_FRAME } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.RX_DROP_OVERSIZE_FRAME}] ${MODELPARAM_VALUE.RX_DROP_OVERSIZE_FRAME}
}

proc update_MODELPARAM_VALUE.RX_DROP_BAD_FRAME { MODELPARAM_VALUE.RX_DROP_BAD_FRAME PARAM_VALUE.RX_DROP_BAD_FRAME } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.RX_DROP_BAD_FRAME}] ${MODELPARAM_VALUE.RX_DROP_BAD_FRAME}
}

proc update_MODELPARAM_VALUE.RX_DROP_WHEN_FULL { MODELPARAM_VALUE.RX_DROP_WHEN_FULL PARAM_VALUE.RX_DROP_WHEN_FULL } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.RX_DROP_WHEN_FULL}] ${MODELPARAM_VALUE.RX_DROP_WHEN_FULL}
}

proc update_MODELPARAM_VALUE.PTP_PERIOD_NS { MODELPARAM_VALUE.PTP_PERIOD_NS PARAM_VALUE.PTP_PERIOD_NS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PTP_PERIOD_NS}] ${MODELPARAM_VALUE.PTP_PERIOD_NS}
}

proc update_MODELPARAM_VALUE.PTP_PERIOD_FNS { MODELPARAM_VALUE.PTP_PERIOD_FNS PARAM_VALUE.PTP_PERIOD_FNS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PTP_PERIOD_FNS}] ${MODELPARAM_VALUE.PTP_PERIOD_FNS}
}

proc update_MODELPARAM_VALUE.PTP_USE_SAMPLE_CLOCK { MODELPARAM_VALUE.PTP_USE_SAMPLE_CLOCK PARAM_VALUE.PTP_USE_SAMPLE_CLOCK } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PTP_USE_SAMPLE_CLOCK}] ${MODELPARAM_VALUE.PTP_USE_SAMPLE_CLOCK}
}

proc update_MODELPARAM_VALUE.TX_PTP_TS_ENABLE { MODELPARAM_VALUE.TX_PTP_TS_ENABLE PARAM_VALUE.TX_PTP_TS_ENABLE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TX_PTP_TS_ENABLE}] ${MODELPARAM_VALUE.TX_PTP_TS_ENABLE}
}

proc update_MODELPARAM_VALUE.RX_PTP_TS_ENABLE { MODELPARAM_VALUE.RX_PTP_TS_ENABLE PARAM_VALUE.RX_PTP_TS_ENABLE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.RX_PTP_TS_ENABLE}] ${MODELPARAM_VALUE.RX_PTP_TS_ENABLE}
}

proc update_MODELPARAM_VALUE.TX_PTP_TS_FIFO_DEPTH { MODELPARAM_VALUE.TX_PTP_TS_FIFO_DEPTH PARAM_VALUE.TX_PTP_TS_FIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TX_PTP_TS_FIFO_DEPTH}] ${MODELPARAM_VALUE.TX_PTP_TS_FIFO_DEPTH}
}

proc update_MODELPARAM_VALUE.PTP_TS_WIDTH { MODELPARAM_VALUE.PTP_TS_WIDTH PARAM_VALUE.PTP_TS_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PTP_TS_WIDTH}] ${MODELPARAM_VALUE.PTP_TS_WIDTH}
}

proc update_MODELPARAM_VALUE.TX_PTP_TAG_ENABLE { MODELPARAM_VALUE.TX_PTP_TAG_ENABLE PARAM_VALUE.TX_PTP_TAG_ENABLE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TX_PTP_TAG_ENABLE}] ${MODELPARAM_VALUE.TX_PTP_TAG_ENABLE}
}

proc update_MODELPARAM_VALUE.PTP_TAG_WIDTH { MODELPARAM_VALUE.PTP_TAG_WIDTH PARAM_VALUE.PTP_TAG_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PTP_TAG_WIDTH}] ${MODELPARAM_VALUE.PTP_TAG_WIDTH}
}

proc update_MODELPARAM_VALUE.TX_USER_WIDTH { MODELPARAM_VALUE.TX_USER_WIDTH PARAM_VALUE.TX_USER_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TX_USER_WIDTH}] ${MODELPARAM_VALUE.TX_USER_WIDTH}
}

proc update_MODELPARAM_VALUE.RX_USER_WIDTH { MODELPARAM_VALUE.RX_USER_WIDTH PARAM_VALUE.RX_USER_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.RX_USER_WIDTH}] ${MODELPARAM_VALUE.RX_USER_WIDTH}
}


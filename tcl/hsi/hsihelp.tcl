#######################################################################
# Copyright (c) 2015-2018 Xilinx, Inc.  All rights reserved.
#
# This   document  contains  proprietary information  which   is
# protected by  copyright. All rights  are reserved. No  part of
# this  document may be photocopied, reproduced or translated to
# another  program  language  without  prior written  consent of
# XILINX Inc., San Jose, CA. 95124
#
# Xilinx, Inc.
# XILINX IS PROVIDING THIS DESIGN, CODE, OR INFORMATION "AS IS" AS A
# COURTESY TO YOU.  BY PROVIDING THIS DESIGN, CODE, OR INFORMATION AS
# ONE POSSIBLE   IMPLEMENTATION OF THIS FEATURE, APPLICATION OR
# STANDARD, XILINX IS MAKING NO REPRESENTATION THAT THIS IMPLEMENTATION
# IS FREE FROM ANY CLAIMS OF INFRINGEMENT, AND YOU ARE RESPONSIBLE
# FOR OBTAINING ANY RIGHTS YOU MAY REQUIRE FOR YOUR IMPLEMENTATION.
# XILINX EXPRESSLY DISCLAIMS ANY WARRANTY WHATSOEVER WITH RESPECT TO
# THE ADEQUACY OF THE IMPLEMENTATION, INCLUDING BUT NOT LIMITED TO
# ANY WARRANTIES OR REPRESENTATIONS THAT THIS IMPLEMENTATION IS FREE
# FROM CLAIMS OF INFRINGEMENT, IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS FOR A PARTICULAR PURPOSE.
#
#######################################################################

namespace eval ::hsi::help {
    variable version 0.1

    ::xsdb::setcmdmeta {hsi create_dt_node} categories {hsi}
    ::xsdb::setcmdmeta {hsi create_dt_node} brief {Create a DT node.}
    ::xsdb::setcmdmeta {hsi create_dt_node} description [hsi::create_dt_node -help]

    ::xsdb::setcmdmeta {hsi create_dt_tree} categories {hsi}
    ::xsdb::setcmdmeta {hsi create_dt_tree} brief {Create a DT tree.}
    ::xsdb::setcmdmeta {hsi create_dt_tree} description [hsi::create_dt_tree -help]

    ::xsdb::setcmdmeta {hsi current_dt_tree} categories {hsi}
    ::xsdb::setcmdmeta {hsi current_dt_tree} brief {Set or get current tree.}
    ::xsdb::setcmdmeta {hsi current_dt_tree} description [hsi::current_dt_tree -help]

    ::xsdb::setcmdmeta {hsi get_dt_nodes} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_dt_nodes} brief {Get a list of DT node objects.}
    ::xsdb::setcmdmeta {hsi get_dt_nodes} description [hsi::get_dt_nodes -help]

    ::xsdb::setcmdmeta {hsi get_dt_trees} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_dt_trees} brief {Get a list of dts trees created.}
    ::xsdb::setcmdmeta {hsi get_dt_trees} description [hsi::get_dt_trees -help]

    ::xsdb::setcmdmeta {hsi close_hw_design} categories {hsi}
    ::xsdb::setcmdmeta {hsi close_hw_design} brief {Close a HW design.}
    ::xsdb::setcmdmeta {hsi close_hw_design} description [hsi::close_hw_design -help]

    ::xsdb::setcmdmeta {hsi current_hw_design} categories {hsi}
    ::xsdb::setcmdmeta {hsi current_hw_design} brief {Set or get current hardware design.}
    ::xsdb::setcmdmeta {hsi current_hw_design} description [hsi::current_hw_design -help]

    ::xsdb::setcmdmeta {hsi get_cells} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_cells} brief {Get a list of cells.}
    ::xsdb::setcmdmeta {hsi get_cells} description [hsi::get_cells -help]

    ::xsdb::setcmdmeta {hsi get_hw_designs} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_hw_designs} brief {Get a list of hardware designs opened.}
    ::xsdb::setcmdmeta {hsi get_hw_designs} description [hsi::get_hw_designs -help]

    ::xsdb::setcmdmeta {hsi get_hw_files} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_hw_files} brief {Get a list of hardware design supporting files.}
    ::xsdb::setcmdmeta {hsi get_hw_files} description [hsi::get_hw_files -help]

    ::xsdb::setcmdmeta {hsi get_intf_nets} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_intf_nets} brief {Get a list of interface nets.}
    ::xsdb::setcmdmeta {hsi get_intf_nets} description [hsi::get_intf_nets -help]

    ::xsdb::setcmdmeta {hsi get_intf_pins} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_intf_pins} brief {Get a list of interface pins.}
    ::xsdb::setcmdmeta {hsi get_intf_pins} description [hsi::get_intf_pins -help]

    ::xsdb::setcmdmeta {hsi get_intf_ports} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_intf_ports} brief {Get a list of interface ports.}
    ::xsdb::setcmdmeta {hsi get_intf_ports} description [hsi::get_intf_ports -help]

    ::xsdb::setcmdmeta {hsi get_mem_ranges} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_mem_ranges} brief {Get a list of memory ranges.}
    ::xsdb::setcmdmeta {hsi get_mem_ranges} description [hsi::get_mem_ranges -help]

    ::xsdb::setcmdmeta {hsi get_nets} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_nets} brief {Get a list of nets.}
    ::xsdb::setcmdmeta {hsi get_nets} description [hsi::get_nets -help]

    ::xsdb::setcmdmeta {hsi get_pins} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_pins} brief {Get a list of pins.}
    ::xsdb::setcmdmeta {hsi get_pins} description [hsi::get_pins -help]

    ::xsdb::setcmdmeta {hsi get_ports} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_ports} brief {Get a list of external ports.}
    ::xsdb::setcmdmeta {hsi get_ports} description [hsi::get_ports -help]

    ::xsdb::setcmdmeta {hsi open_hw_design} categories {hsi}
    ::xsdb::setcmdmeta {hsi open_hw_design} brief {Open a hardware design from disk file.}
    ::xsdb::setcmdmeta {hsi open_hw_design} description [hsi::open_hw_design -help]

    ::xsdb::setcmdmeta {hsi write_ps_configuration} categories {hsi}
    ::xsdb::setcmdmeta {hsi write_ps_configuration} brief {Save PS configurations to a file.}
    ::xsdb::setcmdmeta {hsi write_ps_configuration} description [hsi::write_ps_configuration -help]

    ::xsdb::setcmdmeta {hsi add_library} categories {hsi}
    ::xsdb::setcmdmeta {hsi add_library} brief {Add software library to software design.}
    ::xsdb::setcmdmeta {hsi add_library} description [hsi::add_library -help]

    ::xsdb::setcmdmeta {hsi close_sw_design} categories {hsi}
    ::xsdb::setcmdmeta {hsi close_sw_design} brief {Close a software design.}
    ::xsdb::setcmdmeta {hsi close_sw_design} description [hsi::close_sw_design -help]

    ::xsdb::setcmdmeta {hsi create_comp_param} categories {hsi}
    ::xsdb::setcmdmeta {hsi create_comp_param} brief {Add parameter.}
    ::xsdb::setcmdmeta {hsi create_comp_param} description [hsi::create_comp_param -help]

    ::xsdb::setcmdmeta {hsi create_node} categories {hsi}
    ::xsdb::setcmdmeta {hsi create_node} brief {Add node.}
    ::xsdb::setcmdmeta {hsi create_node} description [hsi::create_node -help]

    ::xsdb::setcmdmeta {hsi create_sw_design} categories {hsi}
    ::xsdb::setcmdmeta {hsi create_sw_design} brief {Create a software design.}
    ::xsdb::setcmdmeta {hsi create_sw_design} description [hsi::create_sw_design -help]

    ::xsdb::setcmdmeta {hsi current_sw_design} categories {hsi}
    ::xsdb::setcmdmeta {hsi current_sw_design} brief {Get or set current software design.}
    ::xsdb::setcmdmeta {hsi current_sw_design} description [hsi::current_sw_design -help]

    ::xsdb::setcmdmeta {hsi delete_objs} categories {hsi}
    ::xsdb::setcmdmeta {hsi delete_objs} brief {Delete specified objects.}
    ::xsdb::setcmdmeta {hsi delete_objs} description [hsi::delete_objs -help]

    ::xsdb::setcmdmeta {hsi generate_app} categories {hsi}
    ::xsdb::setcmdmeta {hsi generate_app} brief {Generate template application.}
    ::xsdb::setcmdmeta {hsi generate_app} description [hsi::generate_app -help]

    ::xsdb::setcmdmeta {hsi generate_bsp} categories {hsi}
    ::xsdb::setcmdmeta {hsi generate_bsp} brief {Generate board support package.}
    ::xsdb::setcmdmeta {hsi generate_bsp} description [hsi::generate_bsp -help]

    ::xsdb::setcmdmeta {hsi generate_target} categories {hsi}
    ::xsdb::setcmdmeta {hsi generate_target} brief {Generate target.}
    ::xsdb::setcmdmeta {hsi generate_target} description [hsi::generate_target -help]

    ::xsdb::setcmdmeta {hsi get_arrays} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_arrays} brief {Get a list of software arrays.}
    ::xsdb::setcmdmeta {hsi get_arrays} description [hsi::get_arrays -help]

    ::xsdb::setcmdmeta {hsi get_comp_params} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_comp_params} brief {Get a list of parameters.}
    ::xsdb::setcmdmeta {hsi get_comp_params} description [hsi::get_comp_params -help]

    ::xsdb::setcmdmeta {hsi get_drivers} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_drivers} brief {Get a list of software driver instances.}
    ::xsdb::setcmdmeta {hsi get_drivers} description [hsi::get_drivers -help]

    ::xsdb::setcmdmeta {hsi get_fields} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_fields} brief {Get a list of fields of a register.}
    ::xsdb::setcmdmeta {hsi get_fields} description [hsi::get_fields -help]

    ::xsdb::setcmdmeta {hsi get_libs} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_libs} brief {Get a list of software libraries.}
    ::xsdb::setcmdmeta {hsi get_libs} description [hsi::get_libs -help]

    ::xsdb::setcmdmeta {hsi get_nodes} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_nodes} brief {Get a list of child nodes.}
    ::xsdb::setcmdmeta {hsi get_nodes} description [hsi::get_nodes -help]

    ::xsdb::setcmdmeta {hsi get_os} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_os} brief {Get OS in the software design.}
    ::xsdb::setcmdmeta {hsi get_os} description [hsi::get_os -help]

    ::xsdb::setcmdmeta {hsi get_registers} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_registers} brief {Get a list of software registers.}
    ::xsdb::setcmdmeta {hsi get_registers} description [hsi::get_registers -help]

    ::xsdb::setcmdmeta {hsi get_sw_cores} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_sw_cores} brief {Get a list of software cores like driver, library, OS.}
    ::xsdb::setcmdmeta {hsi get_sw_cores} description [hsi::get_sw_cores -help]

    ::xsdb::setcmdmeta {hsi get_sw_designs} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_sw_designs} brief {Get a list of software designs opened.}
    ::xsdb::setcmdmeta {hsi get_sw_designs} description [hsi::get_sw_designs -help]

    ::xsdb::setcmdmeta {hsi get_sw_interfaces} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_sw_interfaces} brief {Get a list of software interfaces.}
    ::xsdb::setcmdmeta {hsi get_sw_interfaces} description [hsi::get_sw_interfaces -help]

    ::xsdb::setcmdmeta {hsi get_sw_processor} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_sw_processor} brief {Get processor of the software design.}
    ::xsdb::setcmdmeta {hsi get_sw_processor} description [hsi::get_sw_processor -help]

    ::xsdb::setcmdmeta {hsi open_sw_design} categories {hsi}
    ::xsdb::setcmdmeta {hsi open_sw_design} brief {Open a software design from disk file.}
    ::xsdb::setcmdmeta {hsi open_sw_design} description [hsi::open_sw_design -help]

    ::xsdb::setcmdmeta {hsi set_repo_path} categories {hsi}
    ::xsdb::setcmdmeta {hsi set_repo_path} brief {Set a list of software repository paths.}
    ::xsdb::setcmdmeta {hsi set_repo_path} description [hsi::set_repo_path -help]

    ::xsdb::setcmdmeta {hsi create_property} categories {hsi}
    ::xsdb::setcmdmeta {hsi create_property} brief {Create property for class of object(s).}
    ::xsdb::setcmdmeta {hsi create_property} description [common::create_property -help]

    ::xsdb::setcmdmeta {hsi get_property} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_property} brief {Get properties of object.}
    ::xsdb::setcmdmeta {hsi get_property} description [common::get_property -help]

    ::xsdb::setcmdmeta {hsi list_property} categories {hsi}
    ::xsdb::setcmdmeta {hsi list_property} brief {List properties of object.}
    ::xsdb::setcmdmeta {hsi list_property} description [common::list_property -help]

    ::xsdb::setcmdmeta {hsi list_property_value} categories {hsi}
    ::xsdb::setcmdmeta {hsi list_property_value} brief {List legal property values of object.}
    ::xsdb::setcmdmeta {hsi list_property_value} description [common::list_property_value -help]

    ::xsdb::setcmdmeta {hsi report_property} categories {hsi}
    ::xsdb::setcmdmeta {hsi report_property} brief {Report properties of object.}
    ::xsdb::setcmdmeta {hsi report_property} description [common::report_property -help]

    ::xsdb::setcmdmeta {hsi reset_property} categories {hsi}
    ::xsdb::setcmdmeta {hsi reset_property} brief {Reset property of object(s).}
    ::xsdb::setcmdmeta {hsi reset_property} description [common::reset_property -help]

    ::xsdb::setcmdmeta {hsi set_property} categories {hsi}
    ::xsdb::setcmdmeta {hsi set_property} brief {Set property of object(s).}
    ::xsdb::setcmdmeta {hsi set_property} description [common::set_property -help]

    ::xsdb::setcmdmeta {hsi get_param} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_param} brief {Get a parameter value.}
    ::xsdb::setcmdmeta {hsi get_param} description [common::get_param -help]

    ::xsdb::setcmdmeta {hsi list_param} categories {hsi}
    ::xsdb::setcmdmeta {hsi list_param} brief {Get all parameter names.}
    ::xsdb::setcmdmeta {hsi list_param} description [common::list_param -help]

    ::xsdb::setcmdmeta {hsi report_param} categories {hsi}
    ::xsdb::setcmdmeta {hsi report_param} brief {Get information about all parameters.}
    ::xsdb::setcmdmeta {hsi report_param} description [common::report_param -help]

    ::xsdb::setcmdmeta {hsi reset_param} categories {hsi}
    ::xsdb::setcmdmeta {hsi reset_param} brief {Reset a parameter.}
    ::xsdb::setcmdmeta {hsi reset_param} description [common::reset_param -help]

    ::xsdb::setcmdmeta {hsi set_param} categories {hsi}
    ::xsdb::setcmdmeta {hsi set_param} brief {Set a param value.}
    ::xsdb::setcmdmeta {hsi set_param} description [common::set_param -help]

    ::xsdb::setcmdmeta {hsi get_msg_config} categories {hsi}
    ::xsdb::setcmdmeta {hsi get_msg_config} brief {Returns the current message count, limit, or message
                                configuration rules previously defined by set_msg_config command.}
    ::xsdb::setcmdmeta {hsi get_msg_config} description [common::get_msg_config -help]

    ::xsdb::setcmdmeta {hsi report_environment} categories {hsi}
    ::xsdb::setcmdmeta {hsi report_environment} brief {Report system information.}
    ::xsdb::setcmdmeta {hsi report_environment} description [common::report_environment -help]

    ::xsdb::setcmdmeta {hsi reset_msg_config} categories {hsi}
    ::xsdb::setcmdmeta {hsi reset_msg_config} brief {Resets or removes a message control rule previously
                                defined by the set_msg_config command.}
    ::xsdb::setcmdmeta {hsi reset_msg_config} description [common::reset_msg_config -help]

    ::xsdb::setcmdmeta {hsi reset_msg_count} categories {hsi}
    ::xsdb::setcmdmeta {hsi reset_msg_count} brief {Reset message count.}
    ::xsdb::setcmdmeta {hsi reset_msg_count} description [common::reset_msg_count -help]

    ::xsdb::setcmdmeta {hsi set_msg_config} categories {hsi}
    ::xsdb::setcmdmeta {hsi set_msg_config} brief {Configure how the Vivado tool will display and manage
                                specific messages, based on message ID, string, or severity.}
    ::xsdb::setcmdmeta {hsi set_msg_config} description [common::set_msg_config -help]

    ::xsdb::setcmdmeta {hsi list_features} categories {hsi}
    ::xsdb::setcmdmeta {hsi list_features} brief {List available features.}
    ::xsdb::setcmdmeta {hsi list_features} description [common::list_features -help]

    ::xsdb::setcmdmeta {hsi load_features} categories {hsi}
    ::xsdb::setcmdmeta {hsi load_features} brief {Load Tcl commands for a specified feature.}
    ::xsdb::setcmdmeta {hsi load_features} description [common::load_features -help]

    ::xsdb::setcmdmeta {hsi register_proc} categories {hsi}
    ::xsdb::setcmdmeta {hsi register_proc} brief {Register a Tcl proc with Vivado.}
    ::xsdb::setcmdmeta {hsi register_proc} description [common::register_proc -help]

    ::xsdb::setcmdmeta {hsi unregister_proc} categories {hsi}
    ::xsdb::setcmdmeta {hsi unregister_proc} brief {Unregister a previously registered Tcl proc.}
    ::xsdb::setcmdmeta {hsi unregister_proc} description [common::unregister_proc -help]
}

package provide hsi::help $::hsi::help::version
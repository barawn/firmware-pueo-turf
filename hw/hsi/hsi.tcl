#######################################################################
# Copyright (c) 2015-2021 Xilinx, Inc.  All rights reserved.
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

package require Tcl 8.5

# Temp changes to support gradle builds, which creates the libs with
# libxv_ prefix instead of librdi_ prefix. gradle build scripts search
# and replace "set GRADLE_BUILD 0" with "set GRADLE_BUILD 1" during build,
# so libxv_* libs are loaded when the tool is run from gradle output
set GRADLE_BUILD 0
if { $GRADLE_BUILD } {
    if { $::tcl_platform(platform) == "windows" } {
	set common_prefix "xv"
	set hsm_prefix "xv"
    } else {
	set common_prefix "libxv"
	set hsm_prefix "libxv"
    }
} else {
    set common_prefix "librdi"
    set hsm_prefix "librdi"
}

set loaded 0
foreach d $::auto_path {
    if { ![catch {load [file join $d [set common_prefix]_boardcommontasks[info sharedlibextension]] "Rdi_boardcommontasks"}] &&
         ![catch {load [file join $d [set common_prefix]_commontasks[info sharedlibextension]] "Rdi_commontasks"}] &&
	 ![catch {load [file join $d [set hsm_prefix]_hsmtasks[info sharedlibextension]] "Rdi_hsmtasks"}] &&
	 ![catch {load [file join $d [set hsm_prefix]_hsmswtasks[info sharedlibextension]] "Rdi_hsmswtasks"}] } {
	set loaded 1
	break
    }
}
if { !$loaded } {
    load [set common_prefix]_boardcommontasks[info sharedlibextension] "Rdi_boardcommontasks"
    load [set common_prefix]_commontasks[info sharedlibextension] "Rdi_commontasks"
    load [set hsm_prefix]_hsmtasks[info sharedlibextension] "Rdi_hsmtasks"
    load [set hsm_prefix]_hsmswtasks[info sharedlibextension] "Rdi_hsmswtasks"
}

proc setup_hsm_environment {}   {
    if { [info exists ::env(XILINX_VITIS)] == 0 ||
	 [info exists ::env(RDI_PLATFORM)] == 0 } {
      return
    }

    set xilinx_vitis $::env(XILINX_VITIS)
    set pf $::env(RDI_PLATFORM)

    set path_str ""
    if { $pf == "lnx64" } {
	set ps ":"
	set gnu_pf "lin64"
	set gnu_mbpf "lin"
	set gnu_mblepf "lin64_le"
	set gnu_mbbepf "lin64_be"
    } elseif { $pf == "lnx32" } {
	set ps ":"
	set gnu_pf "lin"
	set gnu_mbpf "lin"
	set gnu_mblepf "lin32_le"
	set gnu_mbbepf "lin32_be"
    } elseif { $pf == "win64" } {
	set ps ";"
	set gnu_pf "nt64"
	set gnu_mbpf "nt"
	set gnu_mblepf "nt64_le"
	set gnu_mbbepf "nt64_be"
	set path_str "$xilinx_vitis/gnuwin//bin$ps"
    } elseif { $pf == "win32" } {
	set ps ";"
	set gnu_pf "nt"
	set gnu_mbpf "nt"
	set gnu_mblepf "nt_le"
	set gnu_mbbepf "nt_be"
	set path_str "$xilinx_vitis/gnuwin//bin$ps"
    }

    set path_str "$path_str$xilinx_vitis/gnu/microblaze/$gnu_mbpf/bin$ps"
    set path_str "$path_str$xilinx_vitis/gnu/microblaze/linux_toolchain/$gnu_mblepf/bin$ps"
    set path_str "$path_str$xilinx_vitis/gnu/microblaze/linux_toolchain/$gnu_mbbepf/bin$ps$xilinx_vitis/gnu/arm/$gnu_mbpf/bin$ps"
    if { [info exists ::env(PATH)] } {
      set ::env(PATH) $path_str$::env(PATH)
    }
}
setup_hsm_environment

if { [info commands rdi::tcl::package] != "" } {
   rename package rdi::package
   rename rdi::tcl::package package
}
if { [info commands tcl::source] != "" } {
   rename source rdi::source
   rename tcl::source source
}
package provide hsi 0.1

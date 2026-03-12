# Create Vivado 2025.2 project for Arty-S7-50 FPGA
# Part: xc7s50csga324-1
# Target language: VHDL-2019

# Create project
create_project fm_radio_project . -part xc7s50csga324-1

# Set default target language to VHDL
set_property target_language VHDL [current_project]

# Default language
set lang "vhdl"

# determine directories relative to this script
set script_dir [file dirname [info script]]
set vhdl_dir [file normalize [file join $script_dir ../src/vhdl]]
set sv_dir   [file normalize [file join $script_dir ../src/systemVerilog]]
set constr_dir [file normalize [file join $script_dir constraints]]

# Check command line arguments
if {[llength $argv] > 0} {
    set lang [lindex $argv 0]
}

if {$lang eq "vhdl"} {
    puts "Using VHDL sources"

    # Add VHDL source files
    add_files -fileset sources_1 [glob $vhdl_dir/*.vhd]
} elseif {$lang eq "sv"} {
    puts "Using SystemVerilog sources"

    # Add SystemVerilog source files
    add_files -fileset sources_1 [glob $sv_dir/*.sv]
} else {
    puts "ERROR: Unsupported language '$lang'"
    puts "Usage: tclsh build.tcl \[vhdl|sv\]"
    exit 1
}

# Add constraint files
add_files -fileset constrs_1 [glob $constr_dir/*.xdc]

# Update compile order
update_compile_order -fileset sources_1

# Set top module/entity for the project fileset (name assumed 'toplevel')
set_property top toplevel [current_fileset]

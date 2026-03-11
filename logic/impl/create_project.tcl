# Create Vivado 2025.2 project for Arty-S7-50 FPGA
# Part: XC7S50-1CSGA324C
# Target language: VHDL-2019

# Create project
create_project fm_radio_project . -part XC7S50-1CSGA324C

# Set default target language to VHDL
set_property target_language VHDL [current_project]

# Default language
set lang "vhdl"

# Check command line arguments
if {[llength $argv] > 0} {
    set lang [lindex $argv 0]
}

if {$lang eq "vhdl"} {
    puts "Using VHDL sources"
    # Set VHDL version to 2008 (latest supported in Vivado)
    set_property target_language_version VHDL-2008 [current_project]

    # Add VHDL source files
    add_files -fileset sources_1 [glob logic/src/vhdl/*.vhd]
} elseif {$lang eq "sv"} {
    puts "Using SystemVerilog sources"
    # Set SystemVerilog version
    set_property target_language_version SystemVerilog-2017 [current_project]

    # Add SystemVerilog source files
    add_files -fileset sources_1 [glob logic/src/systemVerilog/*.sv]
} else {
    puts "ERROR: Unsupported language '$lang'"
    puts "Usage: tclsh build.tcl \[vhdl|sv\]"
    exit 1
}

# Add constraint files
add_files -fileset constrs_1 [glob logic/impl/constraints/*.xdc]

# Set top module
set_property top toplevel [current_fileset]

# Update compile order
update_compile_order -fileset sources_1
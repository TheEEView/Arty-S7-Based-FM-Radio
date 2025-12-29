# Arty-S7-Based-FM-Radio
FPGA Based FM Radio with custom RF frontend using an Arty S7 off the shelf development board spanning the 100MHz to 106MHz band with crisp high-end audio (16-bit stereo). This has been a WIP since Dec 2023.

Please See fm-radio-sysarch.png for a simple system block design.

Plase see fm-radio-fpga-arch.png for FPGA architecture in a block design.

This is the 2nd major gen design (First generation with 2 iterations were an all in one board with a Spartan 7 onboard), hence the v2 sch/pcb nomenclature. I will release the other version as another project.

The PCB is a 4 layer board with a S/G/G/S stackup using primarily 0402 components and high speed design principles.

TerosHDL, Vivado 2025.2, VUnit and KiCAD 9.0.6 have been used with github actions for CI.

Octave has been used for the filter design.

Source is available in both VHDL (IEEE Std 1076-2019) and SV (IEEE 1800-2023).

## How to generate BD TCL
From TCL Window in Vivado:
1. open_bd_design fm-radio-bd/fm-radio-bd.srcs/sources_1/bd/design_bd/design_bd.bd
2. write_bd_tcl fm_radio_bd.tcl

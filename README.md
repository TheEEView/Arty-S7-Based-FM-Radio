# Arty-S7-Based-FM-Radio
FPGA Based FM Radio with custom RF frontend using an Arty S7 off the shelf development board spanning the 88MHz to 108 MHz band with crisp high-end audio.

This is the 3rd gen design (First two generations were an all in one board with a Spartan 7 onboard), please ignore the _v2 nomenclature. I consider this to be the 2nd major iteration.

TerosHDL, Vivado 2025.2, VUnit and KiCAD 9.0.6 have been used with github actions for CI

Source is available in both VHDL and SV.

## How to generate BD TCL
From TCL Window in Vivado:
1. open_bd_design fm-radio-bd/fm-radio-bd.srcs/sources_1/bd/design_bd/design_bd.bd
2. write_bd_tcl fm_radio_bd.tcl

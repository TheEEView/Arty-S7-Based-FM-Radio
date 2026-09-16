# Arty-S7-Based-FM-Radio
FPGA Based FM Radio with custom RF frontend using an Arty S7 off the shelf development board spanning the 88MHz to 108MHz passband with crisp high-end audio (16-bit stereo). This has been a WIP since Dec 2023. The RF front end downmixes and filters the received FM signal down to 100kHz before the ADC.

This is the 2nd major gen design (First generation with 2 iterations were an all in one board with a Spartan 7 onboard), hence the v2 sch/pcb nomenclature. I will release the other version as another project.

The PCB is a 4 layer board with a S/G/G/S stackup using primarily 0402 components and high speed design principles. Routing is on the top and bottom layers only.

Please See docs/fm-radio-sysarch.png for a simple system block design and docs/fm-radio-fpga-arch for the FPGA architecture.

Vivado 2025.2.1, KiCAD 10 and Octave have been used.

Source is available in VHDL (IEEE Std 1076-2019).

## How to generate Vivado Project
source logic/impl/create_project.tcl

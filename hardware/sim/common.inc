* common.inc -- schematic component values, single source of truth.
* Every value here was pulled from analog_front_end_v2.kicad_sch via
* kicad-cli.  Refdes names match the schematic exactly.

* --- RF input bandpass filter (J1 .. U18) ---
.param C1=75p   C2=4.8p  C3=220p  C4=4.8p  C5=75p
.param L1=36n   L2=500n  L3=11.2n L4=500n  L5=36n

* --- LNA chain interstage ---
.param L8=470n  L9=470n  L10=470n L11=470n     $ bias chokes to 5V_LNA
.param C12=10n  C14=10n  C18=10n  C8=10n       $ AC coupling
.param PAD_IN=5 PAD_12=5 PAD_23=5 PAD_34=5 PAD_OUT=5   $ PAT1220 pads, dB

* --- balun + mixer RF match ---
.param C59=27p  L13=18n  L14=18n
.param R31=3.0  C60=1n                          $ T1 centre-tap bias

* --- mixer IF output ---
.param R33=330  R34=330  C64=1n
.param C65=100n C66=100n

* --- MFB lowpass stage 1 (U25 LTC6362) ---
.param R35=1000 R36=1000
.param R37=1000 R38=1000
.param R39=4020 R40=4020
.param C70=390p C71=130p C72=130p

* --- MFB lowpass stage 2 (U26 LTC6362) ---
.param R41=1000 R42=1000
.param R43=1000 R44=1000
.param R45=4020 R46=4020
.param C73=910p C74=56p  C75=56p

* --- ADC input RC (U6 MCP33131) ---
.param R47=22   R48=22   C76=1.8n C77=1.8n
.param VCM=1.25                                 $ R49/R50 divide 2.5V ref, U22 buffers

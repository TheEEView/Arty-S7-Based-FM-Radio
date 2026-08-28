* ifchain.inc -- LT5560 IF outputs (mxop/mxon) through to the MCP33131
* inputs (adcp/adcn).  Expects node "vcm" to be driven to the ADC common
* mode, and a differential current injected between mxop and mxon.
*
*   R33/R34/C64  mixer open-collector load
*   C65/C66      AC coupling
*   U25          MFB lowpass, stage 1
*   U26          MFB lowpass, stage 2
*   R47/R48 + C76/C77   ADC input RC / charge-kickback filter

R33 mxop 0 {R33}
R34 mxon 0 {R34}
C64 mxop mxon {C64}

C65 mxop ifp {C65}
C66 mxon ifn {C66}

* --- MFB stage 1 (U25) ---
R35 ifp s1a {R35}
R36 ifn s1b {R36}
C70 s1a s1b {C70}
R37 s1a s1n {R37}
R38 s1b s1p {R38}
R39 s1a o1p {R39}
R40 s1b o1n {R40}
C71 s1n o1p {C71}
C72 s1p o1n {C72}
XU25 s1p s1n vcm o1p o1n LTC6362

* --- MFB stage 2 (U26) ---
R41 o1p s2a {R41}
R42 o1n s2b {R42}
C73 s2a s2b {C73}
R43 s2a s2n {R43}
R44 s2b s2p {R44}
R45 s2a o2p {R45}
R46 s2b o2n {R46}
C74 s2n o2p {C74}
C75 s2p o2n {C75}
XU26 s2p s2n vcm o2p o2n LTC6362

* --- ADC input RC + sampler ---
R47 o2p adcp {R47}
R48 o2n adcn {R48}
C76 adcp 0 {C76}
C77 adcn 0 {C77}
XADC adcp adcn MCP33131

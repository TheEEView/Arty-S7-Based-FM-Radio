# Analog front end simulation

ngspice models of the `analog_front_end_v2` signal chain, built so the
board can be swept, corner-cased and Monte-Carlo'd before committing to
another spin.

```
./run.sh          # nominal benches, ~5 s
./run.sh mc       # + Monte Carlo (1300 trials), ~13 s
./run.sh e2e      # + end-to-end transient level plan, ~35 s
./run.sh all      # everything
```

Needs only `ngspice` (developed on 42) and python3 for `mcstat.py` —
standard library only, no numpy.

## What is modelled

Component values come from `analog_front_end_v2.kicad_sch`, extracted with
`kicad-cli sch export netlist`, and live in **one** place, `common.inc`.
Refdes names match the schematic. The two shared subnetworks,
`bpf.inc` and `ifchain.inc`, are included by both the nominal and the
Monte Carlo decks so the two cannot drift apart.

```
J1 ─ 5-pole LC BPF ─ U18 ─ U1 ─ U19 ─ U2 ─ U20 ─ U3 ─ U21 ─ U4 ─ U7 ─ T1
                     pad   LNA  pad   LNA  pad   LNA  pad   LNA  pad  balun
                                                                       │
   MCP33131 ◄─ R47/C76 ◄─ U26 MFB ◄─ U25 MFB ◄─ C65/66 ◄─ R33/34 ◄─ LT5560 ◄┘
                                                                     ▲
                                                        ADF4351 ─────┘
```

| bench | what it answers |
|---|---|
| `tb_lna_cal.cir`  | ADL5531 model vs datasheet (gain, NF) |
| `tb_bpf.cir`      | RF bandpass shape, insertion loss, out-of-band rejection |
| `tb_rf_chain.cir` | cascade gain and noise figure, antenna to mixer |
| `tb_padsweep.cir` | what the U18 input pad costs in NF |
| `tb_lo_drive.cir` | does the ADF4351 deliver enough LO to the LT5560 |
| `tb_if_chain.cir` | anti-alias response against the real 779.2 ksps plan |
| `tb_e2e.cir`      | full time-domain level plan, antenna dBm to ADC volts |
| `mc_bpf.cir`      | Monte Carlo: bandpass |
| `mc_rf_chain.cir` | Monte Carlo: cascade gain and NF |
| `mc_if_chain.cir` | Monte Carlo: anti-alias filter |

The operating point is taken from the RTL, not guessed: `fs = 779.2 ksps`
(`mpc33131_adc_driver.vhd`), IF pinned at 100 kHz and the LO one IF below
the station (`adf4351_driver.vhd`), so at full ±75 kHz deviation the
instantaneous IF sweeps 25 – 175 kHz (`fm_demodulator.vhd`).

## Model provenance

Everything in `models/behavioral.lib` is marked `[DS]` (from a datasheet),
`[FIT]` (calibrated by a bench in this directory) or `[ASSUMED]`.

Datasheet-backed:

- **LT5560** — `docs/LT5560f.pdf` Table 2 gives the differential signal
  input as 28.5 + j0.8 Ω at 70 MHz, modelled as 28.5 Ω + 1.8 nH. This
  confirms the board's C59/L13/L14 network: it transforms the 50 Ω balun
  secondary to 28.3 Ω, which is the right target. LO port 180 Ω needing
  240 mV<sub>rms</sub>, also from the datasheet.
- **ADL5531** — 20 dB, NF 2.6 dB, OP1dB +19.5 dBm. The input match is a
  *noiseless* synthesised 50 Ω (a real shunt resistor floors the model at
  NF = 3.0 dB and the part does 2.6 dB); `rnf` and `vsat` are then fitted
  to hit NF and OP1dB. `tb_lna_cal.cir` re-checks both.

Assumed, and worth your review:

- **LT5560 conversion transconductance.** Backed out of the 2.4 dB
  conversion-gain figure *assuming the datasheet test circuit presents a
  400 Ω differential IF load* → `gm = 19.4 mA/V`. The absolute level plan
  in `tb_e2e.cir` scales directly with this: a 3× error moves the clip
  point 10 dB. Everything else (filter shapes, NF, LO drive, all the
  Monte Carlo spreads) is independent of it.
- **LTC6362** GBW 34 MHz and ±1.2 V output swing per pin. The GBW is far
  enough above the 222 kHz corner not to matter; the swing limit *does*
  set the clip point in `tb_e2e.cir`.
- **Inductor Q = 40** at 103 MHz for the 0402 bandpass parts. This matters
  a lot — see below. Set `QL` in `bpf.inc` to whatever your actual parts do.

Not modelled: layout parasitics, and the LT5560's open-collector output
bias current (the real part sources ~6 mA per pin, so R33/R34 = 330 Ω drop
about 2 V from the 5 V rail — a headroom question this deck cannot answer).

## What the nominal sim says

**The bandpass costs 3.1 dB, not 0.5 dB.** With ideal inductors the filter
loses 0.5 dB in band. With Q = 40 it loses 3.1 dB, and the two 500 nH
series-arm inductors (L2, L4) dominate — they carry the most reactance so
they burn the most ESR. That 2.6 dB lands directly on the noise figure.
Set `QL=1e9` in `bpf.inc` to see the ideal case.

**Cascade NF is 10.7 dB, and 5 dB of it is the U18 pad.** The pads are
populated with `PAT1220-C-5DB-T5`. Anything ahead of U1 adds to NF one for
one, and `tb_padsweep.cir` shows exactly that:

```
 pad_dB   chain_gain_dB   cascade_NF_dB
    0          54.06           5.57
    5          49.06          10.71     <- as populated
   10          44.06          15.73
```

**The bandpass is fine but wide.** Geometric centre 102.9 MHz, −3 dB band
90.9 – 116.4 MHz, flat to 0.33 dB across 100 – 106. That is a 25 %
fractional bandwidth, which is why rejection at 88 MHz — the bottom of the
FM band, full of strong local transmitters — is only 10.4 dB. Out at
144 MHz it is 44 dB.

**The anti-alias filter is 222 kHz, not 320 kHz.** The header comment in
`fm_demodulator.vhd` says "320 kHz anti aliasing filter"; the two MFB
sections as built give a −3 dB corner of 222 kHz. The shape is very close
to a 4th-order Butterworth (0.18 dB peaking), slightly steeper than
textbook because the mixer's own R33/R34/C64 pole at ~241 kHz makes the
cascade effectively 5th order. Rejection over 604 – 754 kHz, the band that
folds onto the wanted 25 – 175 kHz IF at 779.2 ksps, is 38.6 dB.

**0.80 dB of tilt across the IF swing.** The filter is 0.14 dB down at
25 kHz and 0.80 dB down at 175 kHz. A slope detector turns amplitude tilt
into demodulated output, so this adds to the ~5 % full-deviation
distortion the RTL header already accounts for.

## Two things worth acting on

**1. The ADF4351 is programmed to under-drive the mixer LO.**
`adf4351_driver.vhd` declares `OUTPUT_POWER : natural := 0` (−4 dBm) and
`toplevel.vhd` does not override it. Through R51/C63/R32/C62 the network
delivers 0.626 V per volt of source EMF, so:

```
  ADF4351 setting   LO port mVrms   (LT5560 wants 240)
     -4 dBm             177          <- default, 2.7 dB short
     -1 dBm             250          marginal
     +2 dBm             352          comfortable
     +5 dBm             498
```

Passing `OUTPUT_POWER => 2` in the `toplevel.vhd` generic map fixes it.
Worth confirming on the bench before changing anything — an under-driven
LT5560 loses conversion gain and degrades NF rather than failing outright,
so it would not show up as a dead radio.

**2. The chain runs out of headroom long before the ADC does.**
`tb_e2e.cir` sweeps antenna power through the whole chain into the ADC pins:

```
 Pant_dBm   IF_pk_V   pct_FS
   -100      0.091      3.6
    -90      0.287     11.5
    -80      0.908     36.3
    -70      2.396     95.8    <- clipped
    -60      2.398     95.9
```

The LTC6362 output swing runs out around −75 dBm at the antenna; U4 hits
its own 1 dB compression near −41 dBm. With a cascade NF of 10.7 dB the
noise floor in a 200 kHz channel is about −110 dBm, so the usable window
is roughly 30 dB wide against an FM environment that spans −100 to
−20 dBm. Strong local stations will overload this front end.

This is the same knob as finding 1: four cascaded 20 dB gain blocks with
only 5 dB pads between them is +49 dB of RF gain. Trading pad values buys
headroom at the cost of NF, and `tb_padsweep.cir` plus `tb_e2e.cir`
together let you price that trade. Note the caveat above — the absolute
clip point scales with the assumed LT5560 conversion gain, so measure the
IF level on a real board before redesigning around it. The *shape* of the
problem (gain distribution) does not depend on that assumption.

## Monte Carlo

Each `mc_*.cir` has a knobs block at the top of its `.control` section:

```
let trials = 500
let tolc   = 0.02      $ capacitors
let toll   = 0.03      $ inductors
let tolq   = 0.30      $ inductor Q spread
let dist   = 0         $ 0 = gaussian truncated at 3 sigma, 1 = uniform
setseed 20260829       $ comment out for a fresh draw each run
```

Both halves of the differential IF pair are drawn independently, which is
what actually happens on a board and what creates the gain-mismatch
spread. Each deck writes `MC,...` CSV lines to stdout; `mcstat.py` turns
those into statistics, histograms and yield against limits:

```
./mcstat.py out/mc_if_chain.csv --limit fold_worst_db:max=-35 --hist f3db_hz
```

Results as built (500 / 300 / 500 trials, gaussian at 3σ):

| metric | mean | σ | p1 … p99 |
|---|---|---|---|
| BPF worst in-band IL | −3.24 dB | 0.34 | −4.16 … −2.54 |
| BPF ripple 100–106 | 0.33 dB | 0.067 | 0.18 … 0.49 |
| BPF rejection at 88 MHz | −10.47 dB | 0.74 | −12.2 … −8.8 |
| chain gain at 103 MHz | 48.97 dB | 0.42 | 47.97 … 49.80 |
| cascade NF at 103 MHz | 10.77 dB | 0.32 | 10.20 … 11.67 |
| AA −3 dB corner | 222.0 kHz | 0.72 k | 220.2 … 223.8 k |
| AA fold-band rejection | −38.71 dB | 0.12 | −38.97 … −38.44 |
| IF tilt at 175 kHz | −0.80 dB | 0.029 | −0.87 … −0.72 |

The filters are not tolerance-limited. The IF chain in particular barely
moves — 0.12 dB of σ on alias rejection — because it is all 1 % resistors
and 2 % C0G in a low-Q topology.

The bandpass insertion-loss spread is driven more by **inductor Q than by
component values**. Re-running `mc_bpf.cir` with `tolq = 0` (Q pinned at
40) drops σ from 0.34 dB to 0.17 dB and pulls the worst trial in from
−5.04 dB to −3.80 dB, so Q spread contributes roughly 0.29 dB of the
0.34 dB in quadrature and the L/C tolerances the remaining 0.17 dB. If you
want insertion loss held tightly, specify Q on L2 and L4 — tightening the
value tolerance buys about half as much.

## Adding a scenario

- **Temperature**: `.options TEMP=` in the deck, or `alter` the values from
  a tempco in the Monte Carlo loop.
- **Different pad values**: edit `PAD_IN` / `PAD_12` / … in `common.inc`.
- **Blocking / two-tone**: add a second `SIN` source in `tb_e2e.cir` at,
  say, 88 MHz and watch the 100 kHz IF amplitude drop as the blocker
  desensitises the chain. The compressing `ADL5531` subckt (not
  `ADL5531_LIN`) is already used there, so intermodulation shows up.
- **A different LT5560 conversion gain**: `XMIX ... LT5560 gm=<value>`.

## ngspice notes

Three things cost time while building this; they are worth knowing.

- `meas ac f3 when h=gpass-3 fall=1` does **not** evaluate the expression.
  It silently measures something else. Normalise first: `let hn = h - gpass`
  then `meas ac f3 when hn=-3 fall=1`.
- Only one `let` per line. `let a=1  let b=2` swallows the rest of the line
  into `a`'s right-hand side and `b` never exists.
- After `noise`, the current plot is the *integrated* noise plot; the
  spectral density is the one before it, so use `setplot previous`.
  `setplot noise1` re-selects the first noise run every time, which
  silently returns stale data inside a loop.
- `unif()` and `gauss()` are not available in the control language in
  ngspice 42; `sgauss(0)` and `sunif(0)` are, and the decks build
  truncated distributions from those.

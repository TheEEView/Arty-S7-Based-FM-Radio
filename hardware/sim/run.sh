#!/usr/bin/env bash
# run.sh -- run the whole analog front end simulation set.
#   ./run.sh            nominal benches only (fast, a few seconds)
#   ./run.sh mc         nominal + all three Monte Carlo runs
#   ./run.sh e2e        nominal + the end-to-end transient level plan
#   ./run.sh all        everything
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p out
MODE="${1:-nominal}"

hdr() { printf '\n\033[1m%s\033[0m\n' "$*"; }
run() { ngspice -b "$1" 2>/dev/null | sed -n "/$2/,/^\$/p"; }

hdr "[1/6] ADL5531 model calibration"
ngspice -b tb_lna_cal.cir 2>/dev/null | grep -E 'gain \.|noise figure'

hdr "[2/6] RF input bandpass filter"
ngspice -b tb_bpf.cir 2>/dev/null | sed -n '/=== RF bandpass/,/200 MHz/p'

hdr "[3/6] RF chain, antenna to mixer"
ngspice -b tb_rf_chain.cir 2>/dev/null | sed -n '/=== RF chain/,/floor/p' \
  | grep -vE 'Doing|Data Rows|^$'

hdr "[4/6] Input pad vs cascade noise figure"
ngspice -b tb_padsweep.cir 2>/dev/null | grep -E 'pad_dB|^ +[0-9]+ +[0-9]'

hdr "[5/6] ADF4351 to LT5560 LO drive"
ngspice -b tb_lo_drive.cir 2>/dev/null \
  | grep -E '=== ADF|MHz \(channel|LO port mVrms|dBm  \.'

hdr "[6/6] IF chain, mixer to ADC"
ngspice -b tb_if_chain.cir 2>/dev/null | sed -n '/=== IF chain/,/5 MHz/p'

if [ "$MODE" = "e2e" ] || [ "$MODE" = "all" ]; then
  hdr "[e2e] End-to-end level plan (takes ~35 s)"
  ngspice -b tb_e2e.cir 2>/dev/null \
    | grep -E 'Pant_dBm|^ +-[0-9]+ +|full scale|1:1|OP1dB'
fi

if [ "$MODE" = "mc" ] || [ "$MODE" = "all" ]; then
  hdr "[mc] Monte Carlo: RF bandpass"
  ngspice -b mc_bpf.cir 2>/dev/null | grep '^MC,' > out/mc_bpf.csv
  ./mcstat.py out/mc_bpf.csv \
      --limit il_worst_db:min=-4.0 \
      --limit ripple_db:max=1.0 \
      --hist il_worst_db

  hdr "[mc] Monte Carlo: RF chain gain and NF"
  ngspice -b mc_rf_chain.cir 2>/dev/null | grep '^MC,' > out/mc_rf_chain.csv
  ./mcstat.py out/mc_rf_chain.csv \
      --limit nf103_db:max=11.5 \
      --limit flatness_db:max=1.0 \
      --hist gain103_db

  hdr "[mc] Monte Carlo: IF anti-alias chain"
  ngspice -b mc_if_chain.cir 2>/dev/null | grep '^MC,' > out/mc_if_chain.csv
  ./mcstat.py out/mc_if_chain.csv \
      --limit fold_worst_db:max=-35 \
      --limit swing_pp_db:max=1.2 \
      --hist fold_worst_db
fi

printf '\nCSV traces and Monte Carlo results are in out/\n'

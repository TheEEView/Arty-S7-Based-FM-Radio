#!/usr/bin/env python3
"""Summarise an ngspice Monte Carlo CSV.

    mcstat.py out/mc_bpf.csv [--hist COL] [--limit COL:min=V] [--limit COL:max=V]

Reads the "MC,..." lines emitted by mc_*.cir, prints per-column statistics and
a pass/fail yield for any limits given.  Standard library only.
"""
import sys, math, statistics as st


def load(path):
    rows, header = [], None
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith("MC,"):
                continue
            parts = line.split(",")[1:]
            if header is None:
                header = parts
                continue
            rows.append(parts)
    if header is None:
        sys.exit(f"{path}: no MC lines found")
    cols = {}
    for i, name in enumerate(header):
        vals = []
        for r in rows:
            if i >= len(r) or r[i] == "":
                continue                      # a failed .meas leaves a blank
            try:
                vals.append(float(r[i]))
            except ValueError:
                pass
        cols[name] = vals
    return header, len(rows), cols


def pct(v, p):
    if not v:
        return float("nan")
    s = sorted(v)
    k = (len(s) - 1) * p / 100.0
    lo, hi = math.floor(k), math.ceil(k)
    return s[lo] if lo == hi else s[lo] + (s[hi] - s[lo]) * (k - lo)


def eng(x):
    if x != x:
        return "   n/a"
    a = abs(x)
    if a >= 1e6:
        return f"{x/1e6:.4g}M"
    if a >= 1e3:
        return f"{x/1e3:.4g}k"
    if a and a < 1e-3:
        return f"{x:.4g}"
    return f"{x:.5g}"


def hist(vals, width=52, bins=20):
    if len(vals) < 2:
        return
    lo, hi = min(vals), max(vals)
    if hi == lo:
        print(f"    all {len(vals)} trials at {eng(lo)}")
        return
    counts = [0] * bins
    for v in vals:
        counts[min(bins - 1, int((v - lo) / (hi - lo) * bins))] += 1
    top = max(counts)
    for i, c in enumerate(counts):
        edge = lo + (hi - lo) * i / bins
        bar = "#" * int(round(c / top * width))
        print(f"    {eng(edge):>10} | {bar}{'' if c else ''} {c}")


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    path = args[0]
    hists, limits = [], []
    i = 1
    while i < len(args):
        if args[i] == "--hist":
            hists.append(args[i + 1]); i += 2
        elif args[i] == "--limit":
            col, spec = args[i + 1].split(":")
            kind, val = spec.split("=")
            limits.append((col, kind, float(val))); i += 2
        else:
            sys.exit(f"unknown argument {args[i]}")

    header, n, cols = load(path)
    print(f"\n{path}   {n} trials\n")
    print(f"{'metric':<16}{'n':>5}{'mean':>12}{'sd':>11}{'min':>12}"
          f"{'p1':>11}{'p50':>11}{'p99':>11}{'max':>12}")
    print("-" * 101)
    for name in header:
        if name == "run":
            continue
        v = cols[name]
        if not v:
            print(f"{name:<16}{0:>5}   (no valid samples -- .meas failed every trial)")
            continue
        sd = st.stdev(v) if len(v) > 1 else 0.0
        print(f"{name:<16}{len(v):>5}{eng(st.fmean(v)):>12}{eng(sd):>11}"
              f"{eng(min(v)):>12}{eng(pct(v,1)):>11}{eng(pct(v,50)):>11}"
              f"{eng(pct(v,99)):>11}{eng(max(v)):>12}")
        if len(v) < n:
            print(f"{'':<16}     ({n-len(v)} trial(s) had no measurable value)")

    for col, kind, lim in limits:
        v = cols.get(col)
        if not v:
            print(f"\nlimit {col}: no data")
            continue
        ok = [x for x in v if (x >= lim if kind == "min" else x <= lim)]
        y = 100.0 * len(ok) / n
        verdict = "PASS" if len(ok) == n else "FAIL"
        print(f"\nyield  {col} {kind}={lim:g} : {len(ok)}/{n} = {y:.2f}%   [{verdict}]")
        if len(ok) < n:
            bad = [x for x in v if x not in ok]
            worst = min(bad) if kind == "min" else max(bad)
            print(f"       worst violator {eng(worst)}")

    for name in hists:
        if name in cols and cols[name]:
            print(f"\nhistogram: {name}")
            hist(cols[name])
    print()


if __name__ == "__main__":
    main()

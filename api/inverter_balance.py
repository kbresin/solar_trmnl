#!/usr/bin/env python3
"""Compare each inverter's output per panel against its own recent history.

The inverters don't produce equally per panel: on Nov 2026 data, Inverter 4 runs
80-98% of the median (shading in direct sun) and Inverter 1 runs ~104%. A fixed
threshold would fire on Inverter 4 every sunny week, so each inverter is judged
against itself instead. Its share of the median over the last 7 days is
compared with its share over the 21 days before.

Over 90 days (Aug-Nov 2026) of healthy data, that share moved by at most
4.9 points. One dead panel only moves it 3.3-4 points, so this catches a
failing string or several panels; single optimizers are covered by the optimizer
check in check4faults.sh and by SolarEdge's own alerts.

Usage: inverter_balance.py TELEMETRY_DAY_JSON OPTIMIZERS_JSON
  TELEMETRY_DAY_JSON  /inverters/telemetry?resolution=DAY covering 28 full days
  OPTIMIZERS_JSON     /devices?types=OPTIMIZER (active ones give panels per inverter)
Exit: 0 balanced, 1 an inverter dropped, 2 bad input.
"""
import json
import statistics
import sys
from collections import defaultdict

DROP_PTS = 8.0  # warn when this week's share is this many points below baseline
MIN_WEEK_WH_PER_PANEL = 1000  # skip judging in very dark/snowy weeks
RECENT_DAYS, BASELINE_DAYS = 7, 21


def main(tel_path, opt_path):
    telemetry = json.load(open(tel_path))
    optimizers = json.load(open(opt_path))

    panels, names = defaultdict(int), {}
    for o in optimizers:
        if o.get("active"):
            panels[o["connectedTo"]] += 1
            names[o["connectedTo"]] = o.get("connectedToName") or o["connectedTo"]

    # day -> inverter serial -> Wh per panel
    days = defaultdict(dict)
    for sn, series in telemetry["inverters"].items():
        if not panels.get(sn):
            continue
        for v in series["energy"]["values"]:
            if v["value"] is not None:
                days[v["timestamp"][:10]][sn] = v["value"] / panels[sn]
    complete = sorted(d for d in days if len(days[d]) == len(panels))
    if len(complete) < RECENT_DAYS + 7:
        print(f"Inverter balance: only {len(complete)} complete days of data, skipped")
        return 0

    def shares(window):
        totals = {sn: sum(days[d][sn] for d in window) for sn in panels}
        median = statistics.median(totals.values())
        return {sn: t / median for sn, t in totals.items()}, median

    recent_days = complete[-RECENT_DAYS:]
    baseline_days = complete[-(RECENT_DAYS + BASELINE_DAYS):-RECENT_DAYS]
    recent, recent_median = shares(recent_days)
    baseline, _ = shares(baseline_days)

    judged = recent_median >= MIN_WEEK_WH_PER_PANEL
    print(f"Inverter balance: output per panel as % of the median inverter, "
          f"{recent_days[0]}..{recent_days[-1]} vs the {len(baseline_days)} days before "
          f"(median {recent_median / 1000:.1f} kWh/panel this week)")
    dropped = []
    for sn in sorted(panels, key=lambda s: names[s]):
        delta = (recent[sn] - baseline[sn]) * 100
        flag = judged and delta <= -DROP_PTS
        if flag:
            dropped.append(sn)
        print(f"  {'LOW ' if flag else ''}{names[sn]} ({panels[sn]} panels): "
              f"{recent[sn] * 100:.1f}% (was {baseline[sn] * 100:.1f}%, {delta:+.1f})")
    if not judged:
        print(f"  (too little sun this week to judge; needs {MIN_WEEK_WH_PER_PANEL} Wh/panel)")
    if dropped:
        print(f"PERF: {', '.join(names[s] for s in dropped)} dropped {DROP_PTS:.0f}+ points "
              f"against its own baseline. Possible failed string or panels (or uneven snow).")
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1], sys.argv[2]))
    except (OSError, ValueError, KeyError, TypeError) as e:
        print(f"ERROR: inverter balance: {e}", file=sys.stderr)
        sys.exit(2)

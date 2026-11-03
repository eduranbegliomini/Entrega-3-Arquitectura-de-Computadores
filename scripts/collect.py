#!/usr/bin/env python3
"""Summarise LibreLane runs into results/runs.csv and results/runs.md.

Usage: python3 scripts/collect.py [design ...]      (default: rom rom_opt ff)

For every librelane/<design>/runs/<tag>/ it reads resolved.json (the
configuration actually used) and the latest metrics.json, and reports area,
utilisation, flip-flops, setup/hold WNS/TNS for the typical and the slowest
corner, routing DRC (a congestion indicator), Magic/KLayout DRC, LVS and
antenna. A run "closes" when the flow completed and every criterion of the
assignment holds: DRC = LVS = antenna = 0, setup and hold WNS >= 0 and
TNS = 0 in the typical and slowest corners.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TT = "nom_tt_025C_5v00"
SS = "max_ss_125C_4v50"   # slowest corner: slow-slow, 125 C, 4.5 V, max parasitics
COST_PER_MM2 = 23000

COLUMNS = [
    "design", "tag", "status", "CLOCK_PERIOD", "FP_CORE_UTIL", "die_um2", "die_mm2",
    "cost_usd", "core_um2", "stdcell_area_um2", "utilization", "stdcells", "flip_flops",
    "setup_ws_tt", "setup_tns_tt", "hold_ws_tt", "hold_tns_tt",
    "setup_ws_ss", "setup_tns_ss", "hold_ws_ss", "hold_tns_ss",
    "fmax_est_mhz", "route_drc_iter0", "route_drc", "magic_drc", "klayout_drc", "lvs_errors",
    "antenna_nets", "max_slew_viol_ss", "wirelength_um",
]


def latest_metrics(run: Path) -> dict:
    final = run / "final" / "metrics.json"
    if final.exists():
        return json.loads(final.read_text())
    steps = sorted((p for p in run.iterdir() if p.is_dir() and p.name[:2].isdigit()),
                   key=lambda p: int(p.name.split("-")[0]))
    for step in reversed(steps):
        state = step / "state_out.json"
        if state.exists():
            return json.loads(state.read_text()).get("metrics", {})
    return {}


def status_of(run: Path) -> str:
    log = run / "flow.log"
    text = log.read_text(errors="replace") if log.exists() else ""
    if "Flow complete." in text:
        return "complete"
    err = run / "error.log"
    first = err.read_text(errors="replace").strip().splitlines()[:1] if err.exists() else []
    return "failed: " + (first[0][:80] if first else "unknown")


def summarise(design: str, run: Path) -> dict | None:
    resolved = run / "resolved.json"
    if not resolved.exists():
        return None
    cfg = json.loads(resolved.read_text())
    m = latest_metrics(run)

    def g(key, default=None):
        return m.get(key, default)

    die = g("design__die__area")
    row = {
        "design": design, "tag": run.name, "status": status_of(run),
        "CLOCK_PERIOD": cfg.get("CLOCK_PERIOD"), "FP_CORE_UTIL": cfg.get("FP_CORE_UTIL"),
        "die_um2": die, "die_mm2": round(die / 1e6, 4) if die else None,
        "cost_usd": round(die / 1e6 * COST_PER_MM2) if die else None,
        "core_um2": g("design__core__area"),
        "stdcell_area_um2": g("design__instance__area__stdcell"),
        "utilization": g("design__instance__utilization"),
        "stdcells": g("design__instance__count__stdcell"),
        "flip_flops": g("design__instance__count__class:sequential_cell"),
        "setup_ws_tt": g(f"timing__setup__ws__corner:{TT}"),
        "setup_tns_tt": g(f"timing__setup__tns__corner:{TT}"),
        "hold_ws_tt": g(f"timing__hold__ws__corner:{TT}"),
        "hold_tns_tt": g(f"timing__hold__tns__corner:{TT}"),
        "setup_ws_ss": g(f"timing__setup__ws__corner:{SS}"),
        "setup_tns_ss": g(f"timing__setup__tns__corner:{SS}"),
        "hold_ws_ss": g(f"timing__hold__ws__corner:{SS}"),
        "hold_tns_ss": g(f"timing__hold__tns__corner:{SS}"),
        "route_drc_iter0": g("route__drc_errors__iter:0"),
        "route_drc": g("route__drc_errors"),
        "magic_drc": g("magic__drc_error__count"),
        "klayout_drc": g("klayout__drc_error__count"),
        "lvs_errors": g("design__lvs_error__count"),
        "antenna_nets": g("antenna__violating__nets"),
        "max_slew_viol_ss": g(f"design__max_slew_violation__count__corner:{SS}"),
        "wirelength_um": g("route__wirelength"),
    }
    period, ws = row["CLOCK_PERIOD"], row["setup_ws_ss"]
    if period is not None and ws is not None and period - ws > 0:
        # Worst-corner critical path delay = T - WNS. Only an estimate: a new
        # CLOCK_PERIOD re-optimises the netlist (sizing, buffering, placement).
        row["fmax_est_mhz"] = round(1000.0 / (float(period) - float(ws)), 2)
    return row


def closes(r: dict) -> bool:
    try:
        return (r["status"] == "complete"
                and all((r[k] or 0) == 0 for k in ("magic_drc", "lvs_errors", "antenna_nets", "route_drc"))
                and all(r[k] is not None and r[k] >= 0 for k in ("setup_ws_tt", "hold_ws_tt", "setup_ws_ss", "hold_ws_ss"))
                and all(abs(r[k] or 0) == 0 for k in ("setup_tns_tt", "hold_tns_tt", "setup_tns_ss", "hold_tns_ss")))
    except TypeError:
        return False


def fmt(v):
    if isinstance(v, float):
        return f"{v:.3f}" if abs(v) < 1000 else f"{v:.0f}"
    return "" if v is None else str(v)


def main(argv: list[str]) -> int:
    designs = argv or ["rom", "rom_opt", "ff"]
    rows = []
    for design in designs:
        runs = ROOT / "librelane" / design / "runs"
        if not runs.is_dir():
            continue
        for run in sorted(runs.iterdir()):
            if run.is_dir() and (row := summarise(design, run)):
                row["closes"] = "yes" if closes(row) else "no"
                rows.append(row)
    out = ROOT / "results"
    out.mkdir(exist_ok=True)
    cols = COLUMNS[:3] + ["closes"] + COLUMNS[3:]
    with open(out / "runs.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    with open(out / "runs.md", "w") as f:
        f.write("| " + " | ".join(cols) + " |\n|" + "---|" * len(cols) + "\n")
        for r in rows:
            f.write("| " + " | ".join(fmt(r.get(c)) for c in cols) + " |\n")
    for r in rows:
        print(f"{r['design']:>3} {r['tag']:<16} closes={r['closes']:<3} T={fmt(r['CLOCK_PERIOD'])} U={fmt(r['FP_CORE_UTIL'])} "
              f"die={fmt(r['die_um2'])}um2 util={fmt(r['utilization'])} FF={fmt(r['flip_flops'])} "
              f"setup tt/ss={fmt(r['setup_ws_tt'])}/{fmt(r['setup_ws_ss'])} hold tt/ss={fmt(r['hold_ws_tt'])}/{fmt(r['hold_ws_ss'])} "
              f"routeDRC0={fmt(r['route_drc_iter0'])} {r['status'] if r['status'] != 'complete' else ''}")
    print(f"-> {out / 'runs.csv'}, {out / 'runs.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

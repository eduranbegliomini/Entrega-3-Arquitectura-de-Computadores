#!/usr/bin/env python3
"""Plots for the report from results/runs.csv (python3 scripts/collect.py first).

  results/plot_util.png    FP_CORE_UTIL vs die area and routing congestion
                           (detailed-routing DRC count at iteration 0)
  results/plot_period.png  CLOCK_PERIOD vs setup WNS (typical and slowest corner)
"""
import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "results"
rows = list(csv.DictReader(open(RES / "runs.csv")))


def num(r, k):
    try:
        return float(r[k])
    except (TypeError, ValueError):
        return None


plt.rcParams.update({"font.size": 10, "axes.grid": True, "grid.alpha": 0.3})

# ---- utilisation sweep (rom, T = 100 ns) ----
util = sorted((r for r in rows if r["design"] == "rom" and r["tag"].startswith("T100_U")),
              key=lambda r: num(r, "FP_CORE_UTIL"))
if util:
    u = [num(r, "FP_CORE_UTIL") for r in util]
    die = [num(r, "die_mm2") for r in util]
    drc0 = [num(r, "route_drc_iter0") for r in util]
    ok = [r["closes"] == "yes" for r in util]
    fig, ax1 = plt.subplots(figsize=(6.5, 4))
    ax1.plot(u, die, "o-", color="#1f77b4", label="Área del die (mm²)")
    ax1.set_xlabel("FP_CORE_UTIL (%)")
    ax1.set_ylabel("Área del die (mm²)", color="#1f77b4")
    ax2 = ax1.twinx()
    ax2.plot(u, [d if d is not None else float("nan") for d in drc0], "s--", color="#d62728",
             label="Violaciones DRC de ruteo (iteración 0)")
    ax2.set_ylabel("Violaciones DRC de ruteo, iter. 0", color="#d62728")
    ax2.grid(False)
    for x, y, good in zip(u, die, ok):
        ax1.annotate("cierra" if good else "NO cierra", (x, y), textcoords="offset points",
                     xytext=(0, 8), ha="center", fontsize=8, color="green" if good else "red")
    ax1.set_title("Barrido de utilización (estrategia ROM, T = 100 ns)")
    fig.tight_layout()
    fig.savefig(RES / "plot_util.png", dpi=160)

# ---- period sweep ----
fig, ax = plt.subplots(figsize=(6.5, 4))
for design, colour in (("rom", "#1f77b4"), ("rom_opt", "#2ca02c"), ("ff", "#9467bd")):
    pts = sorted((r for r in rows if r["design"] == design and r["tag"].endswith("_U40")
                  and num(r, "setup_ws_ss") is not None), key=lambda r: num(r, "CLOCK_PERIOD"))
    if not pts:
        continue
    t = [num(r, "CLOCK_PERIOD") for r in pts]
    ax.plot(t, [num(r, "setup_ws_ss") for r in pts], "o-", color=colour, label=f"{design}: setup WNS, corner lento")
    ax.plot(t, [num(r, "setup_ws_tt") for r in pts], "o:", color=colour, alpha=0.6, label=f"{design}: setup WNS, típico")
ax.axhline(0, color="black", lw=0.8)
ax.set_xlabel("CLOCK_PERIOD (ns)")
ax.set_ylabel("Setup WNS (ns)")
ax.set_title("Barrido de período de reloj (U = 40 %)")
ax.legend(fontsize=7)
fig.tight_layout()
fig.savefig(RES / "plot_period.png", dpi=160)
print("wrote", RES / "plot_util.png", RES / "plot_period.png")

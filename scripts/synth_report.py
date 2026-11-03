#!/usr/bin/env python3
"""Section 3.3: hierarchical synthesis report of one LibreLane run.

Usage: python3 scripts/synth_report.py <design> <run_tag>
       e.g. python3 scripts/synth_report.py rom final

The flow uses SYNTH_HIERARCHY_MODE = "keep", so Yosys's stat.json already
contains one entry per module; each module's "area" is hierarchical (it
includes its submodules). This script prints the five most used cells, the
area and flip-flop count of every module and the fraction taken by the cycle
counter added in Proyecto 2 (pochoco_cycle_counter). Output: stdout and
results/synth_<design>_<tag>.md.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CELL_PREFIX = "gf180mcu_fd_sc_mcu7t5v0__"

# Instance path of each module in the design (one instance per module).
INSTANCES = {
    "asic_top": "asic_top",
    "pochoco_soc": "u_soc",
    "espino_core": "u_soc/u_core",
    "espino_if_stage": "u_soc/u_core/u_if",
    "espino_id_stage": "u_soc/u_core/u_id",
    "espino_decoder": "u_soc/u_core/u_id/u_decoder",
    "espino_alu": "u_soc/u_core/u_id/u_alu",
    "espino_register_file": "u_soc/u_core/u_rf",
    "espino_load_store_unit": "u_soc/u_core/u_lsu",
    "espino_controller": "u_soc/u_core/u_ctrl",
    "pochoco_rom": "u_soc/u_rom",
    "pochoco_dram": "u_soc/u_dram",
    "pochoco_ram_ff": "u_soc/u_mem",
    "pochoco_periph": "u_soc/u_periph",
    "pochoco_cycle_counter": "u_soc/u_periph/u_cycle_counter",
    "pochoco_spi_slave": "u_soc/u_spi",
}


def clean(name: str) -> str:
    name = name.lstrip("\\")
    m = re.match(r"\$paramod\\([^\\]+)", name)
    return m.group(1) if m else name


def own_cells(mod: dict) -> dict:
    cells = mod.get("num_cells_by_type", {})
    return {k: v for k, v in cells.items() if k.startswith(CELL_PREFIX)}


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 1
    design, tag = argv
    run = ROOT / "librelane" / design / "runs" / tag
    synth = sorted(run.glob("*-yosys-synthesis"))
    if not synth:
        print(f"no synthesis step in {run}")
        return 1
    stat = json.loads((synth[0] / "reports" / "stat.json").read_text())
    modules = {clean(k): v for k, v in stat["modules"].items()}
    total = stat["design"]["area"]
    seq_total = stat["design"].get("sequential_area")

    lines = [f"# Synthesis report: {design}/{tag}", "",
             f"Source: `{synth[0].relative_to(ROOT)}/reports/stat.json` (Yosys `stat -liberty`, hierarchy kept).", "",
             f"Total cell area: **{total:,.1f} µm²** (sequential {seq_total:,.1f} µm², {100*seq_total/total:.1f} %)", ""]

    cells = {k: v for k, v in stat["design"]["num_cells_by_type"].items() if k.startswith(CELL_PREFIX)}
    lines += ["## Five most used cells", "", "| cell | count |", "|---|---|"]
    for cell, n in sorted(cells.items(), key=lambda kv: -kv[1])[:5]:
        lines.append(f"| {cell.replace(CELL_PREFIX, '')} | {n} |")
    lines.append("")

    def ffs(name: str) -> int:
        mod = modules[name]
        n = sum(v for k, v in own_cells(mod).items() if "dff" in k)
        for sub, count in mod.get("num_cells_by_type", {}).items():
            if not sub.startswith(CELL_PREFIX) and clean(sub) in modules:
                n += count * ffs(clean(sub))
        return n

    lines += ["## Area per module (hierarchical: includes submodules)", "",
              "| module | instance | area µm² | % of total | flip-flops | top cells (own) |", "|---|---|---|---|---|---|"]
    order = [m for m in INSTANCES if m in modules] + [m for m in modules if m not in INSTANCES]
    for name in order:
        mod = modules[name]
        top = ", ".join(f"{k.replace(CELL_PREFIX, '')}×{v}" for k, v in sorted(own_cells(mod).items(), key=lambda kv: -kv[1])[:3])
        lines.append(f"| {name} | {INSTANCES.get(name, '?')} | {mod['area']:,.1f} | {100*mod['area']/total:.1f} | {ffs(name)} | {top} |")
    lines.append("")

    leaves = [m for m in modules if m not in ("asic_top", "pochoco_soc", "espino_core", "espino_id_stage")]
    biggest = max(leaves, key=lambda m: modules[m]["area"])
    lines.append(f"Largest leaf-level block: **{biggest}** ({modules[biggest]['area']:,.1f} µm², "
                 f"{100*modules[biggest]['area']/total:.1f} %).")
    if "pochoco_cycle_counter" in modules:
        cc = modules["pochoco_cycle_counter"]["area"]
        lines.append(f"Cycle counter (pochoco_cycle_counter, 32-bit counter + 32-bit target timestamp): "
                     f"**{cc:,.1f} µm² = {100*cc/total:.2f} %** of the cell area.")
    text = "\n".join(lines) + "\n"
    print(text)
    out = ROOT / "results"
    out.mkdir(exist_ok=True)
    (out / f"synth_{design}_{tag}.md").write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

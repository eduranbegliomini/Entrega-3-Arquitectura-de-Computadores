#!/usr/bin/env bash
# Section 3.7: post-synthesis functional simulation (no annotated delays).
#   scripts/gate_sim.sh <rom|ff>
# 1. Assembles game.s with -D CLK_HZ=2000 (0.1 s = 200 cycles, 3 s = 6000)
#    into sw/build_sim. The SAME program is used by both simulations.
# 2. Synthesizes asic_top with that program (LibreLane, Yosys only).
# 3. Runs tb/tb_game.v on the RTL and on the netlist and compares the logs.
set -euo pipefail
source "$(dirname "$0")/env.sh"
design=${1:?usage: gate_sim.sh <rom|ff>}
case $design in rom) DEF=MEM_ROM ;; ff) DEF=MEM_UNIFIED_FF ;; *) echo "usage: gate_sim.sh <rom|ff>"; exit 1 ;; esac
cd "$ROOT"
SIM_CLK_HZ=2000

python3 tools/assembler.py sw/game.s -o sw/build_sim/game.hex -D CLK_HZ=$SIM_CLK_HZ \
  --verilog sw/build_sim/game_program.vh

scripts/run.sh "$design" gatesim --to Yosys.Synthesis -c "VERILOG_INCLUDE_DIRS=$ROOT/sw/build_sim"
RUN=librelane/$design/runs/gatesim
NL=$RUN/final/nl/asic_top.nl.v
PDK_ROOT_USED=$(python3 -c "import json,sys;print(json.load(open('$RUN/resolved.json'))['PDK_ROOT'])")
CELLS=$PDK_ROOT_USED/$PDK/libs.ref/$SCL/verilog

IVERILOG=$(find_tool iverilog iverilog); VVP=$(find_tool vvp iverilog)
mkdir -p tb/out
echo "=== RTL simulation ($DEF)"
"$IVERILOG" -g2005 -D$DEF -I sw/build_sim -o tb/out/rtl_$design.vvp rtl/*.v tb/tb_game.v
"$VVP" -n tb/out/rtl_$design.vvp +LOG=tb/out/rtl_$design.log | tee tb/out/rtl_$design.txt
echo "=== Post-synthesis netlist simulation ($NL)"
"$IVERILOG" -g2005 -DFUNCTIONAL -D$DEF -o tb/out/gate_$design.vvp \
  "$CELLS/primitives.v" "$CELLS/$SCL.v" "$NL" tb/tb_game.v
"$VVP" -n tb/out/gate_$design.vvp +LOG=tb/out/gate_$design.log | tee tb/out/gate_$design.txt
echo "=== Comparing output-port and measured-cycle logs"
if diff tb/out/rtl_$design.log tb/out/gate_$design.log; then
  echo "RTL and netlist logs are IDENTICAL ($(wc -l < tb/out/rtl_$design.log) events)"
else
  echo "RTL and netlist logs DIFFER"; exit 1
fi

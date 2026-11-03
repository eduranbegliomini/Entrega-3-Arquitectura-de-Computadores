# Proyecto 2 reference RTL (section 3.1 evidence)

* `rtl/`: the Proyecto 2 RTL exactly as delivered for the FPGA (Go Board, iCE40).
  `librelane/p2_original` runs it through LibreLane to collect the warnings and
  errors that expose each FPGA-only construct.
* `rtl_step2/`: the same RTL with only `espino_register_file.v` replaced by the
  flip-flop version, so that the flow gets past the missing `SB_RAM40_4K`
  primitive and reports on the remaining constructs (`$readmemh`, the BRAM
  inferred in `pochoco_ram`, the `por_cnt = 0` initial value).
  Run with `librelane/p2_step2`.
* `sw/game.hex`: the Proyecto 2 program (25 MHz constants).
* `rtl_step3/`: step 2 plus `game.hex` next to the sources (`MemFile("game.hex")`),
  so `$readmemh` succeeds and Yosys has to build the 512 x 32 `pochoco_ram`
  without BRAM. Run with `librelane/p2_step3` (synthesis only).

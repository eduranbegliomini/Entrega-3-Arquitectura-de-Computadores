# Synthesis report: rom/T100_U40

Source: `librelane/rom/runs/T100_U40/06-yosys-synthesis/reports/stat.json` (Yosys `stat -liberty`, hierarchy kept).

Total cell area: **158,579.1 µm²** (sequential 72,709.4 µm², 45.9 %)

## Five most used cells

| cell | count |
|---|---|
| dffrnq_1 | 971 |
| mux2_2 | 823 |
| aoi22_1 | 555 |
| nand2_1 | 529 |
| nor2_1 | 300 |

## Area per module (hierarchical: includes submodules)

| module | instance | area µm² | % of total | flip-flops | top cells (own) |
|---|---|---|---|---|---|
| asic_top | asic_top | 158,579.1 | 100.0 | 974 |  |
| pochoco_soc | u_soc | 158,579.1 | 100.0 | 974 | mux2_2×66, dffrnq_1×4, and2_1×2 |
| espino_core | u_soc/u_core | 104,056.9 | 65.6 | 611 |  |
| espino_if_stage | u_soc/u_core/u_if | 8,510.8 | 5.4 | 65 | dffrnq_1×65, mux2_2×30, nand2_1×25 |
| espino_id_stage | u_soc/u_core/u_id | 22,388.8 | 14.1 | 1 | nand2_1×74, aoi22_1×58, clkinv_1×53 |
| espino_decoder | u_soc/u_core/u_id/u_decoder | 2,215.0 | 1.4 | 0 | nand2_1×53, clkinv_1×20, buf_1×19 |
| espino_alu | u_soc/u_core/u_id/u_alu | 10,152.8 | 6.4 | 0 | nand2_1×106, xor2_1×64, nor2_1×57 |
| espino_register_file | u_soc/u_core/u_rf | 69,875.4 | 44.1 | 544 | dffrnq_1×544, mux2_2×480, aoi22_1×384 |
| espino_load_store_unit | u_soc/u_core/u_lsu | 3,211.6 | 2.0 | 1 | nand2_1×94, buf_1×38, aoi22_1×15 |
| espino_controller | u_soc/u_core/u_ctrl | 70.2 | 0.0 | 0 | clkinv_1×2, oai21_1×2, nor3_1×1 |
| pochoco_rom | u_soc/u_rom | 12,409.5 | 7.8 | 31 | nand2_1×114, nor2_1×72, nand3_1×60 |
| pochoco_dram | u_soc/u_dram | 18,689.9 | 11.8 | 160 | dffrnq_1×160, mux2_2×128, nand3_1×35 |
| pochoco_periph | u_soc/u_periph | 14,552.0 | 9.2 | 116 | nor2_1×65, dffrnq_1×52, aoi221_1×32 |
| pochoco_cycle_counter | u_soc/u_periph/u_cycle_counter | 7,325.4 | 4.6 | 64 | dffrnq_1×64, mux2_2×23, aoi21_1×16 |
| pochoco_spi_slave | u_soc/u_spi | 6,276.1 | 4.0 | 52 | dffrnq_1×49, mux2_2×27, tiel×24 |

Largest leaf-level block: **espino_register_file** (69,875.4 µm², 44.1 %).
Cycle counter (pochoco_cycle_counter, 32-bit counter + 32-bit target timestamp): **7,325.4 µm² = 4.62 %** of the cell area.

# Evidencia de la sección 3.1: construcciones del RTL del Proyecto 2 que dependen de la FPGA

Corridas: `librelane/p2_original` (RTL del Proyecto 2 sin cambios), `librelane/p2_step2`
(solo se reemplazó el register file) y `librelane/p2_step3` (además se dejó `game.hex`
junto al RTL para que `$readmemh` funcione). LibreLane 3.0.17, gf180mcuD. Los logs
copiados en esta carpeta conservan la numeración de líneas original.

| # | Construcción (archivo P2) | Mensaje del flujo (log : línea) | Reemplazo en el Proyecto 3 |
|---|---|---|---|
| 1 | Primitiva iCE40 `SB_RAM40_4K` en el register file (`espino_register_file.v:22`, `:33`) | `%Error-MODMISSING: ... Cannot find file containing module: 'SB_RAM40_4K'`, en `E1_p2_original_verilator-lint.log:1` y `:13` | `rtl/espino_register_file.v`: 15 × 32 flip-flops con reset a 0 y lectura síncrona (se mantiene la latencia de 1 ciclo y el handshake `rf_ready`) |
| 2 | `initial $readmemh(MemFile, mem)` (`pochoco_ram.v:36`) | `ERROR: Can not open file 'sw/game.hex' for \$readmemh.`, en `E2_p2_original_yosys-jsonheader.log:406` | El assembler genera `sw/build/game_program.vh` (`game_word()`), que se sintetiza como ROM combinacional (`pochoco_rom.v`) o como valores de reset de los FF (`pochoco_ram_ff.v`) |
| 3 | BRAM inferida de 512 × 32 (`pochoco_ram.v`, `NumWords = 512`) | GF180 no tiene BRAM: `Mapping memory \u_pochoco.u_ram.mem ... created 512 $dff cells ... of width 32` (`E4_p2_step3_yosys-synthesis.log:1476-1477`), con 16.468 `dffq_1` y un área de celdas de **2.328.951 µm²** (`E4_p2_step3_stat.rpt:24`, `:50`) | Memoria dimensionada al uso real: 136 palabras de programa + 4 de datos (el juego usa 0) |
| 4 | Valor inicial del power-on reset `reg [19:0] por_cnt = 20'b0` (`pochoco_soc.v:32`) | `%Warning-PROCASSINIT: ... 'por_cnt'`, en `E3_p2_step2_verilator-lint.log:1`. Yosys lo registra como atributo `init` (`E4_..._yosys-synthesis.log:297`) | Puerto externo `rst_n` en `asic_top` + sincronizador de 2 FF (aserción asíncrona, liberación síncrona) en `pochoco_soc.v` |
| 5 | Valores iniciales de la memoria (contenido de `$readmemh`) y de `por_cnt` en FF sin reset | **Sin mensaje**: `dfflegalize` (`E4_..._yosys-synthesis.log`, paso 154.1) mapea a `dffq_1`, que no tienen valor inicial, y el atributo `init` se descarta en silencio | Todo estado que debe tener un valor conocido al arrancar usa reset (los FF de la memoria unificada se resetean al programa) |
| 6 | Suposición sobre el reloj: constantes de `game.s` para 25 MHz | **Sin mensaje**: el flujo no sabe qué significan las constantes | `game.s` con `.equ CLK_HZ, 10000000` y constantes derivadas (sección 3.4) |
| 7 | Displays activos en bajo (`assign ... = ~seg1`, propio de la Go Board) | **Sin mensaje** (es lógica válida) | `asic_top` entrega segmentos lógicos (1 = encendido); la polaridad la decide el pad/placa |
| 8 | Reset de 2^20 ciclos pensado para esperar a que las BRAM de la iCE40 estén listas | **Sin mensaje** | Ya no hace falta: no hay BRAM que configurar; el reset lo controla el pin externo |

Por qué 5–8 seguían siendo un problema aunque el flujo no avisara:
* **5**: un flip-flop de silicio no tiene un estado definido al encender. El chip arrancaría
  con un programa aleatorio y un contador de reset arbitrario, que podría no llegar nunca
  a liberar la CPU. La FPGA sí inicializa los FF y las BRAM desde el bitstream.
* **6**: con T = 100 ns, las constantes de 25 MHz harían que la espera durara 7,5 s en vez de 3 s,
  y que todos los tiempos mostrados quedaran divididos por 2,5 (una décima real son
  1.000.000 de ciclos, pero el programa contaría 2.500.000 por décima).
* **7**: la polaridad depende del display y del driver de pad. Un macro debe exponer funciones lógicas.
* **8**: un contador de 20 bits (+ comparador) gastaría área solo para cubrir una limitación de la FPGA.

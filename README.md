# Proyecto 3 – Pochoco SoC: de RTL a GDSII (LibreLane + GF180MCU)

Integrantes: Constanza Bustamante, Elena Durán y Mario Messen.

Punto de partida: el repositorio del Proyecto 2 (RTL modificado, `game.s` y
assembler propio). El juego de reflejos sobre Espino (RV32E) se lleva de la FPGA
(iCE40, Go Board) a un **macro digital de celdas estándar** en GF180MCU. Los
puertos de `asic_top` son terminales del macro, no pads de I/O.

## Versiones exactas (corrida final)

| Elemento | Versión |
|---|---|
| LibreLane | **3.0.17**, flake `github:librelane/librelane/64ef80802d3d189b476636d2a6b17888c03304ee` |
| PDK | **gf180mcuD**, open_pdks `54435919abffb937387ec956209f9cf5fd2dfbee` (descargado por ciel en `~/.ciel`) |
| Biblioteca de celdas | **gf180mcu_fd_sc_mcu7t5v0** (7 tracks, 5 V) |
| Herramientas del flujo (dentro del closure de Nix) | Yosys, OpenROAD 2026-02-17, KLayout 0.30.7, Magic, Netgen, Verilator, Icarus Verilog |
| Python (assembler y scripts) | ≥ 3.10 |

## Estructura

| Ruta | Contenido |
|---|---|
| `rtl/` | RTL para ASIC. `asic_top.v` (macro), `pochoco_soc.v`, núcleo Espino, periféricos y las dos estrategias de memoria |
| `rtl/pochoco_rom.v`, `rtl/pochoco_dram.v` | Estrategia 1: ROM combinacional generada desde `game.s` + RAM reducida (`MEM_ROM`) |
| `rtl/pochoco_ram_ff.v` | Estrategia 2: memoria unificada de flip-flops cuya imagen de reset es el programa (`MEM_UNIFIED_FF`) |
| `rtl/pochoco_cycle_counter.v` | Contador de ciclos del Proyecto 2, en un módulo propio para medir su área |
| `sw/game.s` | Juego. Constantes derivadas de `CLK_HZ` (10 MHz = 100 ns) |
| `sw/game_25mhz_p2.s` | Versión del Proyecto 2 (25 MHz), como referencia |
| `sw/build/` | Generado: `game.hex`, `game.symbols`, `game_program.vh` (ROM en Verilog) |
| `sw/build_sim/` | Generado con `-D CLK_HZ=2000` para simulación (3 s → 6000 ciclos) |
| `tools/assembler.py` | Assembler extendido con `.equ`, `li`, `-D` y `--verilog` |
| `tests/` | Pruebas unitarias del assembler |
| `tb/tb_game.v` | Testbench común para RTL y netlist post-síntesis |
| `librelane/{rom,rom_opt,ff}/config.json` | Configuraciones del flujo. `rom_opt` agrega el cambio de la ruta crítica (`OPT_PERIPH_READ`) |
| `librelane/pin_order.cfg` | Ubicación de los terminales del macro |
| `librelane/p2_*` y `p2_reference/` | Evidencia de la sección 3.1: el RTL del Proyecto 2 pasado por LibreLane |
| `scripts/` | `run.sh`, `sweep.sh`, `gate_sim.sh`, `collect.py`, `synth_report.py` |
| `results/` | Resúmenes generados desde las corridas (`runs.csv`, `runs.md`, `synth_*.md`) |
| `docs/` | Informe |

## 1. Instalar LibreLane (Linux o WSL2 en Windows)

LibreLane se distribuye con Nix. En Ubuntu (o Ubuntu en WSL2 con systemd):

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon --yes
# cerrar y abrir la terminal
echo "extra-experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf
echo "extra-substituters = https://nix-cache.fossi-foundation.org" | sudo tee -a /etc/nix/nix.conf
echo "extra-trusted-public-keys = nix-cache.fossi-foundation.org:3+K59iFwXqKsL7BNu6Guy0v+uTlwsxYQxjspXzqLYQs=" | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon
nix shell github:librelane/librelane/64ef80802d3d189b476636d2a6b17888c03304ee --command librelane --version   # LibreLane v3.0.17
```

La primera vez descarga las herramientas (varios GB). Los scripts usan
`librelane` si está en el `PATH`; si no, lo ejecutan con `nix shell` fijado a la
misma revisión (`scripts/env.sh`). El PDK lo descarga ciel automáticamente
(`~/.ciel`) en la primera corrida.

> En WSL, copiar el repositorio al sistema de archivos de Linux (`~/`), no a
> `/mnt/c`: el flujo es mucho más rápido.

## 2. Regenerar el programa desde `game.s`

```bash
python3 tools/assembler.py sw/game.s -o sw/build/game.hex \
    --symbols sw/build/game.symbols --verilog sw/build/game_program.vh
python3 -m unittest tests.test_assembler          # 21 pruebas
```

`sw/build/game_program.vh` define `GAME_WORDS` y la función `game_word(idx)`.
La síntesis la convierte en la ROM (estrategia 1) o en los valores de reset de
los flip-flops de la memoria (estrategia 2). Cualquier cambio en `game.s` llega
al silicio con solo regenerar este archivo y volver a correr el flujo.

Extensiones del assembler:

* `.equ NOMBRE, expresión`: constantes con nombre (`+ - * / % ( )`, `/` es división entera).
* `li rd, expresión`: siempre `lui` + `addi` (2 palabras), así el tamaño del programa no depende de las constantes.
* `-D NOMBRE=valor`: sobrescribe un `.equ`. Con `-D CLK_HZ=25000000` la salida
  es idéntica bit a bit al `game.hex` del Proyecto 2 (lo verifica una prueba).

## 3. Ejecutar la corrida final

```bash
scripts/run.sh rom final            # estrategia 1, T = 100 ns, U = 40 %
scripts/run.sh ff  final            # estrategia 2
python3 scripts/collect.py          # resumen de todas las corridas -> results/runs.{csv,md}
python3 scripts/synth_report.py rom final   # 5 celdas más usadas, área por módulo
```

Los resultados quedan en `librelane/<diseño>/runs/<tag>/` (`final/gds/asic_top.gds`,
`final/metrics.json` y los reportes de cada paso).

Barridos (secciones 3.2, 3.4 y 3.5):

```bash
scripts/sweep.sh period rom 80 70 65 60 55     # CLOCK_PERIOD con U = 40 %
scripts/sweep.sh util   rom 30 50 60 70        # FP_CORE_UTIL con T = 100 ns
```

## 4. Simulaciones

Solo RTL (Icarus Verilog, cualquier sistema operativo):

```bash
python3 tools/assembler.py sw/game.s -o sw/build_sim/game.hex -D CLK_HZ=2000 --verilog sw/build_sim/game_program.vh
iverilog -g2005 -DMEM_ROM -I sw/build_sim -o tb/out/rtl.vvp rtl/*.v tb/tb_game.v
vvp -n tb/out/rtl.vvp +LOG=tb/out/rtl.log
```

RTL vs netlist post-síntesis (sección 3.7, requiere LibreLane y el PDK):

```bash
scripts/gate_sim.sh rom      # o ff
```

Sintetiza `asic_top` con el programa ensamblado con `CLK_HZ=2000` (0,1 s = 200
ciclos, 3 s = 6000 ciclos), simula el RTL y el netlist (modelos de celdas GF180
con `-DFUNCTIONAL`, sin retardos) con el mismo testbench y los mismos estímulos,
y compara línea a línea los logs: puertos de salida y ciclos medidos por el
programa.

## Terminales del macro

| Borde | Terminales | Motivo |
|---|---|---|
| Oeste | `clk`, `rst_n` | Reloj y reset entran juntos por un lado, cortos y separados de las E/S |
| Sur | `btn[3:0]` | Entradas del usuario |
| Norte | `led[3:0]`, `seg1[6:0]`, `seg2[6:0]` | Salidas visibles para el usuario, agrupadas |
| Este | `spi_sclk`, `spi_mosi`, `spi_cs_n`, `spi_miso` | El bus SPI se mantiene junto |

Son terminales lógicos en metal: no incluyen protección ESD, cambio de nivel ni
capacidad de corriente. En un chip completo cada uno se conectaría a una celda
pad de I/O de GF180MCU (por ejemplo `gf180mcu_fd_io__bi_24t`) en el anillo de pads.

## Mapa de memoria

| Dirección | Uso |
|---|---|
| `0x00000000`–`0x0000021F` | Programa (136 palabras; ROM o memoria unificada) |
| RAM de datos | `MEM_ROM`: 4 palabras, solo por el puerto de datos (Harvard). `MEM_UNIFIED_FF`: palabras 136–139 de la memoria unificada |
| `0x80000000` | Display (2 dígitos BCD) |
| `0x80000004` | LEDs (escribir un valor one-hot captura la marca de tiempo) |
| `0x80000008` | Botones |
| `0x8000000C` | Contador de ciclos |
| `0x80000010` | Marca de tiempo del objetivo |

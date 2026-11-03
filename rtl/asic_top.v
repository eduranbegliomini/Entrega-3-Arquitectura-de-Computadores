// Copyright 2026 Universidad de los Andes.
// SPDX-License-Identifier: SHL-0.51
//
// Proyecto 3: top-level of the hard macro. It only instantiates the SoC and
// contains nothing FPGA-specific (no PLL, no BRAM, no pin constraints, no
// board polarity). Its ports are *macro terminals* with logical meaning;
// in a full chip each one would connect to an I/O pad cell (ESD protection,
// level shifting and drive strength for LEDs/displays), which is not part of
// this macro.
//
//   clk        system clock, CLOCK_PERIOD = 100 ns (10 MHz)
//   rst_n      asynchronous active-low reset (synchronised inside the SoC)
//   btn[3:0]   push buttons, 1 = pressed (synchronised inside u_periph)
//   led[3:0]   LEDs, 1 = on
//   seg1[6:0]  tens digit,  {g,f,e,d,c,b,a}, 1 = segment on
//   seg2[6:0]  units digit, {g,f,e,d,c,b,a}, 1 = segment on
//   spi_*      SPI slave (SCLK, MOSI, CS_n in; MISO out)

module asic_top (
  input  wire       clk,
  input  wire       rst_n,
  input  wire [3:0] btn,
  output wire [3:0] led,
  output wire [6:0] seg1,
  output wire [6:0] seg2,
  input  wire       spi_sclk,
  input  wire       spi_mosi,
  input  wire       spi_cs_n,
  output wire       spi_miso
);

  pochoco_soc u_soc (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .led_o      (led),
    .btn_i      (btn),
    .seg1_o     (seg1),
    .seg2_o     (seg2),
    .spi_sclk_i (spi_sclk),
    .spi_mosi_i (spi_mosi),
    .spi_cs_ni  (spi_cs_n),
    .spi_miso_o (spi_miso)
  );

endmodule

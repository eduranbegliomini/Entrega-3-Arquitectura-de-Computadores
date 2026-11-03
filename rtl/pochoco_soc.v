// Copyright 2026 Universidad de los Andes.
// Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: SHL-0.51
//
// Course: Arquitectura de Computadores (2026)
//
// Authors:
// - Nicolás Villegas <navillegas@miuandes.cl>
//
// Proyecto 3 (ASIC) changes with respect to Proyecto 2:
//  * The power-on reset counter `reg [19:0] por_cnt = 20'b0` relied on the
//    FPGA configuration to initialise the register. Silicon flops power up in
//    an unknown state, so reset now comes from an external active-low pin
//    (rst_ni) through a synchroniser: asynchronous assertion, synchronous
//    release (no recovery/removal hazard on the ~800 async-reset flops).
//  * pochoco_ram ($readmemh + inferred BRAM) is replaced by one of two memory
//    strategies, selected with a Verilog define:
//      MEM_ROM        (default) combinational ROM + reduced FF data RAM
//      MEM_UNIFIED_FF unified flip-flop memory whose reset image is the program
//  * The seven-segment outputs are logical (1 = segment on). The active-low
//    inversion belonged to the Go Board and is left to the pad ring/board.

module pochoco_soc #(
  parameter integer DataWords = 4   // game.s uses 0 RAM words; small margin
) (
  input  wire       clk_i,
  input  wire       rst_ni,
  output wire [3:0] led_o,
  input  wire [3:0] btn_i,
  output wire [6:0] seg1_o,
  output wire [6:0] seg2_o,
  input  wire       spi_sclk_i,
  input  wire       spi_mosi_i,
  input  wire       spi_cs_ni,
  output wire       spi_miso_o
);
  wire clk = clk_i;

  // Reset synchroniser: assert asynchronously, release on a clock edge.
  reg [1:0] rst_sync_q;
  always @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) rst_sync_q <= 2'b00;
    else         rst_sync_q <= {rst_sync_q[0], 1'b1};
  end
  wire rst_n = rst_sync_q[1];

  wire        instr_req;
  wire [31:0] instr_addr, instr_rdata;
  wire        data_req, data_we;
  wire [3:0]  data_be;
  wire [31:0] data_addr, data_wdata, data_rdata;

  espino_core #(.BootAddr(32'h0000_0000)) u_core (
    .clk_i(clk), .rst_ni(rst_n),
    .instr_req_o(instr_req), .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata),
    .data_req_o(data_req), .data_we_o(data_we), .data_be_o(data_be),
    .data_addr_o(data_addr), .data_wdata_o(data_wdata), .data_rdata_i(data_rdata)
  );

  wire is_mmio = data_addr[31];
  wire per_sel = is_mmio & ~data_addr[16];
  wire spi_sel = is_mmio &  data_addr[16];
  wire ram_b_req = data_req & ~is_mmio;
  wire per_req   = data_req &  per_sel;
  wire spi_req   = data_req &  spi_sel;

  wire [31:0] ram_b_rdata, per_rdata, spi_rdata;
  reg rd_is_per, rd_is_spi;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rd_is_per <= 1'b0; rd_is_spi <= 1'b0; end
    else if (data_req & ~data_we) begin
      rd_is_per <= per_sel;
      rd_is_spi <= spi_sel;
    end
  end
  assign data_rdata = rd_is_per ? per_rdata : rd_is_spi ? spi_rdata : ram_b_rdata;

`ifdef MEM_UNIFIED_FF
  pochoco_ram_ff #(.DataWords(DataWords)) u_mem (
    .clk_i(clk), .rst_ni(rst_n),
    .a_req_i(instr_req), .a_addr_i(instr_addr), .a_rdata_o(instr_rdata),
    .b_req_i(ram_b_req), .b_we_i(data_we), .b_be_i(data_be), .b_addr_i(data_addr),
    .b_wdata_i(data_wdata), .b_rdata_o(ram_b_rdata)
  );
`else
  pochoco_rom u_rom (
    .clk_i(clk), .rst_ni(rst_n),
    .req_i(instr_req), .addr_i(instr_addr), .rdata_o(instr_rdata)
  );

  pochoco_dram #(.NumWords(DataWords)) u_dram (
    .clk_i(clk), .rst_ni(rst_n),
    .req_i(ram_b_req), .we_i(data_we), .be_i(data_be), .addr_i(data_addr),
    .wdata_i(data_wdata), .rdata_o(ram_b_rdata)
  );
`endif

  pochoco_periph u_periph (
    .clk_i(clk), .rst_ni(rst_n), .sel_i(per_sel), .req_i(per_req), .we_i(data_we),
    .addr_i(data_addr[7:0]), .wdata_i(data_wdata), .rdata_o(per_rdata),
    .leds_o(led_o), .btn_i(btn_i), .seg1_o(seg1_o), .seg2_o(seg2_o)
  );

  pochoco_spi_slave u_spi (
    .clk_i(clk), .rst_ni(rst_n), .sel_i(spi_sel), .req_i(spi_req), .we_i(data_we),
    .addr_i(data_addr[7:0]), .wdata_i(data_wdata), .rdata_o(spi_rdata),
    .spi_sclk_i(spi_sclk_i), .spi_mosi_i(spi_mosi_i), .spi_cs_n_i(spi_cs_ni),
    .spi_miso_o(spi_miso_o)
  );
endmodule

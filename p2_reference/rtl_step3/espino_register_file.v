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
// Proyecto 3 (ASIC): the Proyecto 2 version instantiated four iCE40
// SB_RAM40_4K blocks (two banks, one per read port). Those primitives do not
// exist in GF180MCU, so the register file is now 15 x 32 flip-flops (x0 is
// hard-wired to zero). Reads stay *synchronous* (registered on every clock,
// like the BRAM with RE = 1) so the ID-stage rf_ready handshake and the cycle
// count of every instruction are unchanged. Registers reset to zero, which
// reproduces the INIT_0 = 0 contents the BRAMs had after configuration.

module espino_register_file (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire [3:0]  raddr_a_i,
  output reg  [31:0] rdata_a_o,
  input  wire [3:0]  raddr_b_i,
  output reg  [31:0] rdata_b_o,
  input  wire [3:0]  waddr_i,
  input  wire [31:0] wdata_i,
  input  wire        we_i
);

  wire [31:0] regs [0:15];
  assign regs[0] = 32'b0;

  genvar g;
  generate
    for (g = 1; g < 16; g = g + 1) begin : g_reg
      reg [31:0] q;
      always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)                         q <= 32'b0;
        else if (we_i && waddr_i == g)       q <= wdata_i;
      end
      assign regs[g] = q;
    end
  endgenerate

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_a_o <= 32'b0;
      rdata_b_o <= 32'b0;
    end else begin
      rdata_a_o <= regs[raddr_a_i];
      rdata_b_o <= regs[raddr_b_i];
    end
  end

endmodule

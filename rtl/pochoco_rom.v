// Copyright 2026 Universidad de los Andes.
// SPDX-License-Identifier: SHL-0.51
//
// Strategy 1 (MEM_ROM): instruction memory as a combinational ROM generated
// by tools/assembler.py (--verilog) from sw/game.s. Synthesis turns the
// game_word() case statement into logic gates: there is nothing to load at
// power-up. The output register keeps the one-cycle fetch latency that the
// Espino IF stage expects (same contract as the Proyecto 2 BRAM).

module pochoco_rom (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        req_i,
  input  wire [31:0] addr_i,
  output reg  [31:0] rdata_o
);

`include "game_program.vh"

  wire [GAME_ADDR_BITS-1:0] word = addr_i[GAME_ADDR_BITS+1:2];

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)    rdata_o <= 32'b0;
    else if (req_i) rdata_o <= game_word(word);
  end

endmodule

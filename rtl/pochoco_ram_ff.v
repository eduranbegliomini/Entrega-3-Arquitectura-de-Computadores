// Copyright 2026 Universidad de los Andes.
// SPDX-License-Identifier: SHL-0.51
//
// Strategy 2 (MEM_UNIFIED_FF): unified instruction + data memory built from
// flip-flops, sized to the real use of the game: GAME_WORDS program words
// (from the assembler) followed by DataWords data words. Silicon has no
// $readmemh, so the program is the *reset value* of the flip-flops: each bit
// becomes a reset-to-0 or set-to-1 flop according to game_word(). Every reset
// reloads the program. Same two-port contract as the Proyecto 2 pochoco_ram:
// port A fetches (registered, gated by req), port B loads/stores with byte
// enables and a registered read.

module pochoco_ram_ff #(
  parameter integer DataWords = 16
) (
  input  wire        clk_i,
  input  wire        rst_ni,

  // Port A: instruction
  input  wire        a_req_i,
  input  wire [31:0] a_addr_i,
  output reg  [31:0] a_rdata_o,

  // Port B: data
  input  wire        b_req_i,
  input  wire        b_we_i,
  input  wire [3:0]  b_be_i,
  input  wire [31:0] b_addr_i,
  input  wire [31:0] b_wdata_i,
  output reg  [31:0] b_rdata_o
);

`include "game_program.vh"

  localparam integer NumWords = GAME_WORDS + DataWords;
  localparam integer AddrW    = $clog2(NumWords);

  wire [AddrW-1:0] a_word = a_addr_i[AddrW+1:2];
  wire [AddrW-1:0] b_word = b_addr_i[AddrW+1:2];
  wire [31:0] words [0:NumWords-1];

  genvar g;
  generate
    for (g = 0; g < NumWords; g = g + 1) begin : g_word
      reg [31:0] q;
      wire sel = b_req_i & b_we_i & (b_word == g);
      always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) q <= game_word(g);
        else if (sel) begin
          if (b_be_i[0]) q[7:0]   <= b_wdata_i[7:0];
          if (b_be_i[1]) q[15:8]  <= b_wdata_i[15:8];
          if (b_be_i[2]) q[23:16] <= b_wdata_i[23:16];
          if (b_be_i[3]) q[31:24] <= b_wdata_i[31:24];
        end
      end
      assign words[g] = q;
    end
  endgenerate

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)      a_rdata_o <= 32'b0;
    else if (a_req_i) a_rdata_o <= (a_word < NumWords) ? words[a_word] : 32'b0;
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) b_rdata_o <= 32'b0;
    else         b_rdata_o <= (b_word < NumWords) ? words[b_word] : 32'b0;
  end

endmodule

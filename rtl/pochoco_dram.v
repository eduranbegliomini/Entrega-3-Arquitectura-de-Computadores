// Copyright 2026 Universidad de los Andes.
// SPDX-License-Identifier: SHL-0.51
//
// Strategy 1 (MEM_ROM): reduced data RAM made of flip-flops, reached only
// through the data port (Harvard split: loads/stores to addresses below
// 0x80000000 go here, instruction fetches go to pochoco_rom). Byte enables
// and the one-cycle read latency match the Proyecto 2 pochoco_ram port B.

module pochoco_dram #(
  parameter integer NumWords = 16
) (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        req_i,
  input  wire        we_i,
  input  wire [3:0]  be_i,
  input  wire [31:0] addr_i,
  input  wire [31:0] wdata_i,
  output reg  [31:0] rdata_o
);

  localparam integer AddrW = (NumWords > 1) ? $clog2(NumWords) : 1;

  wire [AddrW-1:0] word = addr_i[AddrW+1:2];
  wire [31:0] words [0:NumWords-1];

  genvar g;
  generate
    for (g = 0; g < NumWords; g = g + 1) begin : g_word
      reg [31:0] q;
      wire sel = req_i & we_i & (word == g);
      always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) q <= 32'b0;
        else if (sel) begin
          if (be_i[0]) q[7:0]   <= wdata_i[7:0];
          if (be_i[1]) q[15:8]  <= wdata_i[15:8];
          if (be_i[2]) q[23:16] <= wdata_i[23:16];
          if (be_i[3]) q[31:24] <= wdata_i[31:24];
        end
      end
      assign words[g] = q;
    end
  endgenerate

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rdata_o <= 32'b0;
    else         rdata_o <= (word < NumWords) ? words[word] : 32'b0;
  end

endmodule

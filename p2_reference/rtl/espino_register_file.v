// Copyright 2026 Universidad de los Andes.
// Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: SHL-0.51
//
// Course: Arquitectura de Computadores (2026)
// 
// Authors:
// - Nicolás Villegas <navillegas@miuandes.cl>

module espino_regbank32 (
  input  wire        clk_i,
  input  wire [3:0]  raddr_i,
  output wire [31:0] rdata_o,
  input  wire [3:0]  waddr_i,
  input  wire [31:0] wdata_i,
  input  wire        we_i
);
  wire [10:0] ra = {7'b0, raddr_i};
  wire [10:0] wa = {7'b0, waddr_i};

  SB_RAM40_4K #(
    .READ_MODE(0), .WRITE_MODE(0),
    .INIT_0(256'h0)
  ) u_lo (
    .RDATA (rdata_o[15:0]),
    .RADDR (ra), .RCLK (clk_i), .RCLKE (1'b1), .RE (1'b1),
    .WDATA (wdata_i[15:0]),
    .WADDR (wa), .WCLK (clk_i), .WCLKE (1'b1), .WE (we_i),
    .MASK  (16'h0000)
  );

  SB_RAM40_4K #(
    .READ_MODE(0), .WRITE_MODE(0),
    .INIT_0(256'h0)
  ) u_hi (
    .RDATA (rdata_o[31:16]),
    .RADDR (ra), .RCLK (clk_i), .RCLKE (1'b1), .RE (1'b1),
    .WDATA (wdata_i[31:16]),
    .WADDR (wa), .WCLK (clk_i), .WCLKE (1'b1), .WE (we_i),
    .MASK  (16'h0000)
  );
endmodule

module espino_register_file (
  input  wire        clk_i,
  input  wire        rst_ni,     // unused
  input  wire [3:0]  raddr_a_i,
  output wire [31:0] rdata_a_o,
  input  wire [3:0]  raddr_b_i,
  output wire [31:0] rdata_b_o,
  input  wire [3:0]  waddr_i,
  input  wire [31:0] wdata_i,
  input  wire        we_i
);
  wire wr = we_i & (waddr_i != 4'd0);

  espino_regbank32 u_bankA (   // serves read port A
    .clk_i (clk_i),
    .raddr_i (raddr_a_i), .rdata_o (rdata_a_o),
    .waddr_i (waddr_i), .wdata_i (wdata_i), .we_i (wr)
  );

  espino_regbank32 u_bankB (   // serves read port B
    .clk_i (clk_i),
    .raddr_i (raddr_b_i), .rdata_o (rdata_b_o),
    .waddr_i (waddr_i), .wdata_i (wdata_i), .we_i (wr)
  );

  // rst_ni intentionally unused
  wire _unused = &{1'b0, rst_ni};
endmodule
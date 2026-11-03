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
// This is a WORK IN PROGRESS module. It is provided "AS IS", without warranty of any kind.

module pochoco_spi_slave (
  input  wire        clk_i,
  input  wire        rst_ni,

  input  wire        sel_i,
  input  wire        req_i,
  input  wire        we_i,
  input  wire [7:0]  addr_i,
  input  wire [31:0] wdata_i,
  output reg  [31:0] rdata_o,

  input  wire        spi_sclk_i,
  input  wire        spi_mosi_i,
  input  wire        spi_cs_n_i,
  output wire        spi_miso_o
);

  // Register offsets
  localparam [5:0] REG_STATUS   = 6'd0,
                   REG_PRICE    = 6'd1,
                   REG_DECISION = 6'd2;

  wire [5:0] off    = addr_i[7:2];
  wire       access = sel_i & req_i;
  wire       rd     = access & ~we_i;
  wire       wr     = access &  we_i;

  reg [2:0] sclk_sync, mosi_sync, cs_sync;
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sclk_sync <= 3'b000;
      mosi_sync <= 3'b000;
      cs_sync   <= 3'b111;
    end else begin
      sclk_sync <= {sclk_sync[1:0], spi_sclk_i};
      mosi_sync <= {mosi_sync[1:0], spi_mosi_i};
      cs_sync   <= {cs_sync[1:0],   spi_cs_n_i};
    end
  end

  wire sclk_r    =  sclk_sync[1] & ~sclk_sync[2];
  wire sclk_f    = ~sclk_sync[1] &  sclk_sync[2];
  wire mosi      =  mosi_sync[1];
  wire cs_active = ~cs_sync[1];
  wire cs_assert = ~cs_sync[1] &  cs_sync[2];

  // Shift engine
  reg [7:0] rx_shift;
  reg [7:0] tx_shift;
  reg [3:0] bit_cnt;
  reg [7:0] tx_hold;
  reg [7:0] price_q;
  reg       new_price_q;

  wire byte_done = sclk_r & (bit_cnt == 4'd7);

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_shift <= 8'h00;
      tx_shift <= 8'h00;
      bit_cnt  <= 4'd0;
    end else if (cs_assert) begin
      tx_shift <= tx_hold;
      bit_cnt  <= 4'd0;
    end else if (cs_active) begin
      if (sclk_r) begin
        rx_shift <= {rx_shift[6:0], mosi};
        bit_cnt  <= bit_cnt + 4'd1;
      end
      if (sclk_f) begin
        tx_shift <= {tx_shift[6:0], 1'b0};
      end
    end
  end

  assign spi_miso_o = cs_active ? tx_shift[7] : 1'b0;

  // PRICE latch
  wire price_read = rd & (off == REG_PRICE);
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      price_q     <= 8'h00;
      new_price_q <= 1'b0;
    end else begin
      if (byte_done)       price_q     <= {rx_shift[6:0], mosi};
      if (byte_done)       new_price_q <= 1'b1;
      else if (price_read) new_price_q <= 1'b0;
    end
  end

  // CPU writes DECISION byte
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                          tx_hold <= 8'h00;
    else if (wr & (off == REG_DECISION))  tx_hold <= wdata_i[7:0];
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rdata_o <= 32'b0;
    else if (rd) begin
      case (off)
        REG_STATUS: rdata_o <= {30'b0, cs_active, new_price_q};
        REG_PRICE:  rdata_o <= {24'b0, price_q};
        default:    rdata_o <= 32'b0;
      endcase
    end
  end

endmodule

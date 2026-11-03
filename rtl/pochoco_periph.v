// Copyright 2026 Universidad de los Andes.
// Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: SHL-0.51
//
// Course: Arquitectura de Computadores (2026)
//
// Authors:
// - Nicolás Villegas <navillegas@miuandes.cl>

// Pochoco peripherals, with a memory-mapped cycle counter (Proyecto 2).
// Proyecto 3: the counter and target timestamp live in pochoco_cycle_counter.
module pochoco_periph (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        sel_i,
  input  wire        req_i,
  input  wire        we_i,
  input  wire [7:0]  addr_i,
  input  wire [31:0] wdata_i,
  output reg  [31:0] rdata_o,
  output wire [3:0]  leds_o,
  input  wire [3:0]  btn_i,
  output wire [6:0]  seg1_o,
  output wire [6:0]  seg2_o
);

  wire [5:0] off    = addr_i[7:2];
  wire       access = sel_i & req_i;

  // MMIO word offsets: 0x00 display, 0x04 LEDs, 0x08 buttons,
  // 0x0C free-running 32-bit cycle counter, 0x10 target-start timestamp.
  // Synchronize asynchronous push-button inputs to the system clock. This is
  // a two-flop synchronizer, not a mechanical debounce filter.
  reg [3:0] btn_meta_q, btn_sync_q;
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      btn_meta_q <= 4'b0;
      btn_sync_q <= 4'b0;
    end else begin
      btn_meta_q <= btn_i;
      btn_sync_q <= btn_meta_q;
    end
  end

  // Capture the counter on the same edge that presents a one-hot LED target.
  wire led_write = access & we_i & (off == 6'd1);
  reg  one_hot;
  always @* begin
    case (wdata_i[3:0])
      4'b0001, 4'b0010, 4'b0100, 4'b1000: one_hot = 1'b1;
      default:                            one_hot = 1'b0;
    endcase
  end

  wire [31:0] cycle_count, target_start;
  pochoco_cycle_counter u_cycle_counter (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .capture_i      (led_write & one_hot),
    .count_o        (cycle_count),
    .target_start_o (target_start)
  );

  reg [3:0] led_q;
  reg [7:0] digit_q;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      led_q   <= 4'b0;
      digit_q <= 8'b0;
    end else if (access & we_i) begin
      case (off)
        6'd0: digit_q <= wdata_i[7:0];
        6'd1: led_q   <= wdata_i[3:0];
        default: ;
      endcase
    end
  end

  assign leds_o = led_q;

  function [6:0] hex2seg;
    input [3:0] hex;
    begin
      case (hex)
        4'h0: hex2seg = 7'b0111111;
        4'h1: hex2seg = 7'b0000110;
        4'h2: hex2seg = 7'b1011011;
        4'h3: hex2seg = 7'b1001111;
        4'h4: hex2seg = 7'b1100110;
        4'h5: hex2seg = 7'b1101101;
        4'h6: hex2seg = 7'b1111101;
        4'h7: hex2seg = 7'b0000111;
        4'h8: hex2seg = 7'b1111111;
        4'h9: hex2seg = 7'b1101111;
        4'hA: hex2seg = 7'b1110111;
        4'hB: hex2seg = 7'b1111100;
        4'hC: hex2seg = 7'b0111001;
        4'hD: hex2seg = 7'b1011110;
        4'hE: hex2seg = 7'b1111001;
        4'hF: hex2seg = 7'b1110001;
        default: hex2seg = 7'b0000000;
      endcase
    end
  endfunction

  assign seg1_o = hex2seg(digit_q[7:4]);
  assign seg2_o = hex2seg(digit_q[3:0]);

  // Synchronous read. Since the counter increments on every clock,
  // a read returns the counter value sampled at the access edge.
`ifdef OPT_PERIPH_READ
  // Section 3.4 optimisation: load the read register on every cycle, like the
  // RAM data port. Its D input then depends only on addr[4:2] (the fast low
  // bits of the ALU adder) instead of `access`, which needs bit 31 of the
  // address (end of the carry chain) through the MMIO decode in pochoco_soc.
  // The core reads data_rdata only in the cycle after the access, and
  // rd_is_per still selects this port, so the program sees the same values.
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rdata_o <= 32'b0;
    else begin
      case (off)
        6'd2: rdata_o <= {28'b0, btn_sync_q};
        6'd3: rdata_o <= cycle_count;
        6'd4: rdata_o <= target_start;
        default: rdata_o <= 32'b0;
      endcase
    end
  end
`else
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rdata_o <= 32'b0;
    else if (access & ~we_i) begin
      case (off)
        6'd2: rdata_o <= {28'b0, btn_sync_q};
        6'd3: rdata_o <= cycle_count;
        6'd4: rdata_o <= target_start;
        default: rdata_o <= 32'b0;
      endcase
    end
  end
`endif
endmodule

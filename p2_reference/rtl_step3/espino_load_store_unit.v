// Copyright 2026 Universidad de los Andes.
// Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: SHL-0.51
//
// Course: Arquitectura de Computadores (2026)
// 
// Authors:
// - Nicolás Villegas <navillegas@miuandes.cl>

module espino_load_store_unit (
  input  wire        clk_i,
  input  wire        rst_ni,

  input  wire        req_i,
  input  wire        we_i,
  input  wire [1:0]  type_i,
  input  wire        sign_i,
  input  wire [31:0] addr_i,
  input  wire [31:0] wdata_i,

  output reg  [31:0] rdata_o,
  output wire        busy_o,

  output wire        data_req_o,
  output wire        data_we_o,
  output reg  [3:0]  data_be_o,
  output wire [31:0] data_addr_o,
  output reg  [31:0] data_wdata_o,
  input  wire [31:0] data_rdata_i
);

  localparam [1:0] LSU_BYTE = 2'd0, LSU_HALF = 2'd1, LSU_WORD = 2'd2;

  reg        busy_q, busy_d;
  wire       is_load, is_store;
  wire [1:0] boff;

  assign is_load  = req_i & ~we_i;
  assign is_store = req_i & we_i;
  assign boff     = addr_i[1:0];

  always @* begin
    busy_d = 1'b0;
    if (is_load && !busy_q) busy_d = 1'b1;
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) busy_q <= 1'b0;
    else         busy_q <= busy_d;
  end

  assign busy_o      = is_load & ~busy_q;
  assign data_req_o  = req_i & ~busy_q;
  assign data_we_o   = is_store;
  assign data_addr_o = {addr_i[31:2], 2'b00};

  // Byte-enable mask
  always @* begin
    case (type_i)
      LSU_BYTE: data_be_o = 4'b0001 << boff;
      LSU_HALF: data_be_o = boff[1] ? 4'b1100 : 4'b0011;
      default:  data_be_o = 4'b1111;   
    endcase
  end

  // Store data
  always @* begin
    case (type_i)
      LSU_BYTE: data_wdata_o = {4{wdata_i[7:0]}};
      LSU_HALF: data_wdata_o = {2{wdata_i[15:0]}};
      default:  data_wdata_o = wdata_i;
    endcase
  end

  // Load data
  wire [15:0] lhalf = boff[1] ? data_rdata_i[31:16] : data_rdata_i[15:0];
  wire [7:0]  lbyte = boff[0] ? lhalf[15:8]         : lhalf[7:0];

  always @* begin
    case (type_i)
      LSU_BYTE: rdata_o = {{24{sign_i & lbyte[7]}},  lbyte};
      LSU_HALF: rdata_o = {{16{sign_i & lhalf[15]}}, lhalf};
      default:  rdata_o = data_rdata_i;
    endcase
  end

endmodule
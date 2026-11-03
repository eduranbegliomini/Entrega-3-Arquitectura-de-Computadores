// Copyright 2026 Universidad de los Andes.
// Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: SHL-0.51
//
// Course: Arquitectura de Computadores (2026)
// 
// Authors:
// - Nicolás Villegas <navillegas@miuandes.cl>

module espino_controller (
  input  wire instr_valid_i,
  
  input  wire branch_taken_i,
  input  wire jump_i,

  input  wire lsu_busy_i,
  input  wire rf_ready_i,

  output wire pc_set_o,
  output wire stall_o
);

  wire rf_wait = instr_valid_i & ~rf_ready_i;

  assign stall_o  = rf_wait | lsu_busy_i;

  assign pc_set_o = instr_valid_i & rf_ready_i
                    & ~lsu_busy_i
                    & (branch_taken_i | jump_i);

endmodule
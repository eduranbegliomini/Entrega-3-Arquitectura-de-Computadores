// Copyright 2026 Universidad de los Andes.
// Licensed under the Solderpad Hardware License, Version 0.51 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: SHL-0.51
//
// Course: Arquitectura de Computadores (2026)
// 
// Authors:
// - Nicolás Villegas <navillegas@miuandes.cl>

module espino_decoder (
  input  wire [31:0] instr_i,

  output reg         illegal_insn_o,

  // ALU control
  output reg  [3:0]  alu_operator_o,
  output reg  [1:0]  alu_op_a_sel_o,
  output reg         alu_op_b_sel_o,
  output reg  [31:0] imm_operand_o,
  output reg  [31:0] imm_target_o,

  // Register file write control
  output reg         rf_we_o,
  output reg  [1:0]  rf_wd_sel_o,

  // Control flags
  output reg         is_branch_o,
  output reg         is_jal_o,
  output reg         is_jalr_o,

  // LSU control
  output reg         lsu_req_o,
  output reg         lsu_we_o,
  output reg  [1:0]  lsu_type_o,
  output reg         lsu_sign_o
);

  // --- Local Parameters ---
  
  // Opcodes
  localparam [6:0] 
    OPCODE_LOAD   = 7'h03,
    OPCODE_MISC   = 7'h0f,
    OPCODE_OPIMM  = 7'h13,
    OPCODE_AUIPC  = 7'h17,
    OPCODE_STORE  = 7'h23,
    OPCODE_OP     = 7'h33,
    OPCODE_LUI    = 7'h37,
    OPCODE_BRANCH = 7'h63,
    OPCODE_JALR   = 7'h67,
    OPCODE_JAL    = 7'h6f,
    OPCODE_SYSTEM = 7'h73;

  // ALU operations
  localparam [3:0] 
    ALU_ADD  = 4'd0,
    ALU_SUB  = 4'd1,
    ALU_XOR  = 4'd2,
    ALU_OR   = 4'd3,
    ALU_AND  = 4'd4,
    ALU_SLL  = 4'd5,
    ALU_SRL  = 4'd6,
    ALU_SRA  = 4'd7,
    ALU_SLT  = 4'd8,
    ALU_SLTU = 4'd9,
    ALU_EQ   = 4'd10,
    ALU_NE   = 4'd11,
    ALU_LT   = 4'd12,
    ALU_GE   = 4'd13,
    ALU_LTU  = 4'd14,
    ALU_GEU  = 4'd15;

  // Operand selects
  localparam [1:0] OP_A_REG  = 2'd0, OP_A_PC   = 2'd1, OP_A_ZERO = 2'd2;
  localparam       OP_B_REG  = 1'b0, OP_B_IMM  = 1'b1;

  // Writeback data source
  localparam [1:0] WD_ALU = 2'd0, WD_LSU = 2'd1, WD_PC4 = 2'd2;

  // LSU transfer size
  localparam [1:0] LSU_BYTE = 2'd0, LSU_HALF = 2'd1, LSU_WORD = 2'd2;

  // --- Decoding Logic ---
  wire [6:0] opcode;
  wire [2:0] funct3;
  wire [6:0] funct7;
  assign opcode = instr_i[6:0];
  assign funct3 = instr_i[14:12];
  assign funct7 = instr_i[31:25];

  // Immediate decoders
  wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  assign imm_i = {{20{instr_i[31]}}, instr_i[31:20]};
  assign imm_s = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
  assign imm_b = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                  instr_i[30:25], instr_i[11:8], 1'b0};
  assign imm_u = {instr_i[31:12], 12'b0};
  assign imm_j = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                  instr_i[20], instr_i[30:21], 1'b0};

  always @* begin
    illegal_insn_o = 1'b0;
    alu_operator_o = ALU_ADD;
    alu_op_a_sel_o = OP_A_REG;
    alu_op_b_sel_o = OP_B_IMM;
    imm_operand_o  = imm_i;
    imm_target_o   = imm_b;
    rf_we_o        = 1'b0;
    rf_wd_sel_o    = WD_ALU;
    is_branch_o    = 1'b0;
    is_jal_o       = 1'b0;
    is_jalr_o      = 1'b0;
    lsu_req_o      = 1'b0;
    lsu_we_o       = 1'b0;
    lsu_type_o     = LSU_WORD;
    lsu_sign_o     = 1'b1;

    case (opcode)

      OPCODE_LUI: begin
        alu_op_a_sel_o = OP_A_ZERO;   // rd = 0 + immU
        imm_operand_o  = imm_u;
        rf_we_o        = 1'b1;
      end

      OPCODE_AUIPC: begin
        alu_op_a_sel_o = OP_A_PC;     // rd = pc + immU
        imm_operand_o  = imm_u;
        rf_we_o        = 1'b1;
      end

      OPCODE_OPIMM: begin
        alu_op_a_sel_o = OP_A_REG;
        alu_op_b_sel_o = OP_B_IMM;
        imm_operand_o  = imm_i;
        rf_we_o        = 1'b1;
        case (funct3)
          3'b000: alu_operator_o = ALU_ADD;   // ADDI
          3'b010: alu_operator_o = ALU_SLT;   // SLTI
          3'b011: alu_operator_o = ALU_SLTU;  // SLTIU
          3'b100: alu_operator_o = ALU_XOR;   // XORI
          3'b110: alu_operator_o = ALU_OR;    // ORI
          3'b111: alu_operator_o = ALU_AND;   // ANDI
          3'b001: alu_operator_o = ALU_SLL;   // SLLI
          3'b101: alu_operator_o = funct7[5] ? ALU_SRA : ALU_SRL; // SRAI/SRLI
          default: illegal_insn_o = 1'b1;
        endcase
      end

      OPCODE_OP: begin
        alu_op_a_sel_o = OP_A_REG;
        alu_op_b_sel_o = OP_B_REG;
        rf_we_o        = 1'b1;
        case (funct3)
          3'b000: alu_operator_o = funct7[5] ? ALU_SUB : ALU_ADD;
          3'b001: alu_operator_o = ALU_SLL;
          3'b010: alu_operator_o = ALU_SLT;
          3'b011: alu_operator_o = ALU_SLTU;
          3'b100: alu_operator_o = ALU_XOR;
          3'b101: alu_operator_o = funct7[5] ? ALU_SRA : ALU_SRL;
          3'b110: alu_operator_o = ALU_OR;
          3'b111: alu_operator_o = ALU_AND;
          default: illegal_insn_o = 1'b1;
        endcase
      end

      OPCODE_LOAD: begin
        alu_op_a_sel_o = OP_A_REG;    // address = rs1 + immI
        alu_op_b_sel_o = OP_B_IMM;
        imm_operand_o  = imm_i;
        alu_operator_o = ALU_ADD;
        rf_we_o        = 1'b1;
        rf_wd_sel_o    = WD_LSU;
        lsu_req_o      = 1'b1;
        lsu_we_o       = 1'b0;
        case (funct3)
          3'b000: begin lsu_type_o = LSU_BYTE; lsu_sign_o = 1'b1; end // LB
          3'b001: begin lsu_type_o = LSU_HALF; lsu_sign_o = 1'b1; end // LH
          3'b010: begin lsu_type_o = LSU_WORD; lsu_sign_o = 1'b1; end // LW
          3'b100: begin lsu_type_o = LSU_BYTE; lsu_sign_o = 1'b0; end // LBU
          3'b101: begin lsu_type_o = LSU_HALF; lsu_sign_o = 1'b0; end // LHU
          default: illegal_insn_o = 1'b1;
        endcase
      end

      OPCODE_STORE: begin
        alu_op_a_sel_o = OP_A_REG;    // address = rs1 + immS
        alu_op_b_sel_o = OP_B_IMM;
        imm_operand_o  = imm_s;
        alu_operator_o = ALU_ADD;
        lsu_req_o      = 1'b1;
        lsu_we_o       = 1'b1;
        case (funct3)
          3'b000: lsu_type_o = LSU_BYTE; // SB
          3'b001: lsu_type_o = LSU_HALF; // SH
          3'b010: lsu_type_o = LSU_WORD; // SW
          default: illegal_insn_o = 1'b1;
        endcase
      end

      OPCODE_BRANCH: begin
        alu_op_a_sel_o = OP_A_REG;    // compare rs1, rs2
        alu_op_b_sel_o = OP_B_REG;
        imm_target_o   = imm_b;
        is_branch_o    = 1'b1;
        case (funct3)
          3'b000: alu_operator_o = ALU_EQ;  // BEQ
          3'b001: alu_operator_o = ALU_NE;  // BNE
          3'b100: alu_operator_o = ALU_LT;  // BLT
          3'b101: alu_operator_o = ALU_GE;  // BGE
          3'b110: alu_operator_o = ALU_LTU; // BLTU
          3'b111: alu_operator_o = ALU_GEU; // BGEU
          default: illegal_insn_o = 1'b1;
        endcase
      end

      OPCODE_JAL: begin
        imm_target_o = imm_j;         // pc + immJ
        is_jal_o     = 1'b1;
        rf_we_o      = 1'b1;
        rf_wd_sel_o  = WD_PC4;        // rd = pc + 4
      end

      OPCODE_JALR: begin
        alu_op_a_sel_o = OP_A_REG;    // target = (rs1 + immI) & ~1
        imm_operand_o  = imm_i;
        is_jalr_o      = 1'b1;
        rf_we_o        = 1'b1;
        rf_wd_sel_o    = WD_PC4;
        if (funct3 != 3'b000) illegal_insn_o = 1'b1;
      end

      OPCODE_MISC: begin
        if (funct3 != 3'b000) illegal_insn_o = 1'b1;
      end

      OPCODE_SYSTEM: begin
        if (funct3 != 3'b000) illegal_insn_o = 1'b1;
      end

      default: illegal_insn_o = 1'b1;
    endcase
  end

endmodule
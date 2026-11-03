#!/usr/bin/env python3
"""Small two-pass assembler for the RV32E subset used by this project.

It emits one 32-bit instruction word as eight hexadecimal digits per line and,
for the ASIC flow, a Verilog include (``--verilog``) that describes the program
as a combinational ROM function. It does not invoke an external RISC-V assembler.

Proyecto 3 extensions:
  * ``.equ NAME, expr`` defines a named constant. Expressions may use
    + - * / // % ( ) and previously defined names; '/' is integer division.
  * ``li rd, expr`` always expands to ``lui`` + ``addi`` (two words), so the
    program size does not depend on the constant values.
  * ``-D NAME=expr`` overrides an ``.equ`` from the command line, e.g. to
    shorten the delays for simulation without editing game.s.
  * ``--verilog file.vh`` writes GAME_WORDS and the function game_word(idx),
    used by the ROM (strategy 1) and as the reset image of the unified
    flip-flop memory (strategy 2).
"""
from __future__ import annotations

import argparse
import ast
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

REG_RE = re.compile(r"x(\d+)$", re.IGNORECASE)
MEM_RE = re.compile(r"^(.+)\((x\d+)\)$", re.IGNORECASE)

SUPPORTED = {
    "lui", "addi", "andi", "xori", "add", "sub", "and", "xor",
    "lw", "sw", "beq", "bne", "bltu", "jal"
}
PSEUDO = {"li"}
IGNORED_DIRECTIVES = {".section", ".text", ".global", ".globl", ".type", ".size"}
DEFAULT_MAX_WORDS = 256

class AssemblerError(Exception):
    """Raised for invalid source or an unencodable instruction."""

@dataclass
class SourceInstruction:
    line_no: int
    source: str
    pc: int
    mnemonic: str
    operands: List[str]
    consts: Dict[str, int] = field(default_factory=dict)


def parse_number(value: str, context: str) -> int:
    value = value.strip().replace("_", "")
    try:
        # int(..., 0) handles decimal and 0x/0b prefixes; signed values work too.
        return int(value, 0)
    except ValueError as exc:
        raise AssemblerError(f"{context}: invalid integer literal {value!r}") from exc


_BINOPS = {
    ast.Add: lambda a, b: a + b,
    ast.Sub: lambda a, b: a - b,
    ast.Mult: lambda a, b: a * b,
    ast.Div: lambda a, b: a // b,
    ast.FloorDiv: lambda a, b: a // b,
    ast.Mod: lambda a, b: a % b,
}


def eval_expr(text: str, consts: Dict[str, int], context: str) -> int:
    """Evaluate an integer constant expression over literals and .equ names."""
    text = text.strip()
    if not text:
        raise AssemblerError(f"{context}: empty expression")
    try:
        return parse_number(text, context)
    except AssemblerError:
        pass
    try:
        tree = ast.parse(text, mode="eval")
    except SyntaxError as exc:
        raise AssemblerError(f"{context}: invalid expression {text!r}") from exc

    def ev(node: ast.AST) -> int:
        if isinstance(node, ast.Expression):
            return ev(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, int):
            return node.value
        if isinstance(node, ast.Name):
            if node.id not in consts:
                raise AssemblerError(f"{context}: undefined constant {node.id!r}")
            return consts[node.id]
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
            value = ev(node.operand)
            return -value if isinstance(node.op, ast.USub) else value
        if isinstance(node, ast.BinOp) and type(node.op) in _BINOPS:
            return _BINOPS[type(node.op)](ev(node.left), ev(node.right))
        raise AssemblerError(f"{context}: unsupported expression {text!r}")

    return ev(tree)


def split_li(value: int) -> Tuple[int, int]:
    """Split a 32-bit constant into (lui imm20, addi imm12), as GNU as does."""
    value &= 0xFFFFFFFF
    lo = value & 0xFFF
    if lo >= 0x800:
        lo -= 0x1000
    hi = ((value - lo) >> 12) & 0xFFFFF
    return hi, lo


def parse_reg(token: str, context: str) -> int:
    match = REG_RE.fullmatch(token.strip())
    if not match:
        raise AssemblerError(f"{context}: expected register x0..x15, got {token!r}")
    reg = int(match.group(1))
    if not 0 <= reg <= 15:
        raise AssemblerError(f"{context}: register x{reg} is outside RV32E range x0..x15")
    return reg


def signed_fits(value: int, bits: int) -> bool:
    return -(1 << (bits - 1)) <= value < (1 << (bits - 1))


def enc_i(opcode: int, rd: int, funct3: int, rs1: int, imm: int, context: str) -> int:
    if not signed_fits(imm, 12):
        raise AssemblerError(f"{context}: immediate {imm} does not fit signed 12 bits")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_r(rd: int, rs1: int, rs2: int, funct3: int, funct7: int = 0) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33


def enc_s(rs2: int, rs1: int, imm: int, funct3: int, context: str) -> int:
    if not signed_fits(imm, 12):
        raise AssemblerError(f"{context}: store offset {imm} does not fit signed 12 bits")
    u = imm & 0xFFF
    return (((u >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((u & 0x1F) << 7) | 0x23


def enc_b(rs1: int, rs2: int, offset: int, funct3: int, context: str) -> int:
    if offset & 1:
        raise AssemblerError(f"{context}: branch target offset {offset} must be even")
    if not -(1 << 12) <= offset <= (1 << 12) - 2:
        raise AssemblerError(f"{context}: branch offset {offset} is outside -4096..4094")
    u = offset & 0x1FFF
    return (((u >> 12) & 1) << 31) | (((u >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (((u >> 1) & 0xF) << 8) | (((u >> 11) & 1) << 7) | 0x63


def enc_u(rd: int, imm: int, context: str) -> int:
    # Assembly syntax takes the raw 20-bit immediate, not the byte address.
    if not -(1 << 19) <= imm <= (1 << 20) - 1:
        raise AssemblerError(f"{context}: LUI immediate {imm} does not fit 20 bits")
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | 0x37


def enc_j(rd: int, offset: int, context: str) -> int:
    if offset & 1:
        raise AssemblerError(f"{context}: JAL target offset {offset} must be even")
    if not -(1 << 20) <= offset <= (1 << 20) - 2:
        raise AssemblerError(f"{context}: JAL offset {offset} is outside -1048576..1048574")
    u = offset & 0x1FFFFF
    return (((u >> 20) & 1) << 31) | (((u >> 1) & 0x3FF) << 21) | (((u >> 11) & 1) << 20) | (((u >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def split_operands(text: str) -> List[str]:
    # Current supported syntax has comma-separated operands and no nested expressions.
    return [part.strip() for part in text.split(",")]


def strip_comment(line: str) -> str:
    # '#' is the style used by the supplied .s files. Also accept ';'.
    return line.split("#", 1)[0].split(";", 1)[0].strip()


def parse_source(source: str, defines: Optional[Dict[str, str]] = None) -> Tuple[List[SourceInstruction], Dict[str, int]]:
    instructions: List[SourceInstruction] = []
    labels: Dict[str, int] = {}
    consts: Dict[str, int] = {}
    overrides = dict(defines or {})
    pc = 0
    for line_no, raw in enumerate(source.splitlines(), start=1):
        text = strip_comment(raw)
        if not text:
            continue
        # Allow one or more labels before an instruction/directive.
        while ":" in text:
            left, right = text.split(":", 1)
            label = left.strip()
            if not re.fullmatch(r"[A-Za-z_.$][\w.$]*", label):
                break
            if label in labels:
                raise AssemblerError(f"line {line_no}: duplicate label {label!r}")
            labels[label] = pc
            text = right.strip()
            if not text:
                break
        if not text:
            continue
        if text.startswith("."):
            parts = text.split(None, 1)
            directive = parts[0].lower()
            if directive == ".equ":
                name, _, expr = (parts[1] if len(parts) > 1 else "").partition(",")
                name = name.strip()
                if not re.fullmatch(r"[A-Za-z_]\w*", name) or not expr.strip():
                    raise AssemblerError(f"line {line_no}: expected '.equ NAME, value'")
                if name in overrides:
                    expr = overrides.pop(name)
                consts[name] = eval_expr(expr, consts, f"line {line_no} (.equ {name})")
                continue
            if directive not in IGNORED_DIRECTIVES:
                raise AssemblerError(f"line {line_no}: unsupported directive {directive!r}")
            continue
        parts = text.split(None, 1)
        mnemonic = parts[0].lower()
        if mnemonic not in SUPPORTED | PSEUDO:
            raise AssemblerError(f"line {line_no}: unsupported instruction {mnemonic!r}; supported: {', '.join(sorted(SUPPORTED | PSEUDO))}")
        operands = split_operands(parts[1]) if len(parts) > 1 else []
        if mnemonic == "li":
            if len(operands) != 2:
                raise AssemblerError(f"line {line_no} (li): expected 2 operands, received {len(operands)}")
            value = eval_expr(operands[1], consts, f"line {line_no} (li)")
            if not -(1 << 31) <= value <= 0xFFFFFFFF:
                raise AssemblerError(f"line {line_no} (li): value {value} does not fit 32 bits")
            hi, lo = split_li(value)
            rd = operands[0]
            instructions.append(SourceInstruction(line_no, raw.rstrip(), pc, "lui", [rd, str(hi)], consts))
            instructions.append(SourceInstruction(line_no, raw.rstrip(), pc + 4, "addi", [rd, rd, str(lo)], consts))
            pc += 8
            continue
        instructions.append(SourceInstruction(line_no, raw.rstrip(), pc, mnemonic, operands, consts))
        pc += 4
    if overrides:
        raise AssemblerError(f"-D given for constants not defined with .equ: {', '.join(sorted(overrides))}")
    return instructions, labels


def resolve_target(token: str, pc: int, labels: Dict[str, int], context: str) -> int:
    if token in labels:
        return labels[token] - pc
    # Numeric branch/JAL targets are accepted as relative offsets.
    return parse_number(token, context)


def imm(token: str, ins: SourceInstruction, context: str) -> int:
    return eval_expr(token, ins.consts, context)


def encode_instruction(ins: SourceInstruction, labels: Dict[str, int]) -> int:
    m, o = ins.mnemonic, ins.operands
    ctx = f"line {ins.line_no} ({m})"
    expected = {
        "lui": 2, "addi": 3, "andi": 3, "xori": 3,
        "add": 3, "sub": 3, "and": 3, "xor": 3,
        "lw": 2, "sw": 2, "beq": 3, "bne": 3, "bltu": 3, "jal": 2,
    }[m]
    if len(o) != expected:
        raise AssemblerError(f"{ctx}: expected {expected} operands, received {len(o)}")

    if m == "lui":
        rd = parse_reg(o[0], ctx)
        return enc_u(rd, imm(o[1], ins, ctx), ctx)
    if m in {"addi", "andi", "xori"}:
        rd = parse_reg(o[0], ctx); rs1 = parse_reg(o[1], ctx); value = imm(o[2], ins, ctx)
        funct3 = {"addi": 0, "xori": 4, "andi": 7}[m]
        return enc_i(0x13, rd, funct3, rs1, value, ctx)
    if m in {"add", "sub", "and", "xor"}:
        rd = parse_reg(o[0], ctx); rs1 = parse_reg(o[1], ctx); rs2 = parse_reg(o[2], ctx)
        funct3 = {"add": 0, "sub": 0, "xor": 4, "and": 7}[m]
        funct7 = 0x20 if m == "sub" else 0
        return enc_r(rd, rs1, rs2, funct3, funct7)
    if m in {"lw", "sw"}:
        mem = MEM_RE.fullmatch(o[1])
        if not mem:
            raise AssemblerError(f"{ctx}: expected offset(xN), got {o[1]!r}")
        offset = imm(mem.group(1), ins, ctx); rs1 = parse_reg(mem.group(2), ctx)
        if m == "lw":
            return enc_i(0x03, parse_reg(o[0], ctx), 2, rs1, offset, ctx)
        return enc_s(parse_reg(o[0], ctx), rs1, offset, 2, ctx)
    if m in {"beq", "bne", "bltu"}:
        rs1 = parse_reg(o[0], ctx); rs2 = parse_reg(o[1], ctx)
        offset = resolve_target(o[2], ins.pc, labels, ctx)
        funct3 = {"beq": 0, "bne": 1, "bltu": 6}[m]
        return enc_b(rs1, rs2, offset, funct3, ctx)
    if m == "jal":
        rd = parse_reg(o[0], ctx)
        offset = resolve_target(o[1], ins.pc, labels, ctx)
        return enc_j(rd, offset, ctx)
    raise AssemblerError(f"{ctx}: no encoder implemented")


def assemble_listing(source: str, defines: Optional[Dict[str, str]] = None) -> Tuple[List[int], Dict[str, int], List[SourceInstruction]]:
    instructions, labels = parse_source(source, defines)
    words: List[int] = []
    for ins in instructions:
        try:
            words.append(encode_instruction(ins, labels))
        except AssemblerError as exc:
            raise AssemblerError(f"{exc}\n  source: {ins.source.strip()}") from exc
    return words, labels, instructions


def assemble_text(source: str, defines: Optional[Dict[str, str]] = None) -> Tuple[List[int], Dict[str, int]]:
    words, labels, _ = assemble_listing(source, defines)
    return words, labels


def verilog_rom(words: List[int], instructions: List[SourceInstruction], source_name: str,
                defines: Dict[str, str], max_words: int) -> str:
    """Program as a Verilog include: GAME_WORDS and the combinational function game_word()."""
    addr_bits = max(1, (max_words - 1).bit_length())
    lines = [
        f"// Generated by tools/assembler.py from {source_name}. DO NOT EDIT.",
    ]
    if defines:
        lines.append("// Overrides: " + ", ".join(f"{k}={v}" for k, v in sorted(defines.items())))
    lines += [
        f"localparam integer GAME_WORDS     = {len(words)};",
        f"localparam integer GAME_ADDR_BITS = {addr_bits};",
        "",
        "function [31:0] game_word;",
        "  input [GAME_ADDR_BITS-1:0] idx;",
        "  begin",
        "    case (idx)",
    ]
    for index, (word, ins) in enumerate(zip(words, instructions)):
        text = f"{ins.mnemonic} {', '.join(ins.operands)}"
        lines.append(f"      {addr_bits}'d{index}: game_word = 32'h{word:08x}; // 0x{ins.pc:03x}: {text}")
    lines += [
        "      default: game_word = 32'h00000000;",
        "    endcase",
        "  end",
        "endfunction",
        "",
    ]
    return "\n".join(lines)


def parse_define(text: str) -> Tuple[str, str]:
    name, sep, value = text.partition("=")
    if not sep or not name.strip():
        raise argparse.ArgumentTypeError(f"expected NAME=VALUE, got {text!r}")
    return name.strip(), value.strip()


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="input Assembly source (e.g. sw/game.s)")
    parser.add_argument("-o", "--output", type=Path, required=True, help="output hex path")
    parser.add_argument("--symbols", type=Path, help="optionally write label address table")
    parser.add_argument("--verilog", type=Path, help="write the program as a Verilog ROM include")
    parser.add_argument("-D", dest="defines", action="append", type=parse_define, default=[],
                        metavar="NAME=VALUE", help="override an .equ constant (repeatable)")
    parser.add_argument("--max-words", type=int, default=DEFAULT_MAX_WORDS,
                        help=f"instruction memory capacity in words (default {DEFAULT_MAX_WORDS})")
    args = parser.parse_args(argv)
    defines = dict(args.defines)
    try:
        source_text = args.source.read_text(encoding="utf-8")
        words, labels, instructions = assemble_listing(source_text, defines)
        if len(words) > args.max_words:
            raise AssemblerError(f"program has {len(words)} words; ROM capacity is {args.max_words}")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")
        if args.symbols:
            args.symbols.parent.mkdir(parents=True, exist_ok=True)
            args.symbols.write_text("".join(f"0x{address:08x} {name}\n" for name, address in sorted(labels.items(), key=lambda item: item[1])), encoding="utf-8")
        if args.verilog:
            args.verilog.parent.mkdir(parents=True, exist_ok=True)
            args.verilog.write_text(verilog_rom(words, instructions, args.source.as_posix(), defines, args.max_words), encoding="ascii")
        print(f"Assembled {args.source}: {len(words)} words -> {args.output}" + (f", {args.verilog}" if args.verilog else ""))
        return 0
    except (OSError, AssemblerError) as exc:
        print(f"assembler: error: {exc}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())

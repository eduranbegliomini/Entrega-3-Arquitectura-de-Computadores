import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import assembler


class TestAssembler(unittest.TestCase):
    def test_known_encodings(self):
        cases = {
            "addi x1, x0, 1": 0x00100093,
            "lui x2, 0x80000": 0x80000137,
            "lw x1, 0(x2)": 0x00012083,
            "sw x1, 0(x2)": 0x00112023,
            "jal x0, 0": 0x0000006F,
            "bne x1, x0, -4": 0xFE009EE3,
        }
        for source, expected in cases.items():
            with self.subTest(source=source):
                ins, labels = assembler.parse_source(source)
                self.assertEqual(assembler.encode_instruction(ins[0], labels), expected)

    def test_label_resolution_backward(self):
        source = """
_start:
    addi x1, x0, 1
loop:
    addi x1, x1, -1
    bne x1, x0, loop
"""
        words, labels = assembler.assemble_text(source)
        self.assertEqual(labels["loop"], 4)
        self.assertEqual(len(words), 3)
        self.assertEqual(words[2], 0xFE009EE3)

    def test_label_resolution_forward(self):
        source = """
    beq x0, x0, there
    addi x1, x0, 1
there:
    jal x0, there
"""
        words, labels = assembler.assemble_text(source)
        self.assertEqual(labels["there"], 8)
        # From PC 0 to PC 8 is +8.
        self.assertEqual(words[0], 0x00000463)
        self.assertEqual(words[2], 0x0000006F)

    def test_rv32e_register_limit(self):
        with self.assertRaises(assembler.AssemblerError):
            assembler.assemble_text("addi x16, x0, 1")

    def test_immediate_range(self):
        with self.assertRaises(assembler.AssemblerError):
            assembler.assemble_text("addi x1, x0, 2048")

    def test_shift_is_rejected_for_this_core(self):
        with self.assertRaises(assembler.AssemblerError):
            assembler.assemble_text("slli x1, x1, 1")

    def test_malformed_operand_lists_are_rejected(self):
        for source in ("addi x1,, x0, 1", "addi x1, x0, 1,", "add x1 x2, x3"):
            with self.subTest(source=source):
                with self.assertRaises(assembler.AssemblerError):
                    assembler.assemble_text(source)

    def test_duplicate_labels_are_rejected(self):
        with self.assertRaises(assembler.AssemblerError):
            assembler.assemble_text("again:\n  addi x1, x0, 0\nagain:\n  jal x0, again")


    def test_all_control_flow_targets_resolve_to_instruction_boundaries(self):
        source = (ROOT / "sw" / "game.s").read_text(encoding="utf-8")
        instructions, labels = assembler.parse_source(source)
        words, _ = assembler.assemble_text(source)

        def sext(value, bits):
            sign = 1 << (bits - 1)
            return (value ^ sign) - sign

        for ins, word in zip(instructions, words):
            if ins.mnemonic in {"beq", "bne", "bltu"} and ins.operands[2] in labels:
                imm = (((word >> 31) & 1) << 12) | (((word >> 7) & 1) << 11) | (((word >> 25) & 0x3F) << 5) | (((word >> 8) & 0xF) << 1)
                target = ins.pc + sext(imm, 13)
                self.assertEqual(target, labels[ins.operands[2]], ins.source)
            elif ins.mnemonic == "jal" and ins.operands[1] in labels:
                imm = (((word >> 31) & 1) << 20) | (((word >> 12) & 0xFF) << 12) | (((word >> 20) & 1) << 11) | (((word >> 21) & 0x3FF) << 1)
                target = ins.pc + sext(imm, 21)
                self.assertEqual(target, labels[ins.operands[1]], ins.source)

    def test_lfsr_nonzero_period_is_255(self):
        def step(state):
            feedback = state & 0x80
            state = (state * 2) & 0xFF
            if feedback:
                state ^= 0x1D
            return state
        state = 1
        seen = set()
        while state not in seen:
            seen.add(state)
            state = step(state)
        self.assertEqual(len(seen), 255)
        self.assertEqual(state, 1)

    def test_clock_cycle_constants(self):
        self.assertEqual(((0x262 << 12) + 0x5A0), 2_500_000)
        self.assertEqual(((0x4787 << 12) - 1856), 75_000_000)
        self.assertEqual(((0x131 << 12) + 720), 1_250_000)
        self.assertEqual(((0xBEC << 12) - 992), 12_500_000)
        self.assertEqual(((0x17D8 << 12) - 1984), 25_000_000)
        self.assertEqual(((0x95030 << 12) - 1792), 2_500_000_000)

    def test_game_program_assembles_and_fits_ram(self):
        source_path = ROOT / "sw" / "game.s"
        words, labels = assembler.assemble_text(source_path.read_text(encoding="utf-8"))
        self.assertEqual(len(words), 136)
        self.assertLessEqual(len(words), 512)
        self.assertIn("_start", labels)
        self.assertTrue(all(0 <= word <= 0xFFFFFFFF for word in words))
        # All label-relative branch/jump encodings were resolved by the assembler.
        output = ROOT / "sw" / "build" / "game.hex"
        lines = output.read_text(encoding="ascii").splitlines()
        self.assertEqual(len(lines), len(words))
        self.assertEqual([int(line, 16) for line in lines], words)
        self.assertTrue(all(len(line) == 8 and all(c in "0123456789abcdefABCDEF" for c in line) for line in lines))

    def test_target_timestamp_latch_is_tied_to_led_write(self):
        periph = (ROOT / "rtl" / "pochoco_periph.v").read_text(encoding="utf-8")
        counter = (ROOT / "rtl" / "pochoco_cycle_counter.v").read_text(encoding="utf-8")
        self.assertIn("else if (capture_i) target_start_o <= count_o", counter)
        self.assertIn("4'b0001, 4'b0010, 4'b0100, 4'b1000", periph)
        self.assertIn(".capture_i      (led_write & one_hot)", periph)
        self.assertIn("6'd4: rdata_o <= target_start", periph)

    def test_exact_cycle_average_rounding(self):
        # Ten measurements from 0.1 s through 1.0 s average to 0.55 s,
        # which is 5.5 tenths and rounds half-up to 6 tenths.
        cycles_per_tenth = 2_500_000
        durations = [i * cycles_per_tenth for i in range(1, 11)]
        avg_tenths = (sum(durations) + 12_500_000) // 25_000_000
        self.assertEqual(avg_tenths, 6)
        self.assertEqual(sum([i for i in range(1, 11)]), 55)


class TestProyecto3Extensions(unittest.TestCase):
    GAME = (ROOT / "sw" / "game.s").read_text(encoding="utf-8")

    def test_li_split_matches_gnu_as(self):
        for value in (0, 1, 2047, 2048, 4095, 1_000_000, 30_000_000, 0x80000000, 1_000_000_000, 2_500_000_000, 0xFFFFFFFF, -1):
            with self.subTest(value=value):
                hi, lo = assembler.split_li(value)
                self.assertTrue(-2048 <= lo <= 2047)
                self.assertEqual(((hi << 12) + lo) & 0xFFFFFFFF, value & 0xFFFFFFFF)

    def test_li_always_two_words(self):
        words, _ = assembler.assemble_text("li x5, 1\nli x6, 0x12345678")
        self.assertEqual(len(words), 4)

    def test_equ_expressions_and_override(self):
        src = ".equ HZ, 10000000\n.equ TENTH, HZ / 10\nli x5, TENTH\naddi x6, x0, TENTH / 1000"
        words, _ = assembler.assemble_text(src)
        hi, lo = assembler.split_li(1_000_000)
        self.assertEqual(words[0], (hi << 12) | (5 << 7) | 0x37)
        self.assertEqual(words[2], assembler.enc_i(0x13, 6, 0, 0, 1000, "t"))
        words_d, _ = assembler.assemble_text(src, {"HZ": "20000"})
        self.assertEqual(words_d[2], assembler.enc_i(0x13, 6, 0, 0, 2, "t"))

    def test_unknown_define_is_rejected(self):
        with self.assertRaises(assembler.AssemblerError):
            assembler.assemble_text(".equ A, 1\naddi x1, x0, A", {"B": "2"})

    def test_25mhz_build_reproduces_proyecto2_hex(self):
        words, _ = assembler.assemble_text(self.GAME, {"CLK_HZ": "25000000"})
        p2 = [int(l, 16) for l in (ROOT / "p2_reference" / "sw" / "game.hex").read_text().split()]
        self.assertEqual(words, p2)

    def test_10mhz_constants(self):
        consts = {}
        instructions, _ = assembler.parse_source(self.GAME)
        consts = instructions[0].consts
        self.assertEqual(consts["CYC_TENTH"], 1_000_000)
        self.assertEqual(consts["CYC_HALF_TENTH"], 500_000)
        self.assertEqual(consts["CYC_PREP"], 30_000_000)
        self.assertEqual(consts["CYC_HALF_SECOND"], 5_000_000)
        self.assertEqual(consts["CYC_AVG_DIV"], 10_000_000)
        self.assertEqual(consts["CYC_SUM_LIMIT"], 1_000_000_000)

    def test_verilog_rom_include(self):
        words, labels, ins = assembler.assemble_listing(self.GAME)
        text = assembler.verilog_rom(words, ins, "sw/game.s", {}, 256)
        self.assertIn("localparam integer GAME_WORDS     = 136;", text)
        self.assertIn("8'd0: game_word = 32'h800000b7;", text)
        self.assertEqual(text.count("8'd"), 136)
        committed = (ROOT / "sw" / "build" / "game_program.vh").read_text(encoding="ascii")
        self.assertEqual(committed, text, "sw/build/game_program.vh is stale: rerun the assembler")


if __name__ == "__main__":
    unittest.main()

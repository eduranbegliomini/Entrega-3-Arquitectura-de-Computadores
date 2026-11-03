# Juego de reflejos para Pochoco SoC / Espino Core (RV32E) - Proyecto 3 (ASIC).
# MMIO: display 0x80000000, LEDs 0x80000004, buttons 0x80000008,
#       free-running cycle counter 0x8000000C, target-start latch 0x80000010.
# Display encoding: two decimal digits representing tenths of a second.
# EE = wrong button; FF = a time/average that rounds to >= 10.0 seconds.
# No shift instructions are used because the supplied ALU disables shifts.
#
# All delays derive from CLK_HZ. The ASIC macro runs with CLOCK_PERIOD = 100 ns
# (10 MHz); the Proyecto 2 FPGA build used 25 MHz (sw/game_25mhz_p2.s).
# `li` always expands to lui + addi, so changing CLK_HZ never changes the
# program size. Simulation shortens the delays with: -D CLK_HZ=<small value>.
.equ CLK_HZ,          10000000                # T = 100 ns
.equ CYC_TENTH,       CLK_HZ / 10             # 0.1 s  = 1,000,000 cycles
.equ CYC_HALF_TENTH,  CYC_TENTH / 2           # 0.05 s =   500,000 cycles
.equ CYC_PREP,        3 * CLK_HZ              # 3 s    = 30,000,000 cycles
.equ CYC_HALF_SECOND, CLK_HZ / 2              # 0.5 s  = 5,000,000 cycles
.equ CYC_AVG_DIV,     10 * CYC_TENTH          # sum of 10 rounds / this = average tenths
.equ CYC_SUM_LIMIT,   100 * CYC_AVG_DIV       # sum whose average is 10.0 s

.section .text
.global _start

_start:
    lui  x1, 0x80000         # x1 = display/MMIO base
    addi x2, x1, 4           # x2 = LED register
    addi x3, x1, 8           # x3 = button input register
    addi x4, x1, 12          # x4 = cycle counter register

    li   x5, CYC_TENTH        # x5 = cycles per 0.1 s

    addi x7, x0, 0           # x7 = correct answers
    addi x8, x0, 0           # x8 = sum of exact response durations (cycles)

    lw   x9, 0(x4)           # Seed PRNG from counter
    andi x9, x9, 255
    bne  x9, x0, seed_ready
    addi x9, x0, 1           # LFSR must not start at zero
seed_ready:
    sw   x0, 0(x1)           # Display 00

wait_release:
    lw   x12, 0(x3)
    bne  x12, x0, wait_release

    # Reload 3 s on every attempt: x6 is reused below as the 0.05 s rounding
    # threshold, so a value loaded only once in _start would be lost.
    li   x6, CYC_PREP         # x6 = cycles in the 3 s preparation

    addi x13, x0, 15        # All four LEDs on
    sw   x13, 0(x2)
    lw   x11, 0(x4)          # Beginning of three-second preparation
prep_wait:
    lw   x12, 0(x4)
    sub  x13, x12, x11       # Unsigned modular elapsed-cycle difference
    bltu x13, x6, prep_wait

    # If a button was pressed during preparation, wait for its release before
    # revealing the target; pre-target presses must not count as reactions.
prep_release_wait:
    lw   x12, 0(x3)
    bne  x12, x0, prep_release_wait

    # Mix the changing counter value into an 8-bit LFSR seed.
    lw   x12, 0(x4)
    andi x12, x12, 255
    xor  x9, x9, x12
    andi x9, x9, 255
    bne  x9, x0, prng_nonzero
    addi x9, x0, 1
prng_nonzero:
    andi x10, x9, 128       # Save old high bit as feedback
    add  x9, x9, x9         # Shift left 1 using ADD (not SLL)
    andi x9, x9, 255        # Keep 8-bit state
    beq  x10, x0, prng_shifted
    xori x9, x9, 29         # Polynomial mask 0x1D
prng_shifted:
    andi x10, x9, 3          # LED index in 0..3
    addi x14, x0, 1           # Build LED mask 1 << index without shifts
mask_loop:
    beq  x10, x0, mask_ready
    add  x14, x14, x14
    addi x10, x10, -1
    jal  x0, mask_loop
mask_ready:
    addi x15, x1, 16          # MMIO pointer to atomic target-start timestamp
    sw   x14, 0(x2)           # Show target; hardware latches timer on this same edge
    lw   x11, 0(x15)          # Exact cycle value from the target-presentation edge
    addi x15, x11, 0          # Preserve original start for full-precision sum
    addi x10, x0, 0           # x10 = elapsed tenths
    li   x6, CYC_HALF_TENTH   # x6 = cycles in 0.05 s (rounding threshold)

response_wait:
    lw   x12, 0(x4)           # Read timer before sampling button
    sub  x13, x12, x11
    bltu x13, x5, check_buttons
    add  x11, x11, x5         # Advance one 0.1 s boundary
    addi x10, x10, 1
check_buttons:
    lw   x12, 0(x3)
    beq  x12, x0, response_wait
    bne  x12, x14, wrong_answer  # Only the target button may be active

    # Correct press: keep the full elapsed cycle count for the final average.
    # x15 holds the exact start timestamp; x12 is the current counter sample.
    lw   x12, 0(x4)
    sub  x15, x12, x15        # Exact reaction duration in cycles

    # Accumulate raw cycles, not already-rounded tenths. If total cycles reach
    # 2.5 billion, the ten-round average is at least 10 s and must display FF.
    addi x13, x0, -1
    beq  x8, x13, cycle_sum_done
    li   x13, CYC_SUM_LIMIT   # Ten-round sum that averages to 10.0 s
    sub  x13, x13, x8          # Remaining room before average reaches 10 s
    bltu x15, x13, cycle_sum_add
    addi x8, x0, -1            # Saturation sentinel: average out of display range
    jal  x0, cycle_sum_done
cycle_sum_add:
    add  x8, x8, x15
cycle_sum_done:

    # Round the displayed individual time to the nearest tenth.
    sub  x13, x12, x11        # Remainder beyond the last 0.1 s boundary
    bltu x13, x6, response_time_ready
    addi x10, x10, 1
response_time_ready:
    # Display response as two decimal digits; FF means >= 10.0 seconds.
    addi x13, x0, 100
    bltu x10, x13, display_response
    addi x13, x0, 255
    sw   x13, 0(x1)
    jal  x0, after_response_display

display_response:
    addi x14, x0, 0            # x14 = tens digit
    addi x15, x10, 0            # x15 = remaining tenths

divide_response_by_10:
    addi x13, x0, 10
    bltu x15, x13, pack_response
    sub  x15, x15, x13
    addi x14, x14, 1
    jal  x0, divide_response_by_10
pack_response:
    add  x13, x14, x14         # tens * 2
    add  x13, x13, x13         # tens * 4
    add  x13, x13, x13         # tens * 8
    add  x13, x13, x13         # tens * 16
    add  x13, x13, x15         # packed BCD-like byte: tens | ones
    sw   x13, 0(x1)

after_response_display:
    addi x7, x7, 1
    addi x13, x0, 10
    bne  x7, x13, wait_release

    # Hold the tenth response on the display for about 0.5 s before average.
    lw   x11, 0(x4)
    li   x6, CYC_HALF_SECOND  # 0.5 s hold; also half the average divisor
final_response_pause:
    lw   x12, 0(x4)
    sub  x13, x12, x11
    bltu x13, x6, final_response_pause

    # Average in tenths = sum_cycles / 25,000,000. Add half the divisor
    # (12,500,000 cycles) first to round to the nearest tenth.
    addi x13, x0, -1
    beq  x8, x13, average_overflow
    li   x13, CYC_AVG_DIV     # 10 rounds x CYC_TENTH = one tenth of average
    add  x15, x8, x6           # x6 = 12,500,000-cycle half-divisor
    addi x14, x0, 0             # x14 = average in tenths

divide_sum_by_25m:
    bltu x15, x13, average_tenths_ready
    sub  x15, x15, x13
    addi x14, x14, 1
    jal  x0, divide_sum_by_25m
average_tenths_ready:
    addi x13, x0, 100
    bltu x14, x13, display_average
average_overflow:
    addi x13, x0, 255
    sw   x13, 0(x1)             # Average rounds to 10.0 s or higher
    jal  x0, game_done

display_average:
    addi x10, x14, 0            # x10 = average in tenths
    addi x14, x0, 0             # x14 = tens digit
divide_average_by_10:
    addi x13, x0, 10
    bltu x10, x13, pack_average
    sub  x10, x10, x13
    addi x14, x14, 1
    jal  x0, divide_average_by_10
pack_average:
    add  x13, x14, x14
    add  x13, x13, x13
    add  x13, x13, x13
    add  x13, x13, x13
    add  x13, x13, x10
    sw   x13, 0(x1)

game_done:
    addi x13, x0, 0
    sw   x13, 0(x2)              # Turn all LEDs off

done_loop:
    jal  x0, done_loop

wrong_answer:
    addi x13, x0, 238            # 0xEE = error indicator
    sw   x13, 0(x1)
    addi x13, x0, 0
    sw   x13, 0(x2)
wait_wrong_release:
    lw   x12, 0(x3)
    bne  x12, x0, wait_wrong_release
    jal  x0, wait_release        # Retry this round; keep count/sum intact

// Testbench for asic_top, shared by the RTL and the post-synthesis netlist
// simulations (section 3.7). Both runs use the program assembled with
// -D CLK_HZ=2000 (sw/build_sim), so 0.1 s = 200 cycles and the 3 s
// preparation = 6000 cycles instead of 30,000,000.
//
// Inputs change and outputs are sampled on the falling clock edge (no races
// with the rising edge). Stimulus is defined in clock cycles relative to the cycle at which the
// one-hot target LED appears:
//   * round 3 (index 2) first receives a WRONG button at +REACT_WRONG cycles:
//     the display must show EE, the LEDs must turn off and, after release,
//     the same round restarts (four LEDs on again);
//   * every correct round is pressed at +REACT[i] cycles and held HOLD cycles.
// Every change of the output ports is logged with its cycle number to
// LOG_FILE; identical RTL and gate-level logs prove cycle-exact equivalence.
`timescale 1ns/1ps

module tb_game;
  localparam integer CLK_NS      = 100;     // CLOCK_PERIOD = 100 ns
  localparam integer HOLD        = 300;   // > worst-case display update latency
  localparam integer REACT_WRONG = 120;
  localparam integer TIMEOUT     = 400000;

  reg        clk = 1'b0;
  reg        rst_n = 1'b0;
  reg  [3:0] btn = 4'b0;
  wire [3:0] led;
  wire [6:0] seg1, seg2;
  wire       spi_miso;

  always #(CLK_NS/2) clk = ~clk;

  asic_top dut (
    .clk(clk), .rst_n(rst_n), .btn(btn), .led(led), .seg1(seg1), .seg2(seg2),
    .spi_sclk(1'b0), .spi_mosi(1'b0), .spi_cs_n(1'b1), .spi_miso(spi_miso)
  );

  integer cycle = 0;
  always @(posedge clk) cycle <= cycle + 1;

  // ---- seven-segment decoder (1 = segment on, {g,f,e,d,c,b,a}) ----
  function [3:0] seg2hex;
    input [6:0] s;
    begin
      case (s)
        7'b0111111: seg2hex = 4'h0; 7'b0000110: seg2hex = 4'h1;
        7'b1011011: seg2hex = 4'h2; 7'b1001111: seg2hex = 4'h3;
        7'b1100110: seg2hex = 4'h4; 7'b1101101: seg2hex = 4'h5;
        7'b1111101: seg2hex = 4'h6; 7'b0000111: seg2hex = 4'h7;
        7'b1111111: seg2hex = 4'h8; 7'b1101111: seg2hex = 4'h9;
        7'b1110111: seg2hex = 4'hA; 7'b1111100: seg2hex = 4'hB;
        7'b0111001: seg2hex = 4'hC; 7'b1011110: seg2hex = 4'hD;
        7'b1111001: seg2hex = 4'hE; 7'b1110001: seg2hex = 4'hF;
        default:    seg2hex = 4'hx;
      endcase
    end
  endfunction
  wire [7:0] display = {seg2hex(seg1), seg2hex(seg2)};

  // ---- output-port event log ----
  integer log_fd;
  reg [255:0] log_file;
  initial begin
    if (!$value$plusargs("LOG=%s", log_file)) log_file = "tb_game.log";
    log_fd = $fopen(log_file, "w");
  end
  // Outputs are sampled on the falling edge, half a period after the rising
  // edge that updates them, so zero-delay glitches in the netlist are ignored.
  reg [17:0] last_out = 18'bx;
  always @(negedge clk)
    if (rst_n && {led, seg1, seg2} !== last_out) begin
      last_out = {led, seg1, seg2};
      $fdisplay(log_fd, "cycle=%0d led=%b display=%h", cycle, led, display);
    end

  // ---- cycles measured by the program ----
  // game.s accumulates the exact reaction time of every correct round in x8.
  // Watching the register-file write port (a module port, so it keeps its name
  // in the hierarchical netlist) gives each round's measured cycles in both
  // the RTL and the gate-level simulation.
  wire        rf_we    = dut.u_soc.u_core.u_rf.we_i;
  wire [3:0]  rf_waddr = dut.u_soc.u_core.u_rf.waddr_i;
  wire [31:0] rf_wdata = dut.u_soc.u_core.u_rf.wdata_i;
  reg  [31:0] sum_prev = 32'b0;
  integer     measured = 0, n_measured = 0;
  always @(negedge clk)
    if (rst_n && rf_we === 1'b1 && rf_waddr == 4'd8 && rf_wdata != sum_prev) begin
      measured   = rf_wdata - sum_prev;
      sum_prev   = rf_wdata;
      n_measured = n_measured + 1;
      $fdisplay(log_fd, "cycle=%0d measured_cycles=%0d sum=%0d", cycle, measured, rf_wdata);
    end

  // ---- data RAM usage (section 3.2): count loads/stores that reach RAM ----
`ifdef MEM_UNIFIED_FF
  wire ram_req = dut.u_soc.u_mem.b_req_i;
`else
  wire ram_req = dut.u_soc.u_dram.req_i;
`endif
  integer ram_accesses = 0;
  always @(negedge clk) if (rst_n && ram_req === 1'b1) ram_accesses = ram_accesses + 1;

  // ---- helpers ----
  task automatic wait_cycles(input integer n);
    integer k;
    begin
      for (k = 0; k < n; k = k + 1) @(negedge clk);
    end
  endtask

  function is_one_hot(input [3:0] v);
    is_one_hot = (v == 4'b0001) | (v == 4'b0010) | (v == 4'b0100) | (v == 4'b1000);
  endfunction

  integer react [0:9];
  integer round_idx, t_target, t_press, t_disp, errors, wrong_done;
  // Cycle of the most recent display change (the program's "result" event).
  reg [7:0] disp_prev;
  always @(negedge clk) begin if (display !== disp_prev) t_disp = cycle; disp_prev = display; end
  reg [3:0] target;
  reg [7:0] shown;

  initial begin
    // Reaction delays in cycles (0.1 s = 200 cycles in this configuration).
    react[0] = 250;  react[1] = 333;  react[2] = 460;  react[3] = 180;
    react[4] = 610;  react[5] = 299;  react[6] = 777;  react[7] = 405;
    react[8] = 150;  react[9] = 520;
    errors = 0; wrong_done = 0;

    wait_cycles(5);
    rst_n = 1'b1;

    round_idx = 0;
    while (round_idx < 10) begin
      // Wait for the single target LED after the 3 s preparation.
      @(negedge clk);
      while (!is_one_hot(led)) @(negedge clk);
      target   = led;
      t_target = cycle;

      if (round_idx == 2 && !wrong_done) begin
        // Wrong button: the next LED (rotated) is never the target.
        wait_cycles(REACT_WRONG);
        btn = {target[2:0], target[3]};
        wait_cycles(HOLD);
        if (display !== 8'hEE || led !== 4'b0000) begin
          $display("ERROR: wrong press did not show EE (display=%h led=%b)", display, led);
          errors = errors + 1;
        end
        btn = 4'b0;
        // After release the same round restarts with all four LEDs on.
        while (led !== 4'b1111) @(negedge clk);
        $display("[cycle %0d] round %0d: WRONG button %b at +%0d -> display EE, round restarted (LEDs=1111)",
                 cycle, round_idx + 1, {target[2:0], target[3]}, REACT_WRONG);
        wrong_done = 1;
      end else begin
        wait_cycles(react[round_idx]);
        t_press = cycle;
        btn = target;
        wait_cycles(HOLD);
        shown = display;
        btn = 4'b0;
        $display("[cycle %0d] round %0d: target=%b press@+%0d, measured=%0d cycles, display=%h (updated at +%0d)",
                 cycle, round_idx + 1, target, t_press - t_target, measured, shown, t_disp - t_target);
        round_idx = round_idx + 1;
        // Next attempt starts with the 3 s preparation (all LEDs on).
        if (round_idx < 10) while (led !== 4'b1111) @(negedge clk);
      end
    end

    // The tenth time stays ~0.5 s, then the average is shown with LEDs off.
    while (led !== 4'b0000) @(negedge clk);
    wait_cycles(2);
    $display("[cycle %0d] average display=%h, LEDs=%b", cycle, display, led);
    $display("data RAM accesses during the whole game: %0d", ram_accesses);
    if (n_measured != 10) begin
      $display("ERROR: expected 10 measured rounds, got %0d", n_measured);
      errors = errors + 1;
    end
    if (!wrong_done) errors = errors + 1;
    $display("RESULT: %s (errors=%0d)", errors == 0 ? "PASS" : "FAIL", errors);
    $fclose(log_fd);
    $finish;
  end

  initial begin
    wait_cycles(TIMEOUT);
    $display("ERROR: timeout at cycle %0d", cycle);
    $display("RESULT: FAIL (timeout)");
    $finish;
  end
endmodule

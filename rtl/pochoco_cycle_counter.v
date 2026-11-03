// Copyright 2026 Universidad de los Andes.
// SPDX-License-Identifier: SHL-0.51
//
// Proyecto 2 addition, moved into its own module in Proyecto 3 so that its
// area can be reported and located in the layout (instance
// u_soc/u_periph/u_cycle_counter).
//
//  * count_o:        free-running 32-bit cycle counter (MMIO 0x8000000C).
//  * target_start_o: counter value captured on the same edge that a one-hot
//                    LED target is written (MMIO 0x80000010).

module pochoco_cycle_counter (
  input  wire        clk_i,
  input  wire        rst_ni,
  input  wire        capture_i,
  output reg  [31:0] count_o,
  output reg  [31:0] target_start_o
);

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) count_o <= 32'b0;
    else         count_o <= count_o + 32'd1;
  end

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)        target_start_o <= 32'b0;
    else if (capture_i) target_start_o <= count_o;
  end

endmodule

// ============================================================================
// Problem 2 -- A register file: combinational read, sequential write
//
// Eight 8-bit registers, two read ports, one write port. This is the exact
// structure sitting in the middle of every CPU datapath you will ever draw,
// and it is the lab's "combinational read, sequential write" pattern at full
// size.
//
//   read  : combinational. Put an address on rs1_addr_i and the data appears
//           on rs1_data_o in the same cycle. No clock, no latency.
//   write : sequential. Data lands at the next rising edge.
//
// Why asymmetric? Because the alternative costs you a cycle for nothing.
// Registering the read port would mean the instruction after a read waits an
// extra cycle to see its operands -- a stall on every single instruction. The
// cost of the combinational read is that the read path (address decode + the
// mux across all 8 registers) is on your critical path. That is the trade,
// and every real CPU takes this side of it.
//
// ---------------------------------------------------------------------------
// Register 0 is hardwired to zero, RISC-V style: reads always return 0, and
// writes to it are silently discarded. It is a surprisingly useful piece of
// free hardware -- `add x0, x0, x0` is a NOP, `beq x0, x0, L` is an
// unconditional branch, and you get a zero operand without burning an
// immediate field. Note it costs *less* than a real register, not more:
// there is no flop behind it at all, just a constant.
// ============================================================================
module p2_regfile
  import hw_pkg::*;
(
    input  logic     clk_i,
    input  logic     rst_ni,

    // two combinational read ports
    input  regid_t   rs1_addr_i,
    output xdata_t   rs1_data_o,
    input  regid_t   rs2_addr_i,
    output xdata_t   rs2_data_o,

    // one sequential write port, bundled as a struct (see hw_pkg.sv)
    input  wr_port_t wr_i,

    // Part (c): when high, a read of the register being written this cycle
    // returns the NEW data instead of the old. See below.
    input  logic     bypass_en_i
);

  // --------------------------------------------------------------------------
  // The storage itself: an unpacked array of packed values.
  //
  //     xdata_t regs_q [NUM_REGS];
  //
  // Read that carefully, it trips everyone up once:
  //   - xdata_t is PACKED   -> each entry is a real 8-bit bit vector
  //   - [NUM_REGS] is UNPACKED -> eight separate such vectors
  //
  // That is the right shape for storage. An unpacked dimension is what tells
  // the synthesizer "these are 8 independent things I will index into",
  // which is what lets it build (or infer a memory for) an array. If you
  // wrote `logic [NUM_REGS-1:0][XLEN-1:0]` you would get one 64-bit packed
  // blob -- also legal, also indexable, but it is a different declaration
  // with different rules, and for a register file the unpacked form is the
  // conventional one.
  // --------------------------------------------------------------------------
  xdata_t regs_q [NUM_REGS];

  // --------------------------------------------------------------------------
  // TODO 2a -- the write port.
  //
  //   on reset         -> clear every register to 0
  //   else if wr_i.en  -> write wr_i.data into regs_q[wr_i.addr],
  //                       UNLESS wr_i.addr is 0 (writes to r0 are discarded)
  //
  // For the reset, you need a loop over all NUM_REGS entries. Inside an
  // always_ff, a `for` loop is not a loop in time -- it is unrolled at
  // elaboration into NUM_REGS parallel reset connections. Nothing is
  // sequential about it; it is just a way to write eight lines once:
  //
  //     for (int i = 0; i < NUM_REGS; i++) regs_q[i] <= '0;
  //
  // This is worth internalising. `for`, `generate for`, and array literals
  // in RTL all describe structure that exists simultaneously, never steps
  // that happen one after another. If you catch yourself thinking "and then
  // the loop runs again", stop and redraw the hardware.
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int i = 0; i < NUM_REGS; i++) regs_q[i] <= '0;
    end else if (wr_i.en && wr_i.addr != '0) begin
      regs_q[wr_i.addr] <= wr_i.data;
    end
  end
  // --------------------------------------------------------------------------
  // TODO 2b -- the two combinational read ports, WITHOUT bypass for now.
  //
  //   rs1_data_o = (rs1_addr_i == 0) ? '0 : regs_q[rs1_addr_i];
  //
  // and the same for rs2. Get this working and passing the first group of
  // testbench checks before you touch part (c).
  // --------------------------------------------------------------------------

  // --------------------------------------------------------------------------
  // TODO 2c -- write-to-read bypass (also called read-during-write forwarding).
  //
  // THE PROBLEM. Suppose this cycle the write port is writing 42 into r3,
  // and at the same time a read port is asking for r3. What should come out?
  //
  // Without bypass: the OLD value. The write does not land until the clock
  // edge, and the read is combinational, so the read sees the register as it
  // is right now -- stale. In a pipelined CPU this is exactly the data hazard
  // you will spend a lecture on: an instruction reads a register one cycle
  // before the instruction ahead of it finishes writing it, and silently gets
  // the wrong operand.
  //
  // THE FIX. Detect the collision combinationally and mux in the new data:
  //
  //     "am I reading the same register that is being written, and is the
  //      write actually enabled, and is it not r0?"
  //      -> yes: return wr_i.data.   no: return regs_q[addr].
  //
  // Implement this for BOTH read ports, gated by bypass_en_i so the testbench
  // can check your behaviour with it on and with it off. All three conditions
  // matter; the testbench checks each one, including the r0 case (a bypassed
  // read of r0 must still return 0, never the written data).
  //
  // The cost: the read path now has a comparator and an extra mux in it, on
  // top of the array mux -- and the read path was already a critical path.
  // Bypassing is not free, it is a cycle of latency traded for some delay.
  // That is why it is a parameter here and an architectural decision in a
  // real design.
  // --------------------------------------------------------------------------

    logic rs1_bypass, rs2_bypass;

  assign rs1_bypass = bypass_en_i && wr_i.en && (wr_i.addr == rs1_addr_i);
  assign rs2_bypass = bypass_en_i && wr_i.en && (wr_i.addr == rs2_addr_i);

  assign rs1_data_o = (rs1_addr_i == '0) ? '0
                    : rs1_bypass         ? wr_i.data
                    :                      regs_q[rs1_addr_i];
  assign rs2_data_o = (rs2_addr_i == '0) ? '0
                    : rs2_bypass         ? wr_i.data
                    :                      regs_q[rs2_addr_i];


endmodule

// ============================================================================
// Problem 1 -- A finite state machine: overlapping "1101" detector
//
// One serial input bit per clock cycle. Assert `found_o` for exactly one
// cycle each time the pattern 1101 has just completed, counting OVERLAPPING
// matches.
//
//   bit stream : 1 1 0 1 1 0 1 0 0 1 1 0 1
//   cycle      : 0 1 2 3 4 5 6 7 8 9 ...
//   found_o    :       ^     ^           ^      (3 matches)
//
// Note the timing: found_o is high DURING the cycle in which the final bit of
// the pattern is being presented -- not the cycle after. That makes it a
// MEALY output (a function of the current state AND the current input), which
// is why it is driven from the combinational block below rather than from a
// register.
//
// The alternative is a MOORE output: add a fifth state meaning "just matched"
// and drive found_o purely from the state register. That version is one cycle
// later and costs an extra state, but found_o is then a registered signal with
// no combinational path from bit_i -- which matters if something downstream is
// timing-critical. Mealy is asked for here; the trade is worth knowing.
//
// "Overlapping" is the interesting word. After the match that ends at cycle 3,
// the tail of that match (the trailing `1`) is also the HEAD of the next
// possible match. A detector that resets to IDLE after a hit would miss the
// match at cycle 6 entirely. Your state machine must fall back to the longest
// prefix of the pattern that is still alive, not all the way to the start.
//
// ---------------------------------------------------------------------------
// The standard two-block FSM pattern. Learn this shape; you will write it a
// few hundred times.
//
//     always_comb begin          // block 1: next-state + outputs
//         state_d = state_q;     //   default: hold (no latch, no surprises)
//         case (state_q) ...
//     end
//
//     always_ff @(posedge clk) begin   // block 2: the state register
//         if (!rst_n) state_q <= S_IDLE;
//         else        state_q <= state_d;
//     end
//
// Why split it in two? Because one block is pure combinational logic and the
// other is exactly one register. Written this way, you can read the hardware
// straight off the page: one cloud, one box. Cramming both into a single
// always_ff works for small FSMs and becomes unreadable the moment you add
// a Mealy output or a second state variable.
// ============================================================================
module p1_seq_detect (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  logic       bit_i,       // one bit of the stream, per cycle
    output logic       found_o,     // 1-cycle pulse on each completed match
    output logic [7:0] count_o      // how many matches so far (saturates at 255)
);

  // --------------------------------------------------------------------------
  // State encoding. Each state means "the longest prefix of 1101 that the
  // stream currently ends with".
  //
  //   S_IDLE  : no useful prefix
  //   S_1     : stream ends with      1
  //   S_11    : stream ends with     11
  //   S_110   : stream ends with    110
  //
  // There is deliberately no S_1101 state. Think about why before you look at
  // the hint: once the fourth bit arrives you can emit `found_o` and move
  // directly to whatever prefix the stream now ends with. Adding a fifth
  // state that exists for one cycle and then immediately leaves is a common
  // and harmless beginner move, but it is extra hardware for nothing.
  //
  // Using an enum rather than raw 2'b01 means your waveform viewer prints
  // S_110 instead of 10, which during debugging is worth a great deal.
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    S_IDLE = 2'b00,
    S_1    = 2'b01,
    S_11   = 2'b10,
    S_110  = 2'b11
  } state_e;

  state_e state_q, state_d;

  logic [7:0] count_q;

  // --------------------------------------------------------------------------
  // TODO 1a -- next state and output logic.
  //
  // Fill in the case statement. For each state, decide where a 0 and a 1
  // take you, and whether the transition completes a match.
  //
  // Work through it on paper first. The three transitions people get wrong:
  //
  //   * S_1 on another 1  -> you now end with "11", NOT back to the start.
  //   * S_11 on another 1 -> you still only end with "11" (the longest live
  //                          prefix). Staying put is the right answer.
  //   * S_110 on a 1      -> MATCH. And the stream now ends with "1", which
  //                          is itself a live prefix -- this is the whole
  //                          point of overlapping detection.
  //
  // Keep the `state_d = state_q;` default at the top. It is the same
  // default-then-override habit from the lab, and here it also guarantees
  // every path assigns state_d, so you cannot infer a latch.
  // --------------------------------------------------------------------------
  always_comb begin
    state_d = state_q;   // default: hold
    found_o = 1'b0;      // default: no match this cycle

    case (state_q)
    S_IDLE: begin
      if (bit_i) state_d = S_1;
        else       state_d = S_IDLE;
      end

      S_1: begin
        if (bit_i) state_d = S_11;
        else       state_d = S_IDLE;
      end

      S_11: begin
        if (bit_i) state_d = S_11;
        else       state_d = S_110;
      end

      S_110: begin
        if (bit_i) begin
          found_o = 1'b1;
          state_d = S_1;
        end else begin
          state_d = S_IDLE;
        end
      end

      default: begin
        state_d = S_IDLE;
      end
    endcase
    end

  // --------------------------------------------------------------------------
  // TODO 1b -- the state register. Reset to S_IDLE, otherwise take state_d.
  // Two lines.
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (!rst_ni) state_q <= S_IDLE;
    else         state_q <= state_d;
  end

  // --------------------------------------------------------------------------
  // TODO 1c -- the match counter.
  //
  // Increment on every cycle where found_o is high. SATURATE at 8'hFF rather
  // than wrapping to 0.
  //
  // Saturation versus wrapping is a real design decision, not a detail. A
  // counter that wraps silently reports "2 matches" after 258 of them, and
  // you will believe it. A saturating counter reports 255 and you know to
  // widen it. When a counter exists to be read by a human or by software,
  // saturate; when it is an index into a 2^N-entry structure, wrapping is
  // exactly what you want.
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      count_q <= '0;
    end else if (found_o && count_q != 8'hFF) begin
      count_q <= count_q + 8'd1;
    end
  end

  assign count_o = count_q;

endmodule

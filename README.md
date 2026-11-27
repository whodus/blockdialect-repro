# Reproducing BlockDialect's MAC area results with open-source tools

This repo reproduces the MAC area comparison (Table 5) from

> W. Jang and T. Tambe, "BlockDialect: Block-wise Fine-grained Mixed Format
> Quantization for Energy-Efficient LLM Inference," ICML 2025.
> https://arxiv.org/abs/2501.01144

The paper synthesized its MACs with Synopsys Design Compiler. This repo uses
open-source tools instead (Yosys + ABC) with the same Nangate 45nm cell
library, 500 MHz target, and 64-term dot products. All designs are checked
bit-exactly in simulation before synthesis.

*Work in progress.*

## Results

Area in µm², Nangate45 typical corner, 2000 ps target, Yosys default
multiplier mapping, hierarchy kept so the multiplier and accumulator are
reported separately (as in the paper's Table 5).

"Mul + Acc" is the multiplier plus accumulator, excluding input registers:
the paper's multiplier and accumulator add up to within 8 µm² of its
reported totals, so its totals appear not to include them. "vs INT8"
compares each design to INT8 from the same source.

| Design | Multiplier | Accumulator | Mul + Acc | vs INT8 | Input regs |
|---|---|---|---|---|---|
| INT4, paper | 62.51 | 138.59 | 201.10 | 0.368 | — |
| INT4, Yosys | 106.93 | 169.97 | 276.91 | 0.387 | 40.70 |
| INT5, paper | 101.88 | 171.04 | 272.92 | 0.499 | — |
| INT5, Yosys | 175.03 | 189.66 | 364.69 | 0.510 | 49.74 |
| INT8, paper | 301.91 | 244.72 | 546.63 | 1.000 | — |
| INT8, Yosys | 446.88 | 268.66 | 715.54 | 1.000 | 76.87 |
| FP4, paper | 71.55 | 171.04 | 242.59 | 0.444 | — |
| FP4, Yosys (FP-style mul) | 36.71 | 221.58 | 258.29 | 0.361 | 40.70 |
| FP4, Yosys (integer-style mul) | 60.38 | 221.58 | 281.96 | 0.394 | 40.70 |
| DialectFP4, paper | 63.31 | 184.87 | 248.18 | 0.454 | — |
| DialectFP4, Yosys | 73.15 | 221.58 | 294.73 | 0.412 | 49.74 |

All designs meet the 500 MHz target with about 2× margin (see
[Timing](#timing)).

### Findings

1. **The integer baselines reproduce the paper's ratios.** INT4 and INT5
   land within 0.02 of the paper's area relative to INT8 (within 0.04
   with a flattened hierarchy), even though absolute areas are
   1.31–1.38× larger. Most of that absolute gap is in the multiplier
   (1.48–1.72× the paper's); accumulators are 1.10–1.23×.

2. **DialectFP4 is well under half of INT8, as the paper reports:** 0.412×
   here vs 0.454× in the paper, and 0.319× with a flattened hierarchy.

3. **DialectFP4 and FP4 come out about the same size, consistent with the
   paper, but the FP4 multiplier is smaller, unlike in the paper.** The
   paper does not describe its FP4 multiplier, so two styles were built
   (see `rtl/fp4_mac.v`). Depending on that style and on whether the
   hierarchy is flattened, the DialectFP4 MAC is 0.90–1.14× the FP4 MAC
   (paper: 1.02×). Which one is larger depends on these choices, so this
   repo cannot resolve a difference between them. What holds in every
   setting is that the FP4 multiplier on its own is smaller than the
   DialectFP4 one (36.7–60.4 vs 73.2 µm²), while in the paper it is
   larger (71.55 vs 63.31). A likely reason: E2M1 has only 8 magnitudes
   (3 bits), while a DialectFP4 operand has 16 (4 bits).

4. **The DialectFP4 accumulator is larger than INT4's and INT5's, as in
   the paper** (1.30× INT4 here vs 1.33× in the paper). In this design the
   cost comes from converting the sign-magnitude product to two's
   complement inside the accumulator (add or subtract), consistent with
   the paper's multiplier containing only an XOR for the sign. This
   comparison depends on that design choice and needs the hierarchical
   split. FP4 uses the same accumulator here; in the paper FP4's
   accumulator (171.04) is smaller and identical to INT5's, which
   suggests a different FP4 datapath.

### Sensitivity to synthesis settings

Multiplier + accumulator area (flattened: total minus input registers),
and the ratio to INT8 under the same setting.

| Design | Default | vs INT8 | Booth | vs INT8 | Flattened | vs INT8 |
|---|---|---|---|---|---|---|
| INT4 | 276.91 | 0.387 | 244.45 | 0.400 | 352.72 | 0.408 |
| INT5 | 364.69 | 0.510 | 339.68 | 0.555 | 437.04 | 0.505 |
| INT8 | 715.54 | 1.000 | 611.53 | 1.000 | 865.03 | 1.000 |
| FP4 (FP-style mul) | 258.29 | 0.361 | 258.29 | 0.422 | 273.98 | 0.317 |
| FP4 (integer-style mul) | 281.96 | 0.394 | 327.45 | 0.535 | 305.90 | 0.354 |
| DialectFP4 | 294.73 | 0.412 | 315.21 | 0.515 | 276.11 | 0.319 |

- **Booth** (`synth -booth`) brings the INT8 multiplier much closer to the
  paper's (1.14× vs 1.48×) but makes the small 4-bit multipliers larger,
  so it moves every ratio further from the paper's. The FP-style FP4
  multiplier has no multiplier large enough for Booth to apply.
- **Flattening** lets Yosys merge each multiply and add into a single
  multiply-accumulate block before mapping. That makes the INT designs
  20–27% larger and DialectFP4 about 6% smaller, which is why it
  changes the DialectFP4/FP4 ordering (finding 3).
- **The clock target** has no effect: 1000, 2000 and 5000 ps targets give
  identical areas, because every design meets timing easily.

The default setting is used for the main results because it keeps the
multiplier/accumulator split that the paper reports.

### Timing

Longest register-to-register logic delay, estimated by ABC after
flattened mapping (Nangate45 typical, no wire load model, excluding
flip-flop clock-to-Q and setup):

| INT4 | INT5 | INT8 | FP4 | FP4 (int-style) | DialectFP4 |
|---|---|---|---|---|---|
| 652 ps | 875 ps | 1020 ps | 856 ps | 807 ps | 810 ps |

All are about half of the 2000 ps clock period.

## Repo layout

```
rtl/      MAC designs (Verilog): int_mac.v (INT4/5/8), fp4_mac.v, dialectfp4_mac.v
tb/       self-checking testbenches
synth/    synthesis and timing scripts; reports in synth/results/
```

## Reproducing

Requires Yosys and Icarus Verilog, plus `NangateOpenCellLibrary_typical.lib`
from [OpenROAD-flow-scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts)
(`flow/platforms/nangate45/lib/`) in the repo root.

```bash
# Simulation (bit-exact checks)
for w in 4 5 8; do
  iverilog -P int_mac_tb.WIDTH=$w -o sim.vvp rtl/int_mac.v tb/int_mac_tb.v && vvp sim.vvp
done
for st in 0 1; do
  iverilog -P fp4_mac_tb.INT_STYLE=$st -o sim.vvp rtl/fp4_mac.v tb/fp4_mac_tb.v && vvp sim.vvp
done
iverilog -o sim.vvp rtl/dialectfp4_mac.v tb/dialectfp4_mac_tb.v && vvp sim.vvp

# Synthesis and timing (reports land in synth/results/)
for d in int4 int5 int8 fp4 fp4int dialectfp4; do
  synth/synth.sh $d
  synth/synth.sh $d booth
  synth/synth.sh $d flat
  synth/timing.sh $d
done

# Clock-target check, e.g.
PERIOD_PS=1000 synth/synth.sh int8
```

## Limitations

- Synthesis only: no place-and-route, no wire load model, and no power
  numbers.
- Timing is ABC's synthesis-time estimate, not signoff static timing
  analysis.
- The FP4 multiplier and the placement of sign handling are design
  choices, since the paper does not describe them; results for FP4 in
  particular depend on them (finding 3).
- Area excludes the DialectFP4 dequantization (3-bit index + dialect ID
  to 4-bit integer), as in the paper's Table 5.

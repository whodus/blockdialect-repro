#!/usr/bin/env bash
# Estimate the critical combinational path of one MAC design.
#
#   usage (from repo root):  synth/timing.sh <design>
#     design: int4 | int5 | int8 | fp4 | fp4int | dialectfp4
#
# The design is flattened and mapped by ABC with a 2000 ps target, then
# ABC's `stime` reports the longest register-to-register logic delay
# (Nangate45 typical corner, no wire load model). Flip-flop clock-to-Q
# and setup time are not included. This is a synthesis estimate, not
# signoff static timing analysis.
set -euo pipefail

DESIGN="${1:?usage: synth/timing.sh <int4|int5|int8|fp4|fp4int|dialectfp4>}"
LIB="NangateOpenCellLibrary_typical.lib"
OUT="synth/results"
mkdir -p "$OUT"

case "$DESIGN" in
  int[0-9]*)
    SRC="rtl/int_mac.v"; TOP="int_mac"
    PARAM="chparam -set WIDTH ${DESIGN#int} int_mac" ;;
  fp4)
    SRC="rtl/fp4_mac.v"; TOP="fp4_mac"; PARAM="" ;;
  fp4int)
    SRC="rtl/fp4_mac.v"; TOP="fp4_mac"
    PARAM="chparam -set INT_STYLE 1 fp4_mac" ;;
  dialectfp4)
    SRC="rtl/dialectfp4_mac.v"; TOP="dialectfp4_mac"; PARAM="" ;;
  *)
    echo "unknown design: $DESIGN" >&2; exit 1 ;;
esac

yosys -q -l "$OUT/${DESIGN}_timing.log" -p "
  read_verilog ${SRC}
  ${PARAM}
  synth -flatten -top ${TOP}
  dfflibmap -liberty ${LIB}
  abc -liberty ${LIB} -D 2000 -script synth/abc_timing.script
" </dev/null

# Yosys logs the ABC script by absolute path; keep logs machine-independent.
sed -i.bak "s|$PWD/||g" "$OUT/${DESIGN}_timing.log" && rm -f "$OUT/${DESIGN}_timing.log.bak"

printf "%-11s critical path: %s ps\n" "$DESIGN" \
  "$(grep -o 'Delay = *[0-9.]*' "$OUT/${DESIGN}_timing.log" | tail -1 | grep -o '[0-9.]*$')"

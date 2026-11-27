#!/usr/bin/env bash
# Synthesize one MAC design with Yosys + Nangate45 and save its area report.
#
#   usage (from repo root):  synth/synth.sh <design> [booth|flat]
#     design: int4 | int5 | int8 | fp4 | fp4int | dialectfp4
#     booth:  use Yosys's Booth-encoded multiplier (sensitivity check)
#     flat:   flatten the hierarchy before synthesis (sensitivity check)
#
# By default hierarchy is kept so the area report breaks out the
# multiplier and accumulator separately, as in Table 5 of the BlockDialect
# paper. Target clock: 500 MHz (2000 ps); override with PERIOD_PS=<ps>.
set -euo pipefail

DESIGN="${1:?usage: synth/synth.sh <int4|int5|int8|fp4|fp4int|dialectfp4> [booth|flat]}"
MODE="${2:-default}"
LIB="NangateOpenCellLibrary_typical.lib"
PERIOD_PS="${PERIOD_PS:-2000}"
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

case "$MODE" in
  default) SYNTH_FLAGS="";         TAG="$DESIGN" ;;
  booth)   SYNTH_FLAGS="-booth";   TAG="${DESIGN}_booth" ;;
  flat)    SYNTH_FLAGS="-flatten"; TAG="${DESIGN}_flat" ;;
  *) echo "unknown mode: $MODE" >&2; exit 1 ;;
esac

yosys -q -l "$OUT/${TAG}.log" -p "
  read_verilog ${SRC}
  ${PARAM}
  synth ${SYNTH_FLAGS} -top ${TOP}
  dfflibmap -liberty ${LIB}
  abc -liberty ${LIB} -D ${PERIOD_PS}
  opt_clean
  tee -o ${OUT}/${TAG}_area.txt stat -liberty ${LIB}
"

grep -E "Chip area" "$OUT/${TAG}_area.txt" \
  | sed -E 's/\$paramod[^ ]*\\([a-z0-9_]+)[^:]*/\1/'

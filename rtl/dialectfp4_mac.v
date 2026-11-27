// dialectfp4_mac.v
//
// DialectFP4 multiply-accumulate unit, reproducing the "Ours (DialectFP4)"
// row of Table 5 in
//
//   W. Jang and T. Tambe, "BlockDialect: Block-wise Fine-grained Mixed
//   Format Quantization for Energy-Efficient LLM Inference," ICML 2025.
//   https://arxiv.org/abs/2501.01144
//
// Every DialectFP4 value is a multiple of 0.5 in [0, 7.5], so after
// dequantization each operand is a sign bit plus a 4-bit unsigned integer
// n, representing (-1)^s * 0.5 * n. The paper's MAC is a 4-bit unsigned
// multiplier plus an XOR for the sign bit; the 3-bit-index-to-integer
// lookup happens before the MAC (dequantization) and is not part of it.
//
// The product of two operands is (-1)^(sa^sb) * 0.25 * (na * nb). The
// accumulator sums the integer na * nb with its sign; the factor 0.25
// (the paper's 2-bit right shift) is applied once to the final result by
// reading acc as a fixed-point number with 2 fractional bits.
//
// Accumulator width for 64 terms:
//   max |na * nb| = 15 * 15 = 225 < 2^8
//   64 * 225 = 14400 < 2^14, so 8 + 6 magnitude bits + 1 sign = 15 bits.
//
// The conditional negation (sign-magnitude to two's complement) is placed
// in the accumulator: it adds or subtracts the unsigned product.
//
// Pipeline (two clock edges from input to accumulator), same as int_mac:
//   edge 1: operands and valid are captured in input registers
//   edge 2: acc <= acc +/- na_r * nb_r   (when valid_r is high)

// 4-bit unsigned multiplier plus sign XOR.
module dfp4_mul (
    input  wire       sa,
    input  wire [3:0] na,
    input  wire       sb,
    input  wire [3:0] nb,
    output wire       sp,
    output wire [7:0] np
);
    assign np = na * nb;
    assign sp = sa ^ sb;
endmodule

// Signed accumulator fed with a sign-magnitude product.
module dfp4_acc #(
    parameter AW = 15
) (
    input  wire                 clk,
    input  wire                 clear,
    input  wire                 en,
    input  wire                 sp,
    input  wire [7:0]           np,
    output reg  signed [AW-1:0] acc
);
    wire signed [AW-1:0] np_ext = {{(AW-8){1'b0}}, np};

    always @(posedge clk) begin
        if (clear)
            acc <= 0;
        else if (en)
            acc <= sp ? acc - np_ext : acc + np_ext;
    end
endmodule

// Top level: input registers -> multiplier -> accumulator.
// acc holds the dot product in units of 0.25 (2 fractional bits).
module dialectfp4_mac (
    input  wire              clk,
    input  wire              clear,
    input  wire              valid,
    input  wire              sa,
    input  wire [3:0]        na,
    input  wire              sb,
    input  wire [3:0]        nb,
    output wire signed [14:0] acc
);
    reg       sa_r, sb_r, valid_r;
    reg [3:0] na_r, nb_r;
    wire       sp;
    wire [7:0] np;

    always @(posedge clk) begin
        sa_r    <= sa;
        na_r    <= na;
        sb_r    <= sb;
        nb_r    <= nb;
        valid_r <= valid;
    end

    dfp4_mul u_mul (
        .sa(sa_r), .na(na_r), .sb(sb_r), .nb(nb_r), .sp(sp), .np(np)
    );

    dfp4_acc #(.AW(15)) u_acc (
        .clk(clk), .clear(clear), .en(valid_r), .sp(sp), .np(np), .acc(acc)
    );
endmodule

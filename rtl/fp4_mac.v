// fp4_mac.v
//
// FP4 (E2M1) multiply-accumulate unit, reproducing the "FP4" row of
// Table 5 in
//
//   W. Jang and T. Tambe, "BlockDialect: Block-wise Fine-grained Mixed
//   Format Quantization for Energy-Efficient LLM Inference," ICML 2025.
//   https://arxiv.org/abs/2501.01144
//
// E2M1 follows the OCP Microscaling (MX) spec: 1 sign bit, 2 exponent
// bits (bias 1), 1 mantissa bit, with subnormals and no inf/NaN.
// Representable magnitudes:
//
//   {e,m}:  00   01   10   11   100  101  110  111
//   value:  0    0.5  1    1.5  2    3    4    6
//
// The paper does not describe its FP4 multiplier, so the multiplier is a
// design choice. Two styles are provided (parameter INT_STYLE), both kept
// as close to the DialectFP4 MAC as possible so that FP4 and DialectFP4
// differ only in the multiplier. Both produce a sign-magnitude product
// with 2 fractional bits; the sign is an XOR.
//
//   INT_STYLE = 0 (floating-point style, default):
//     multiply the 2-bit significands (hidden bit + mantissa), add the
//     exponents, and shift the 4-bit significand product into place.
//       value_x2   = sig * 2^(e_eff - 1),  sig = {e != 0, m},  e_eff = max(e, 1)
//       product_x4 = (sig_a * sig_b) << (e_eff_a + e_eff_b - 2)
//
//   INT_STYLE = 1 (integer style):
//     decode each magnitude to a 4-bit integer (value x 2, one of
//     0, 1, 2, 3, 4, 6, 8, 12), then use the same 4-bit unsigned
//     multiplier as the DialectFP4 MAC.
//
//   Max magnitude 6 * 6 = 36 -> 144 quarters, 8 bits.
//
//   Accumulator: identical to the DialectFP4 one (sign-magnitude input,
//   add or subtract, 15 bits). 64 * 144 = 9216 < 2^14, so 15 bits signed
//   covers FP4 too, and both 4-bit formats use the same accumulator.
//
// acc holds the dot product in units of 0.25 (2 fractional bits).
//
// Pipeline (two clock edges from input to accumulator), same as int_mac:
//   edge 1: operands and valid are captured in input registers
//   edge 2: acc <= acc +/- product   (when valid_r is high)

// E2M1 x E2M1 multiplier producing a sign-magnitude fixed-point product.
module fp4_mul #(
    parameter INT_STYLE = 0
) (
    input  wire       sa,
    input  wire [1:0] ea,
    input  wire       ma,
    input  wire       sb,
    input  wire [1:0] eb,
    input  wire       mb,
    output wire       sp,
    output wire [7:0] np
);
    assign sp = sa ^ sb;

    generate
        if (INT_STYLE == 0) begin : g_fp
            wire [1:0] sig_a = {ea != 2'b00, ma};
            wire [1:0] sig_b = {eb != 2'b00, mb};
            wire [1:0] eff_a = (ea == 2'b00) ? 2'd1 : ea;
            wire [1:0] eff_b = (eb == 2'b00) ? 2'd1 : eb;

            wire [3:0] sig_p = sig_a * sig_b;          // 0..9
            wire [2:0] shamt = eff_a + eff_b - 3'd2;   // 0..4

            assign np = {4'b0000, sig_p} << shamt;
        end else begin : g_int
            wire [3:0] na = fp4_to_int({ea, ma});
            wire [3:0] nb = fp4_to_int({eb, mb});

            assign np = na * nb;
        end
    endgenerate

    // E2M1 magnitude {e, m} -> value x 2 as a 4-bit unsigned integer.
    function [3:0] fp4_to_int(input [2:0] em);
        case (em)
            3'd0: fp4_to_int = 4'd0;
            3'd1: fp4_to_int = 4'd1;
            3'd2: fp4_to_int = 4'd2;
            3'd3: fp4_to_int = 4'd3;
            3'd4: fp4_to_int = 4'd4;
            3'd5: fp4_to_int = 4'd6;
            3'd6: fp4_to_int = 4'd8;
            3'd7: fp4_to_int = 4'd12;
        endcase
    endfunction
endmodule

// Signed accumulator fed with a sign-magnitude product.
// Same logic as dfp4_acc in dialectfp4_mac.v.
module fp4_acc #(
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
// Each operand is a 4-bit E2M1 code {sign, exp[1:0], mant}.
module fp4_mac #(
    parameter INT_STYLE = 0
) (
    input  wire               clk,
    input  wire               clear,
    input  wire               valid,
    input  wire [3:0]         a,
    input  wire [3:0]         b,
    output wire signed [14:0] acc
);
    reg [3:0] a_r, b_r;
    reg       valid_r;
    wire       sp;
    wire [7:0] np;

    always @(posedge clk) begin
        a_r     <= a;
        b_r     <= b;
        valid_r <= valid;
    end

    fp4_mul #(.INT_STYLE(INT_STYLE)) u_mul (
        .sa(a_r[3]), .ea(a_r[2:1]), .ma(a_r[0]),
        .sb(b_r[3]), .eb(b_r[2:1]), .mb(b_r[0]),
        .sp(sp), .np(np)
    );

    fp4_acc #(.AW(15)) u_acc (
        .clk(clk), .clear(clear), .en(valid_r), .sp(sp), .np(np), .acc(acc)
    );
endmodule

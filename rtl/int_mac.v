// int_mac.v
//
// Signed integer multiply-accumulate unit, used as the INT4 / INT5 / INT8
// baseline when reproducing the MAC area comparison (Table 5) of
//
//   W. Jang and T. Tambe, "BlockDialect: Block-wise Fine-grained Mixed
//   Format Quantization for Energy-Efficient LLM Inference," ICML 2025.
//   https://arxiv.org/abs/2501.01144
//
// Following the paper, each MAC accumulates a 64-term dot product. The
// accumulator is therefore sized as product width + log2(64) bits:
//
//   WIDTH = 8:  max |product| = (-128)(-128) = 2^14
//               64 * 2^14 = 2^20, which needs 22 bits signed (2*WIDTH + 6).
//
// The multiplier and accumulator are separate modules so that synthesis
// reports their areas separately, matching the breakdown in Table 5.
//
// Pipeline (two clock edges from input to accumulator):
//   edge 1: a, b, valid are captured in input registers
//   edge 2: acc <= acc + a_r * b_r   (when valid_r is high)

// Combinational signed multiplier.
module int_mul #(
    parameter WIDTH = 8
) (
    input  wire signed [WIDTH-1:0]   a,
    input  wire signed [WIDTH-1:0]   b,
    output wire signed [2*WIDTH-1:0] p
);
    assign p = a * b;
endmodule

// Signed accumulator with synchronous clear. The PW-bit product is
// sign-extended to AW bits before the add.
module int_acc #(
    parameter PW = 16,   // product width
    parameter AW = 22    // accumulator width
) (
    input  wire                 clk,
    input  wire                 clear,
    input  wire                 en,
    input  wire signed [PW-1:0] p,
    output reg  signed [AW-1:0] acc
);
    always @(posedge clk) begin
        if (clear)
            acc <= 0;
        else if (en)
            acc <= acc + p;
    end
endmodule

// Top level: input registers -> multiplier -> accumulator.
module int_mac #(
    parameter WIDTH = 8
) (
    input  wire                      clk,
    input  wire                      clear,
    input  wire                      valid,
    input  wire signed [WIDTH-1:0]   a,
    input  wire signed [WIDTH-1:0]   b,
    output wire signed [2*WIDTH+5:0] acc
);
    reg  signed [WIDTH-1:0]   a_r, b_r;
    reg                       valid_r;
    wire signed [2*WIDTH-1:0] p;

    always @(posedge clk) begin
        a_r     <= a;
        b_r     <= b;
        valid_r <= valid;
    end

    int_mul #(.WIDTH(WIDTH)) u_mul (
        .a(a_r), .b(b_r), .p(p)
    );

    int_acc #(.PW(2*WIDTH), .AW(2*WIDTH+6)) u_acc (
        .clk(clk), .clear(clear), .en(valid_r), .p(p), .acc(acc)
    );
endmodule

// fp4_mac_tb.v
//
// Self-checking testbench for fp4_mac. Operands are 4-bit E2M1 codes
// {sign, exp[1:0], mant}. The reference model decodes each code with a
// value table (independent of the RTL's exponent/significand arithmetic)
// and checks the accumulator in units of 0.25.
//
// Directed tests: all 256 single products, accumulation across calls,
// clear, and the 64-term worst cases in both directions.
// Random tests: 500 dot products of 64 random terms each.
//
// Run from the repo root (INT_STYLE selects the multiplier, default 0):
//   iverilog -P fp4_mac_tb.INT_STYLE=1 -o sim.vvp rtl/fp4_mac.v tb/fp4_mac_tb.v && vvp sim.vvp
`timescale 1ns/1ps

module fp4_mac_tb;
    parameter  INT_STYLE = 0;
    localparam N     = 64;
    localparam NRAND = 500;

    reg               clk = 0;
    reg               clear = 0;
    reg               valid = 0;
    reg  [3:0]        a = 0, b = 0;
    wire signed [14:0] acc;

    integer errors = 0;
    integer i, j, k, expected;
    integer seed = 1;
    reg [3:0] ra, rb;

    // Magnitude x2 for each 3-bit {exp, mant}: 0, 0.5, 1, 1.5, 2, 3, 4, 6.
    integer mag_x2 [0:7];
    initial begin
        mag_x2[0] = 0;  mag_x2[1] = 1;  mag_x2[2] = 2;  mag_x2[3] = 3;
        mag_x2[4] = 4;  mag_x2[5] = 6;  mag_x2[6] = 8;  mag_x2[7] = 12;
    end

    // Signed value x2 of an E2M1 code.
    function integer val_x2(input [3:0] code);
        val_x2 = code[3] ? -mag_x2[code[2:0]] : mag_x2[code[2:0]];
    endfunction

    fp4_mac #(.INT_STYLE(INT_STYLE)) dut (
        .clk(clk), .clear(clear), .valid(valid), .a(a), .b(b), .acc(acc)
    );

    always #1 clk = ~clk;   // 2 ns period = 500 MHz

    task do_clear;
        begin
            @(negedge clk); clear = 1; valid = 0;
            @(negedge clk); clear = 0;
        end
    endtask

    task send(input [3:0] x, input [3:0] y);
        begin
            @(negedge clk); a = x; b = y; valid = 1;
        end
    endtask

    task check(input integer exp_q, input [255:0] name, input verbose);
        begin
            @(negedge clk); valid = 0;
            @(negedge clk);
            @(negedge clk);
            if (acc !== exp_q) begin
                errors = errors + 1;
                $display("FAIL %0s: got %0d, expected %0d", name, acc, exp_q);
            end else if (verbose) begin
                $display("pass %0s: %0d (= %0.2f)", name, acc, acc / 4.0);
            end
        end
    endtask

    initial begin
        #0;  // let the value table initialize
        $display("fp4_mac INT_STYLE=%0d", INT_STYLE);

        // 1.5 * -3 = -4.5  ->  -18 quarters
        do_clear;
        send(4'b0011, 4'b1101);
        check(-18, "single product", 1);

        // -4.5 + (-0.5)(-6) = -1.5  ->  -6 quarters  (subnormal x max)
        send(4'b1001, 4'b1111);
        check(-6, "accumulates", 1);

        do_clear;
        check(0, "clear", 1);

        // Every pair of codes, one product at a time.
        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 16; j = j + 1) begin
                do_clear;
                send(i, j);
                check(val_x2(i) * val_x2(j), "exhaustive product", 0);
            end
        $display("all 256 single products checked");

        // 64 * 6 * 6 = 2304  ->  9216 quarters
        do_clear;
        for (i = 0; i < N; i = i + 1) send(4'b1111, 4'b1111);
        check(9216, "64 x max positive", 1);

        // 64 * 6 * -6 = -2304  ->  -9216 quarters
        do_clear;
        for (i = 0; i < N; i = i + 1) send(4'b0111, 4'b1111);
        check(-9216, "64 x max negative", 1);

        for (k = 0; k < NRAND; k = k + 1) begin
            do_clear;
            expected = 0;
            for (i = 0; i < N; i = i + 1) begin
                ra = $random(seed);
                rb = $random(seed);
                expected = expected + val_x2(ra) * val_x2(rb);
                send(ra, rb);
            end
            check(expected, "random dot product", 0);
        end
        $display("%0d random 64-term dot products checked", NRAND);

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule

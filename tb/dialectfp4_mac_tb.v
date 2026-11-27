// dialectfp4_mac_tb.v
//
// Self-checking testbench for dialectfp4_mac. Operands are given as
// (sign, n) with value (-1)^sign * 0.5 * n; the accumulator is checked in
// units of 0.25, i.e. sum of (-1)^(sa^sb) * na * nb.
//
// Directed tests: single product, accumulation across calls, clear,
// zero operands (including -0), and the 64-term worst cases in both
// directions. Random tests: 500 dot products of 64 random terms each.
//
// Run from the repo root:
//   iverilog -o sim.vvp rtl/dialectfp4_mac.v tb/dialectfp4_mac_tb.v && vvp sim.vvp
`timescale 1ns/1ps

module dialectfp4_mac_tb;
    localparam N     = 64;
    localparam NRAND = 500;

    reg               clk = 0;
    reg               clear = 0;
    reg               valid = 0;
    reg               sa = 0, sb = 0;
    reg  [3:0]        na = 0, nb = 0;
    wire signed [14:0] acc;

    integer errors = 0;
    integer i, k, expected;
    integer seed = 1;
    reg       rsa, rsb;
    reg [3:0] rna, rnb;

    dialectfp4_mac dut (
        .clk(clk), .clear(clear), .valid(valid),
        .sa(sa), .na(na), .sb(sb), .nb(nb), .acc(acc)
    );

    always #1 clk = ~clk;   // 2 ns period = 500 MHz

    task do_clear;
        begin
            @(negedge clk); clear = 1; valid = 0;
            @(negedge clk); clear = 0;
        end
    endtask

    task send(input s1, input [3:0] n1, input s2, input [3:0] n2);
        begin
            @(negedge clk); sa = s1; na = n1; sb = s2; nb = n2; valid = 1;
        end
    endtask

    // exp_q is the expected sum in units of 0.25.
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
        // 3.5 * -1.5 = -5.25  ->  -21 quarters  (n = 7 and 3)
        do_clear;
        send(0, 7, 1, 3);
        check(-21, "single product", 1);

        // -5.25 + (-2.5)(-2.0) = -0.25  ->  -1 quarter  (n = 5 and 4)
        send(1, 5, 1, 4);
        check(-1, "accumulates", 1);

        do_clear;
        check(0, "clear", 1);

        // Zero and negative zero contribute nothing.
        do_clear;
        send(0, 0, 0, 15); send(1, 0, 0, 15); send(1, 9, 1, 0);
        check(0, "zero operands", 1);

        // 64 * 7.5 * 7.5 = 3600  ->  14400 quarters
        do_clear;
        for (i = 0; i < N; i = i + 1) send(1, 15, 1, 15);
        check(14400, "64 x max positive", 1);

        // 64 * 7.5 * -7.5 = -3600  ->  -14400 quarters
        do_clear;
        for (i = 0; i < N; i = i + 1) send(0, 15, 1, 15);
        check(-14400, "64 x max negative", 1);

        for (k = 0; k < NRAND; k = k + 1) begin
            do_clear;
            expected = 0;
            for (i = 0; i < N; i = i + 1) begin
                {rsa, rna} = $random(seed);
                {rsb, rnb} = $random(seed);
                expected = expected + ((rsa ^ rsb) ? -(rna * rnb) : (rna * rnb));
                send(rsa, rna, rsb, rnb);
            end
            check(expected, "random dot product", 0);
        end
        $display("%0d random 64-term dot products checked", NRAND);

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule

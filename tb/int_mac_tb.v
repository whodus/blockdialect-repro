// int_mac_tb.v
//
// Self-checking testbench for int_mac at any operand width.
//
// Directed tests: single product, accumulation across calls, synchronous
// clear, a mixed-sign sequence, and the 64-term worst cases in both
// directions (which exercise the full accumulator range).
// Random tests: 500 dot products of 64 random terms each, checked against
// an integer reference computed in the testbench.
//
// Run from the repo root (WIDTH defaults to 8):
//   iverilog -P int_mac_tb.WIDTH=4 -o sim.vvp rtl/int_mac.v tb/int_mac_tb.v && vvp sim.vvp
`timescale 1ns/1ps

module int_mac_tb;
    parameter WIDTH = 8;
    localparam AW     = 2*WIDTH + 6;
    localparam N      = 64;                       // terms per dot product
    localparam MINV   = -(1 <<< (WIDTH-1));       // e.g. -128 for WIDTH=8
    localparam MAXV   =  (1 <<< (WIDTH-1)) - 1;   // e.g.  127 for WIDTH=8
    localparam NRAND  = 500;

    reg                    clk = 0;
    reg                    clear = 0;
    reg                    valid = 0;
    reg  signed [WIDTH-1:0] a = 0, b = 0;
    wire signed [AW-1:0]    acc;

    integer errors = 0;
    integer i, k, x, y, expected;
    integer seed = 1;

    int_mac #(.WIDTH(WIDTH)) dut (
        .clk(clk), .clear(clear), .valid(valid), .a(a), .b(b), .acc(acc)
    );

    always #1 clk = ~clk;   // 2 ns period = 500 MHz

    // Inputs change on the falling edge so they are stable at the rising edge.
    task do_clear;
        begin
            @(negedge clk); clear = 1; valid = 0;
            @(negedge clk); clear = 0;
        end
    endtask

    task send(input integer xv, input integer yv);
        begin
            @(negedge clk); a = xv; b = yv; valid = 1;
        end
    endtask

    // Stop sending, wait for the last term to reach the accumulator, compare.
    task check(input integer exp_val, input [255:0] name, input verbose);
        begin
            @(negedge clk); valid = 0;
            @(negedge clk);
            @(negedge clk);
            if (acc !== exp_val) begin
                errors = errors + 1;
                $display("FAIL %0s: got %0d, expected %0d", name, acc, exp_val);
            end else if (verbose) begin
                $display("pass %0s: %0d", name, acc);
            end
        end
    endtask

    initial begin
        $display("int_mac WIDTH=%0d, accumulator %0d bits", WIDTH, AW);

        // 7 * -3 = -21  (operands fit in every WIDTH >= 4)
        do_clear;
        send(7, -3);
        check(-21, "single product", 1);

        // -21 + 5*4 = -1  (no clear: accumulator keeps its value)
        send(5, 4);
        check(-1, "accumulates", 1);

        do_clear;
        check(0, "clear", 1);

        // 3*2 + (-4)*3 + MAXV*MAXV
        do_clear;
        send(3, 2); send(-4, 3); send(MAXV, MAXV);
        check(6 - 12 + MAXV*MAXV, "mixed signs", 1);

        // Largest positive sum: N * (MINV * MINV)
        do_clear;
        for (i = 0; i < N; i = i + 1) send(MINV, MINV);
        check(N * MINV * MINV, "64 x max positive", 1);

        // Largest negative sum: N * (MINV * MAXV)
        do_clear;
        for (i = 0; i < N; i = i + 1) send(MINV, MAXV);
        check(N * MINV * MAXV, "64 x max negative", 1);

        // Random dot products.
        for (k = 0; k < NRAND; k = k + 1) begin
            do_clear;
            expected = 0;
            for (i = 0; i < N; i = i + 1) begin
                // Top WIDTH bits of a random 32-bit value, sign-extended:
                // uniform over [MINV, MAXV].
                x = $random(seed) >>> (32 - WIDTH);
                y = $random(seed) >>> (32 - WIDTH);
                expected = expected + x * y;
                send(x, y);
            end
            check(expected, "random dot product", 0);
        end
        $display("%0d random 64-term dot products checked", NRAND);

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule

// =============================================================
// Module      : alu_vtb
// Description : Self-checking testbench for the 8-bit ALU (alu.v)
//               Applies directed vectors covering ADD, SUB, AND, OR
//               and checks result + zero/negative/carry/overflow flags
// =============================================================

`timescale 1ns / 1ps

module alu_vtb;

    // Local opcode parameters (must match DUT encoding)
    localparam OP_ADD = 2'b00;
    localparam OP_SUB = 2'b01;
    localparam OP_AND = 2'b10;
    localparam OP_OR  = 2'b11;

    // DUT I/O
    reg  [7:0] a, b;
    reg  [1:0] op_sel;
    wire [7:0] result;
    wire       zero, negative, carry, overflow;

    // Bookkeeping
    integer pass_count;
    integer fail_count;

    // Instantiate the DUT
    alu dut (
        .a        (a),
        .b        (b),
        .op_sel   (op_sel),
        .result   (result),
        .zero     (zero),
        .negative (negative),
        .carry    (carry),
        .overflow (overflow)
    );

    // -----------------------------------------------------------
    // Task: apply a vector, wait, then check DUT outputs against
    // expected values. Reports PASS/FAIL per test case.
    // -----------------------------------------------------------
    task run_test;
        input [7:0] t_a;
        input [7:0] t_b;
        input [1:0] t_op;
        input [7:0] exp_result;
        input       exp_zero;
        input       exp_negative;
        input       exp_carry;
        input       exp_overflow;
        begin
            a      = t_a;
            b      = t_b;
            op_sel = t_op;
            #10; // allow combinational logic to settle

            if ((result   === exp_result)   &&
                (zero     === exp_zero)     &&
                (negative === exp_negative) &&
                (carry    === exp_carry)    &&
                (overflow === exp_overflow)) begin
                pass_count = pass_count + 1;
                $display("PASS: op=%0d a=%0d b=%0d -> result=%0d (Z=%b N=%b C=%b V=%b)",
                          t_op, t_a, t_b, result, zero, negative, carry, overflow);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: op=%0d a=%0d b=%0d", t_op, t_a, t_b);
                $display("      Got     -> result=%0d Z=%b N=%b C=%b V=%b",
                          result, zero, negative, carry, overflow);
                $display("      Expected-> result=%0d Z=%b N=%b C=%b V=%b",
                          exp_result, exp_zero, exp_negative, exp_carry, exp_overflow);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("========== Starting ALU Testbench ==========");

        // ---------------- ADD tests ----------------
        // Simple add, no carry/overflow
        run_test(8'd10, 8'd20, OP_ADD, 8'd30, 1'b0, 1'b0, 1'b0, 1'b0);

        // Add resulting in zero
        run_test(8'd0, 8'd0, OP_ADD, 8'd0, 1'b1, 1'b0, 1'b0, 1'b0);

        // Add causing unsigned carry-out (255 + 1 = 0, carry = 1)
        run_test(8'hFF, 8'h01, OP_ADD, 8'h00, 1'b1, 1'b0, 1'b1, 1'b0);

        // Add causing signed overflow (127 + 1 = -128 in signed view)
        run_test(8'h7F, 8'h01, OP_ADD, 8'h80, 1'b0, 1'b1, 1'b0, 1'b1);

        // Add of two negative numbers producing negative result (no overflow)
        run_test(8'hFE, 8'hFE, OP_ADD, 8'hFC, 1'b0, 1'b1, 1'b1, 1'b0);

        // ---------------- SUB tests ----------------
        // Simple subtract, no borrow
        run_test(8'd30, 8'd10, OP_SUB, 8'd20, 1'b0, 1'b0, 1'b1, 1'b0);

        // Subtract resulting in zero
        run_test(8'd15, 8'd15, OP_SUB, 8'd0, 1'b1, 1'b0, 1'b1, 1'b0);

        // Subtract causing borrow (0 - 1 = -1 => 0xFF, borrow occurs so carry = 0)
        run_test(8'h00, 8'h01, OP_SUB, 8'hFF, 1'b0, 1'b1, 1'b0, 1'b0);

        // Subtract causing signed overflow (-128 - 1 => overflow)
        run_test(8'h80, 8'h01, OP_SUB, 8'h7F, 1'b0, 1'b0, 1'b1, 1'b1);

        // ---------------- AND tests ----------------
        run_test(8'hF0, 8'h0F, OP_AND, 8'h00, 1'b1, 1'b0, 1'b0, 1'b0);
        run_test(8'hFF, 8'hAA, OP_AND, 8'hAA, 1'b0, 1'b1, 1'b0, 1'b0);

        // ---------------- OR tests ----------------
        run_test(8'hF0, 8'h0F, OP_OR, 8'hFF, 1'b0, 1'b1, 1'b0, 1'b0);
        run_test(8'h00, 8'h00, OP_OR, 8'h00, 1'b1, 1'b0, 1'b0, 1'b0);

        $display("========== Testbench Complete ==========");
        $display("Total PASS = %0d, Total FAIL = %0d", pass_count, fail_count);

        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");

        $finish;
    end

endmodule


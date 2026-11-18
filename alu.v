// =============================================================
// Module      : alu
// Description : 8-bit ALU supporting ADD, SUB, AND, OR
//               Generates Zero, Negative, Carry, Overflow flags
// Opcode Map  : 2'b00 -> ADD
//               2'b01 -> SUB
//               2'b10 -> AND
//               2'b11 -> OR
// =============================================================

module alu (
    input  wire [7:0] a,        // Operand A
    input  wire [7:0] b,        // Operand B
    input  wire [1:0] op_sel,   // Operation select
    output reg  [7:0] result,    // ALU result
    output wire       zero,      // Result == 0
    output wire       negative,  // Result MSB (sign bit)
    output reg        carry,     // Carry-out / borrow-not
    output reg        overflow   // Signed overflow
);

    // Local opcode parameters for readability
    localparam OP_ADD = 2'b00;
    localparam OP_SUB = 2'b01;
    localparam OP_AND = 2'b10;
    localparam OP_OR  = 2'b11;

    // 9-bit intermediate results to capture carry/borrow out of bit 7
    wire [8:0] add_ext = {1'b0, a} + {1'b0, b};
    wire [8:0] sub_ext = {1'b0, a} - {1'b0, b};

    always @(*) begin
        // Default assignments prevent inferred latches
        result   = 8'h00;
        carry    = 1'b0;
        overflow = 1'b0;

        case (op_sel)
            OP_ADD: begin
                result   = add_ext[7:0];
                carry    = add_ext[8];
                // Signed overflow: operands same sign, result different sign
                overflow = (a[7] == b[7]) && (result[7] != a[7]);
            end

            OP_SUB: begin
                result   = sub_ext[7:0];
                
                // carry = 1 means no borrow occurred (a >= b), standard convention
                carry    = ~sub_ext[8];

                /*
                    Positive + Positive → can overflow past +127

                    Negative + Negative → can overflow past -128

                    Same-sign subtraction (pos−pos or neg−neg) → the result always stays within range, no overflow possible
                    30 - 10 = 20, no overflow
                    -30 - (-10) = -20, no overflow

                    signed overflow: negative − positive --> True math: -128 - 1 = -129, which doesn't fit in signed 8-bit range.

                    signed overflow: positive − negative --> True math: 127 - (-1) = 128, which doesn't fit in signed 8-bit range. Result wraps to 0x80 (-128)
                */

                // Signed overflow: operands different sign, result sign != a's sign
                overflow = (a[7] != b[7]) && (result[7] != a[7]);
            end

            OP_AND: begin
                result   = a & b;
                carry    = 1'b0;
                overflow = 1'b0;
            end

            OP_OR: begin
                result   = a | b;
                carry    = 1'b0;
                overflow = 1'b0;
            end

            default: begin
                result   = 8'h00;
                carry    = 1'b0;
                overflow = 1'b0;
            end
        endcase
    end

    // Zero and Negative flags derived combinationally from result
    assign zero     = (result == 8'h00);
    assign negative = result[7];

endmodule

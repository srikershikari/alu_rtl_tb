// =====================================================================
// File        : alu_uvm_tb.sv
// Description : Single-file UVM testbench for the 8-bit ALU ( alu.v )
//               Contains: interface, sequence item, sequences
//               ( directed corner-case, exhaustive boundary sweep,
//               constrained-random ), driver, monitor, scoreboard
//               ( independent reference model ), functional coverage,
//               agent, env, tests, and the top-level module.
//
// NOTE        : Requires a UVM-aware simulator with the UVM class
//               library ( UVM 1.2 / IEEE 1800.2 ), e.g. VCS, Xcelium,
//               or Questa. Compile this file together with alu.v.
//               Plain Icarus Verilog does not support UVM. Verilator
//               has only experimental/partial UVM support.
// =====================================================================

`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg :: *;

// Opcode encoding - must match alu.v
`define OP_ADD 2'b00
`define OP_SUB 2'b01
`define OP_AND 2'b10
`define OP_OR  2'b11

// =====================================================================
// Interface
// =====================================================================
interface alu_if ( input bit clk );
    logic [7:0] a;
    logic [7:0] b;
    logic [1:0] op_sel;
    logic [7:0] result;
    logic       zero;
    logic       negative;
    logic       carry;
    logic       overflow;
endinterface


// =====================================================================
// Sequence Item
// =====================================================================
class alu_txn extends uvm_sequence_item;

    rand bit [7:0] a;
    rand bit [7:0] b;
    rand bit [1:0] op_sel;

    // Filled in by the monitor after the DUT settles
    bit [7:0] result;
    bit       zero;
    bit       negative;
    bit       carry;
    bit       overflow;

    `uvm_object_utils_begin( alu_txn )
        `uvm_field_int( a,        UVM_ALL_ON )
        `uvm_field_int( b,        UVM_ALL_ON )
        `uvm_field_int( op_sel,   UVM_ALL_ON )
        `uvm_field_int( result,   UVM_ALL_ON )
        `uvm_field_int( zero,     UVM_ALL_ON )
        `uvm_field_int( negative, UVM_ALL_ON )
        `uvm_field_int( carry,    UVM_ALL_ON )
        `uvm_field_int( overflow, UVM_ALL_ON )
    `uvm_object_utils_end

    function new( string name = "alu_txn" );
        super.new( name );
    endfunction

    // Bias random draws toward boundary values without excluding the
    // rest of the input space - keeps random testing "aggressive"
    // around corners while still exercising the general case.
    /* constraint c_corner_bias { 
        a dist {  8'h00 := 5, 8'hFF := 5, 8'h80 := 5, 8'h7F := 5, [8'h01:8'hFE] :/ 80  };

        b dist {  8'h00 := 5, 8'hFF := 5, 8'h80 := 5, 8'h7F := 5, [8'h01:8'hFE] :/ 80  };

        op_sel dist {  `OP_ADD := 1, `OP_SUB := 1, `OP_AND := 1, `OP_OR := 1  };
     }*/

    function string convert2string();
        return $sformatf( 
            "a = %0d b = %0d op = %0d | result = %0d Z = %0b N = %0b C = %0b V = %0b",
            a, b, op_sel, result, zero, negative, carry, overflow );
    endfunction

endclass


// =====================================================================
// Sequence 1: Directed corner-case vectors
// Hand-picked values known to hit zero/negative/carry/overflow edges
// =====================================================================
class alu_corner_seq extends uvm_sequence #( alu_txn );

    `uvm_object_utils( alu_corner_seq )

    typedef struct { 
        bit [7:0] a;
        bit [7:0] b;
        bit [1:0] op;
     } corner_vec_t;

    function new( string name = "alu_corner_seq" );
        super.new( name );
    endfunction

    task body(  );

        corner_vec_t vecs[$];

        alu_txn req;

        // ---- ADD corner cases ----
        
        //0 + 0 = 0, 255 + 1 = 0 ( unsigned carry ), 127 + 1 = -128 ( signed overflow ), etc.
        vecs.push_back( '{ 8'h00, 8'h00, `OP_ADD } ); // zero result

        // 255 + 1 = 0 ( unsigned carry-out, wraps to 0 )
        vecs.push_back( '{ 8'hFF, 8'h01, `OP_ADD } ); // unsigned carry-out, wraps to 0

        // 127 + 1 = -128 ( signed overflow ), 8th bit is a signed bit, so 127 is the max positive value, and adding 1 causes it to wrap to the most negative value
        vecs.push_back( '{ 8'h7F, 8'h01, `OP_ADD } ); // signed overflow: pos + pos = neg

        //-128 + -128 = -256 ( signed overflow )
        vecs.push_back( '{ 8'h80, 8'h80, `OP_ADD } ); // signed overflow: neg + neg = pos, plus carry

        // 255 + 255 = 510 ( unsigned overflow, wraps to 254 )
        vecs.push_back( '{ 8'hFF, 8'hFF, `OP_ADD } ); // carry, max + max

        // 1 + 255 = 256 ( unsigned overflow, wraps to 0 )
        vecs.push_back( '{ 8'h01, 8'hFF, `OP_ADD } ); // carry, wraps to 0

        
        // ---- SUB corner cases ----

        // 0 - 0 = 0, 0 - 1 = -1 ( borrow ), -128 - 1 = 127 ( signed overflow ), etc.
        vecs.push_back( '{ 8'h00, 8'h00, `OP_SUB } ); // zero result

        // 0 - 1 = -1 ( borrow )
        vecs.push_back( '{ 8'h00, 8'h01, `OP_SUB } ); // borrow

        // -128 - 1 = 127 ( signed overflow )
        vecs.push_back( '{ 8'h80, 8'h01, `OP_SUB } ); // signed overflow: neg - pos = pos

        // 127 - ( -1 ) = 128 ( signed overflow )
        vecs.push_back( '{ 8'h7F, 8'hFF, `OP_SUB } ); // signed overflow: pos - neg = neg

        // 255 - 255 = 0 ( no borrow )
        vecs.push_back( '{ 8'hFF, 8'hFF, `OP_SUB } ); // equal operands -> zero

        // -128 - ( -128 ) = 0 ( no borrow )
        vecs.push_back( '{ 8'h80, 8'h80, `OP_SUB } ); // equal negatives -> zero


        // ---- AND corner cases ----

        // 0 & 0 = 0, 255 & 255 = 255, 170 & 85 = 0, etc.
        vecs.push_back( '{ 8'h00, 8'hFF, `OP_AND } ); // all-zero result

        // 255 & 255 = 255 ( all ones )
        vecs.push_back( '{ 8'hFF, 8'hFF, `OP_AND } ); // all-one result

        // 170 & 85 = 0 ( alternating bits )
        vecs.push_back( '{ 8'hAA, 8'h55, `OP_AND } ); // alternating bits -> zero

        // 128 & 128 = 128 ( negative result )
        vecs.push_back( '{ 8'h80, 8'h80, `OP_AND } ); // negative result


        // ---- OR corner cases ----

        // 0 | 0 = 0, 255 | 0 = 255, 170 | 85 = 255, etc.
        vecs.push_back( '{ 8'h00, 8'h00, `OP_OR } );  // all-zero result

        // 255 | 0 = 255 ( all ones )
        vecs.push_back( '{ 8'hFF, 8'h00, `OP_OR } );  // all-one result

        // 170 | 85 = 255 ( alternating bits )
        vecs.push_back( '{ 8'hAA, 8'h55, `OP_OR } );  // alternating bits -> all ones

        // 128 | 0 = 128 ( negative result )
        vecs.push_back( '{ 8'h00, 8'h80, `OP_OR } );  // negative result

        foreach ( vecs[i] ) 
        begin

            req = alu_txn :: type_id :: create( $sformatf( "corner_%0d", i ) );

            start_item( req );

            if ( !req.randomize() with { 
                    a      == vecs[i].a;
                    b      == vecs[i].b;
                    op_sel == vecs[i].op;
                 } )
            begin
                `uvm_fatal( get_type_name(), "Randomization failed for directed vector\n" )
            end

            finish_item( req );

        end

    endtask

endclass


// =====================================================================
// Sequence 2: Exhaustive boundary sweep
// All opcode x boundary-value x boundary-value combinations
// ( 4 ops x 6 values x 6 values = 144 vectors )
// =====================================================================
class alu_exhaustive_corner_seq extends uvm_sequence #( alu_txn );

    `uvm_object_utils( alu_exhaustive_corner_seq )

    function new( string name = "alu_exhaustive_corner_seq" );
        super.new( name );
    endfunction

    task body(  );

        bit [7:0] boundary_vals[] = '{ 8'h00, 8'h01, 8'h7F, 8'h80, 8'hFE, 8'hFF };

        bit [1:0] ops[]           = '{ `OP_ADD, `OP_SUB, `OP_AND, `OP_OR };

        alu_txn req;

        foreach ( ops[o] )
            foreach ( boundary_vals[i] )
                foreach ( boundary_vals[j] ) 
                begin

                    req = alu_txn :: type_id :: create( $sformatf( "sweep_%0d_%0d_%0d", o, i, j ) );

                    start_item( req );

                    if ( !req.randomize() with { 
                            a      == boundary_vals[i];
                            b      == boundary_vals[j];
                            op_sel == ops[o];
                         } )
                    begin
                        `uvm_fatal( get_type_name(), "Randomization failed for exhaustive vector\n" )
                    end

                    finish_item( req );
                end
    endtask
endclass



// =====================================================================
// Sequence 3: Constrained-random, corner-biased stress sequence
// =====================================================================
class alu_random_seq extends uvm_sequence #( alu_txn );

    `uvm_object_utils( alu_random_seq )

    int unsigned num_txns = 200;

    function new( string name = "alu_random_seq" );
        super.new( name );
    endfunction

    task body(  );

        alu_txn req;

        repeat ( num_txns ) 
        begin

            req = alu_txn :: type_id :: create( "req" );

            start_item( req );

            if ( !req.randomize() )
            begin
                `uvm_fatal( get_type_name(), "Randomization failed\n" )
            end

            finish_item( req );

        end

    endtask

endclass


// =====================================================================
// Driver
// =====================================================================
class alu_driver extends uvm_driver #( alu_txn );

    `uvm_component_utils( alu_driver )

    virtual alu_if vif;

    function new( string name, uvm_component parent );
        super.new( name, parent );
    endfunction

    function void build_phase( uvm_phase phase );

        super.build_phase( phase );

        if ( !uvm_config_db #( virtual alu_if ) :: get( this, "", "vif", vif ) )
        begin
            `uvm_fatal( get_type_name(), "Virtual interface 'vif' not found in config_db\n" )
        end

    endfunction

    task run_phase( uvm_phase phase );

        forever 
        begin
            
            alu_txn req;

            seq_item_port.get_next_item( req );

            `uvm_info( get_type_name(), $sformatf( "printing from driver %s\n", req.sprint() ), UVM_LOW )

            //this is a synchronous interface, so we drive the DUT on the falling edge of the clock
            //this is like a handshake, we wait for the clock to fall, then we drive the inputs, 
            //then we wait for the clock to rise so that the monitor can sample the outputs
            //this is a common pattern in UVM, where the driver drives the inputs on one edge of the clock, 
            //and the monitor samples the outputs on the other edge of the clock
            //remeber that the DUT is combinational, so it will compute the outputs based on the inputs immediately, 
            //but we want to give the monitor a chance to sample the outputs after the clock edge
            @( negedge vif.clk );
            vif.a      <= req.a;
            vif.b      <= req.b;
            vif.op_sel <= req.op_sel;

            @( posedge vif.clk ); // let the monitor sample after this edge

            seq_item_port.item_done(  );

        end
    endtask
endclass


// =====================================================================
// Monitor
// =====================================================================
class alu_monitor extends uvm_monitor;

    `uvm_component_utils( alu_monitor )

    virtual alu_if vif;

    uvm_analysis_port #( alu_txn ) ap;

    function new( string name, uvm_component parent );
        super.new( name, parent );
        ap = new( "ap", this );
    endfunction

    function void build_phase( uvm_phase phase );

        super.build_phase( phase );

        if ( !uvm_config_db #( virtual alu_if ) :: get( this, "", "vif", vif ) )
        begin
            `uvm_fatal( get_type_name(), "Virtual interface 'vif' not found in config_db\n" )
        end
        
    endfunction

    task run_phase( uvm_phase phase );

        alu_txn item;

        forever 
        begin

            @( negedge vif.clk );

            @( posedge vif.clk );
            
            // allow the DUT's combinational logic to settle like hold time, how a real circuit would, before sampling the outputs
            //#2; 

            item          = alu_txn :: type_id :: create( "item" );

            item.a        = vif.a;

            item.b        = vif.b;

            item.op_sel   = vif.op_sel;

            item.result   = vif.result;
            
            // sample the flags
            item.zero     = vif.zero;

            item.negative = vif.negative;

            item.carry    = vif.carry;

            item.overflow = vif.overflow;

            `uvm_info( get_type_name(), $sformatf( "printing from monitor %s\n", item.sprint() ), UVM_LOW )

            ap.write( item );
            
        end
    endtask
endclass


// =====================================================================
// Scoreboard - independent reference model, not a copy-paste of the DUT
// =====================================================================
class alu_scoreboard extends uvm_subscriber #( alu_txn );

    `uvm_component_utils( alu_scoreboard )

    int unsigned pass_cnt = 0;

    int unsigned fail_cnt = 0;

    function new( string name, uvm_component parent );
        super.new( name, parent );
    endfunction

    // Reference model: re-derives expected result/flags from the spec.
    /* function void predict( 
        input  bit [7:0] a,
        input  bit [7:0] b,
        input  bit [1:0] op,
        output bit [7:0] exp_result,
        output bit       exp_zero,
        output bit       exp_negative,
        output bit       exp_carry,
        output bit       exp_overflow
     );
        bit [8:0] add_ext, sub_ext;
        add_ext = { 1'b0, a } + { 1'b0, b };
        sub_ext = { 1'b0, a } - { 1'b0, b };

        case ( op )

            `OP_ADD: 
            begin
                exp_result   = add_ext[7:0];
                exp_carry    = add_ext[8];
                exp_overflow = ( a[7] == b[7] ) && ( exp_result[7] != a[7] );
            end

            `OP_SUB: 
            begin
                exp_result   = sub_ext[7:0];
                exp_carry    = ~sub_ext[8];
                exp_overflow = ( a[7] != b[7] ) && ( exp_result[7] != a[7] );
            end

            `OP_AND: 
            begin
                exp_result   = a & b;
                exp_carry    = 1'b0;
                exp_overflow = 1'b0;
            end
            
            `OP_OR: 
            begin
                exp_result   = a | b;
                exp_carry    = 1'b0;
                exp_overflow = 1'b0;
            end

            default: 
            begin
                exp_result   = 8'h00;
                exp_carry    = 1'b0;
                exp_overflow = 1'b0;
            end

        endcase

        exp_zero     = ( exp_result == 8'h00 );

        exp_negative = exp_result[7];

    endfunction */

    function void predict(
        input  bit [7:0] a,
        input  bit [7:0] b,
        input  bit [1:0] op,
        output bit [7:0] exp_result,
        output bit       exp_zero,
        output bit       exp_negative,
        output bit       exp_carry,
        output bit       exp_overflow
    );
    
        int signed   s_a, s_b, s_result;
        int unsigned u_a, u_b, u_result;

        s_a = $signed( a );   // sign-extends a into a 32-bit signed value
        s_b = $signed( b );
        u_a = a;            // zero-extends a into a 32-bit unsigned value
        u_b = b;

        case ( op )

            `OP_ADD: 
            begin
                u_result     = u_a + u_b;               // true 32-bit unsigned sum, no wraparound risk
                s_result     = s_a + s_b;                // true 32-bit signed sum
                exp_result   = s_result[7:0];            // 2's complement truncation gives correct 8-bit wraparound
                exp_carry    = ( u_result > 32'd255 );      // did the unsigned magnitude exceed 8 bits?
                exp_overflow = ( s_result < -128 ) || ( s_result > 127 ); // did the signed value exceed the range?
            end

            `OP_SUB: 
            begin
                s_result     = s_a - s_b;
                exp_result   = s_result[7:0];
                exp_carry    = ( u_a >= u_b );              // direct magnitude comparison: no borrow if a >= b
                exp_overflow = ( s_result < -128 ) || ( s_result > 127 );
            end

            `OP_AND: 
            begin
                exp_result   = a & b;
                exp_carry    = 1'b0;
                exp_overflow = 1'b0;
            end

            `OP_OR: 
            begin
                exp_result   = a | b;
                exp_carry    = 1'b0;
                exp_overflow = 1'b0;
            end

            default: 
            begin
                exp_result   = 8'h00;
                exp_carry    = 1'b0;
                exp_overflow = 1'b0;
            end

        endcase

        exp_zero     = ( exp_result == 8'h00 );
        exp_negative = exp_result[7];

    endfunction

    function void write( alu_txn t );

        bit [7:0] exp_result;
        bit       exp_zero, exp_negative, exp_carry, exp_overflow;

        predict( t.a, t.b, t.op_sel, exp_result, exp_zero, exp_negative, exp_carry, exp_overflow );

        if ( t.result   === exp_result   &&
            t.zero     === exp_zero     &&
            t.negative === exp_negative &&
            t.carry    === exp_carry    &&
            t.overflow === exp_overflow ) 
        begin
            pass_cnt++;
            `uvm_info( get_type_name(), $sformatf( "PASS: %s\n", t.convert2string() ), UVM_LOW )
        end 
        
        else 
        begin
            fail_cnt++;
            `uvm_error( get_type_name(), 
                $sformatf( "MISMATCH: %s | expected result = %0d Z = %0b N = %0b C = %0b V = %0b\n",
                    t.convert2string(), exp_result, exp_zero, exp_negative, exp_carry, exp_overflow ) )
        end

    endfunction


    function void report_phase( uvm_phase phase );

        `uvm_info( get_type_name(), 
            $sformatf( "======== SCOREBOARD SUMMARY: PASS = %0d FAIL = %0d ========\n", pass_cnt, fail_cnt ),
            UVM_LOW )
            
        if ( fail_cnt == 0 )
        begin
            `uvm_info( get_type_name(), "RESULT: ALL CHECKS PASSED\n", UVM_LOW )
        end

        else
        begin
            `uvm_error( get_type_name(), "RESULT: ONE OR MORE CHECKS FAILED\n" )
        end

    endfunction
endclass


// =====================================================================
// Functional Coverage
// =====================================================================
class alu_coverage extends uvm_subscriber #( alu_txn );

    `uvm_component_utils( alu_coverage )

    alu_txn item;

    covergroup cg_alu;

        option.per_instance = 1;

        cp_op: coverpoint item.op_sel { 
            bins add     = { `OP_ADD };
            bins sub     = { `OP_SUB };
            bins bit_and = { `OP_AND };
            bins bit_or  = { `OP_OR };
         }

        cp_a_corner: coverpoint item.a { 
            bins zero    = { 8'h00 };
            bins max     = { 8'hFF };
            bins min_neg = { 8'h80 };
            bins max_pos = { 8'h7F };
            bins mid     = { [8'h01:8'hFE] };
         }

        cp_b_corner: coverpoint item.b { 
            bins zero    = { 8'h00 };
            bins max     = { 8'hFF };
            bins min_neg = { 8'h80 };
            bins max_pos = { 8'h7F };
            bins mid     = { [8'h01:8'hFE] };
         }

        cp_zero:     coverpoint item.zero;
        cp_negative: coverpoint item.negative;
        cp_carry:    coverpoint item.carry;
        cp_overflow: coverpoint item.overflow;

        cx_op_flags:   cross cp_op, cp_zero, cp_negative, cp_carry, cp_overflow;  //with both of this I get only 77% coverage.

        cx_op_corners: cross cp_op, cp_a_corner, cp_b_corner; //only with this I can get 99% coverage.

    endgroup

    function new( string name, uvm_component parent );
        super.new( name, parent );
        cg_alu = new();
    endfunction

    function void write( alu_txn t );
        item = t;
        cg_alu.sample();
    endfunction

    function void report_phase( uvm_phase phase );
        `uvm_info( get_type_name(), 
            $sformatf( "Functional coverage = %0.2f%%\n", cg_alu.get_coverage() ), UVM_LOW )
    endfunction

endclass


// =====================================================================
// Agent
// =====================================================================
class alu_agent extends uvm_agent;

    `uvm_component_utils( alu_agent )

    alu_driver                    driver;
    uvm_sequencer #( alu_txn ) sequencer;
    alu_monitor                   monitor;

    function new( string name, uvm_component parent );
        super.new( name, parent );
    endfunction

    function void build_phase( uvm_phase phase );
        super.build_phase( phase );
        driver    = alu_driver :: type_id :: create( "driver", this );
        sequencer = uvm_sequencer #( alu_txn ) :: type_id :: create( "sequencer", this );
        monitor   = alu_monitor :: type_id :: create( "monitor", this );
    endfunction

    function void connect_phase( uvm_phase phase );
        super.connect_phase( phase );
        driver.seq_item_port.connect( sequencer.seq_item_export );
    endfunction

endclass


// =====================================================================
// Environment
// =====================================================================
class alu_env extends uvm_env;

    `uvm_component_utils( alu_env )

    alu_agent      agent;
    alu_scoreboard scoreboard;
    alu_coverage   coverage;

    function new( string name, uvm_component parent );
        super.new( name, parent );
    endfunction

    function void build_phase( uvm_phase phase );
        super.build_phase( phase );
        agent      = alu_agent :: type_id :: create( "agent", this );
        scoreboard = alu_scoreboard :: type_id :: create( "scoreboard", this );
        coverage   = alu_coverage :: type_id :: create( "coverage", this );
    endfunction

    function void connect_phase( uvm_phase phase );
        super.connect_phase( phase );
        agent.monitor.ap.connect( scoreboard.analysis_export );
        agent.monitor.ap.connect( coverage.analysis_export );
    endfunction

endclass


// =====================================================================
// Tests
// =====================================================================
class alu_base_test extends uvm_test;

    `uvm_component_utils( alu_base_test )

    alu_env env;

    function new( string name, uvm_component parent );
        super.new( name, parent );
    endfunction

    function void build_phase( uvm_phase phase );
        super.build_phase( phase );
        env = alu_env :: type_id :: create( "env", this );
    endfunction

    function void end_of_elaboration_phase( uvm_phase phase );
        super.end_of_elaboration_phase( phase );
        uvm_top.print_topology();
    endfunction

endclass : alu_base_test


// ---------------------------------------------------------------------
// Test 1: directed corner-case vectors only
// ---------------------------------------------------------------------
class alu_corner_test extends alu_base_test;

    `uvm_component_utils( alu_corner_test )

    function new( string name, uvm_component parent );
        super.new( name, parent );
    endfunction

    task run_phase( uvm_phase phase );
    
        alu_corner_seq corner_seq;

        phase.raise_objection( this );

        `uvm_info( get_type_name(), "Running directed corner-case sequence...\n", UVM_LOW )

        corner_seq = alu_corner_seq :: type_id :: create( "corner_seq" );
        
        corner_seq.start( env.agent.sequencer );

        phase.drop_objection( this );

    endtask

endclass : alu_corner_test


// ---------------------------------------------------------------------
// Test 2: exhaustive boundary-value sweep only
// ---------------------------------------------------------------------
class alu_exhaustive_corner_test extends alu_base_test;

    `uvm_component_utils( alu_exhaustive_corner_test )

    function new( string name, uvm_component parent );
        super.new( name, parent );
    endfunction

    task run_phase( uvm_phase phase );

        alu_exhaustive_corner_seq sweep_seq;

        phase.raise_objection( this );

        `uvm_info( get_type_name(), "Running exhaustive boundary-sweep sequence...\n", UVM_LOW )

        sweep_seq = alu_exhaustive_corner_seq :: type_id :: create( "sweep_seq" );

        sweep_seq.start( env.agent.sequencer );

        phase.drop_objection( this );

    endtask

endclass : alu_exhaustive_corner_test


// ---------------------------------------------------------------------
// Test 3: constrained-random, corner-biased stress only
// ---------------------------------------------------------------------
class alu_random_test extends alu_base_test;

    `uvm_component_utils( alu_random_test )

    function new( string name, uvm_component parent );
        super.new( name, parent );
    endfunction

    task run_phase( uvm_phase phase );
        alu_random_seq rand_seq;

        phase.raise_objection( this );

        `uvm_info( get_type_name(), "Running randomized corner-biased stress sequence...\n", UVM_LOW )

        rand_seq = alu_random_seq :: type_id :: create( "rand_seq" );

        rand_seq.num_txns = 500;

        rand_seq.start( env.agent.sequencer );

        phase.drop_objection( this );

    endtask

endclass : alu_random_test


// =====================================================================
// Top-level module
// =====================================================================
module top;

    bit clk;

    always #5 clk = ~clk;

    alu_if intf ( clk );

    // DUT - compile alu.v alongside this file
    alu dut ( 
        .a        ( intf.a ),
        .b        ( intf.b ),
        .op_sel   ( intf.op_sel ),
        .result   ( intf.result ),
        .zero     ( intf.zero ),
        .negative ( intf.negative ),
        .carry    ( intf.carry ),
        .overflow ( intf.overflow )
     );


    initial 
    begin

        uvm_config_db #( virtual alu_if ) :: set( null, "*", "vif", intf );

        // No hard-coded test name: pass +UVM_TESTNAME=<test> on the
        // command line so a regression/Makefile can run each test
        // (alu_corner_test, alu_exhaustive_corner_test, alu_random_test)
        // separately and collect per-test coverage.
        run_test();

    end

endmodule : top


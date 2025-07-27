// Code your testbench here
// or browse Examples
// =============================================================================
// ECC LAYERED TESTBENCH SYSTEM
// Comprehensive testbench for BCH (15,5) and Hamming (7,4) error correction
// =============================================================================

`timescale 1ns/1ps

// =============================================================================
// TRANSACTION CLASS - Data packet for stimulus and response
// =============================================================================
typedef enum {HAMMING_7_4, BCH_15_5} ecc_type_e;
class ecc_transaction;
    // Common fields
    rand bit [31:0] data_in;
    bit [31:0] codeword;
    bit [31:0] received_codeword;
    bit [31:0] data_out;
    bit error_detected;
    bit error_corrected;
    bit [31:0] corrected_codeword;
    bit [31:0] syndrome;
    
    // Test control
    rand ecc_type_e ecc_type;
    rand int num_errors;
    int error_positions[$];
    time timestamp;
    
    // Constraints
    constraint c_ecc_type {
        ecc_type inside {HAMMING_7_4, BCH_15_5};
    }
    
    constraint c_data_size {
        if (ecc_type == HAMMING_7_4) {
            data_in < 16; // 4-bit data
        } else {
            data_in < 32; // 5-bit data
        }
    }
    
    constraint c_errors {
        num_errors inside {0, 1, 2, 3};
        num_errors dist {0 := 20, 1 := 40, 2 := 30, 3 := 10};
    }
    
    // Methods
    function new();
        timestamp = $time;
        error_positions = {};
    endfunction
    
    function void print(string prefix = "");
        $display("%s[%0t] ECC Transaction:", prefix, timestamp);
        $display("%s  Type: %s", prefix, ecc_type.name());
      $display("%s  Data In: 0x%0b", prefix, data_in);
      $display("%s  Codeword: 0x%0b", prefix, codeword);
        $display("%s  Errors: %0d at positions %p", prefix, num_errors, error_positions);
      $display("%s  Received: 0x%0b", prefix, received_codeword);
      $display("%s  Data Out: 0x%0b", prefix, data_out);
        $display("%s  Error Detected/Corrected: %b/%b", prefix, error_detected, error_corrected);
    endfunction
    
    function bit compare_data();
        case (ecc_type)
            HAMMING_7_4: return (data_out[3:0] == data_in[3:0]);
            BCH_15_5: return (data_out[4:0] == data_in[4:0]);
            default: return 0;
        endcase
    endfunction
endclass

// =============================================================================
// ENUM DEFINITIONS
// =============================================================================

typedef enum {IDLE, ENCODE, INJECT_ERROR, DECODE, CHECK} test_state_e;

// =============================================================================
// DRIVER CLASS - Converts transactions to pin wiggles
// =============================================================================
class ecc_driver;
    virtual ecc_interface vif;
    mailbox #(ecc_transaction) gen2drv;
    mailbox #(ecc_transaction) drv2scb;
    
    function new(virtual ecc_interface vif, 
                 mailbox #(ecc_transaction) gen2drv,
                 mailbox #(ecc_transaction) drv2scb);
        this.vif = vif;
        this.gen2drv = gen2drv;
        this.drv2scb = drv2scb;
    endfunction
    
    task run();
        ecc_transaction trans;
        forever begin
            gen2drv.get(trans);
            drive_transaction(trans);
            drv2scb.put(trans);
        end
    endtask
    
    task drive_transaction(ecc_transaction trans);
        case (trans.ecc_type)
            HAMMING_7_4: drive_hamming(trans);
            BCH_15_5: drive_bch(trans);
        endcase
    endtask
    
    task drive_hamming(ecc_transaction trans);
        // Drive input data
        vif.hamming_data_in = trans.data_in[3:0];
        @(posedge vif.clk);
        
        // Capture encoded codeword
        trans.codeword = vif.hamming_codeword;
        
        // Inject errors
        trans.received_codeword = inject_errors(trans.codeword, 7, trans.num_errors, trans.error_positions);
        vif.hamming_received = trans.received_codeword[6:0];
        @(posedge vif.clk);
        
        // Capture decoded results
        trans.data_out = vif.hamming_data_out;
        trans.error_detected = vif.hamming_error_detected;
        trans.error_corrected = vif.hamming_error_corrected;
        trans.corrected_codeword = vif.hamming_corrected_codeword;
        trans.syndrome = vif.hamming_syndrome;
    endtask
    
    task drive_bch(ecc_transaction trans);
        // Drive input data
        vif.bch_data_in = trans.data_in[4:0];
        @(posedge vif.clk);
        
        // Capture encoded codeword
        trans.codeword = vif.bch_codeword;
        
        // Inject errors
        trans.received_codeword = inject_errors(trans.codeword, 15, trans.num_errors, trans.error_positions);
        vif.bch_received = trans.received_codeword[14:0];
        @(posedge vif.clk);
        
        // Capture decoded results
        trans.data_out = vif.bch_data_out;
        trans.error_detected = vif.bch_error_detected;
        trans.error_corrected = vif.bch_error_corrected;
        trans.corrected_codeword = vif.bch_corrected_codeword;
        trans.syndrome = vif.bch_syndrome;
    endtask
    
    function automatic bit [31:0] inject_errors(
        input bit [31:0] original, 
        input int max_bits, 
        input int num_err,
        ref int error_positions[$]
    );
        bit [31:0] corrupted;
        int pos, attempts;
        bit position_exists;
        
        corrupted = original;
        error_positions.delete();
        
        for (int i = 0; i < num_err; i++) begin
            attempts = 0;
            do begin
                pos = $urandom_range(0, max_bits-1);
                attempts++;
                
                position_exists = 0;
                foreach (error_positions[j]) begin
                    if (error_positions[j] == pos) begin
                        position_exists = 1;
                        break;
                    end
                end
            end while (position_exists && attempts < 100);
            
            if (attempts < 100) begin
                error_positions.push_back(pos);
                corrupted[pos] = ~corrupted[pos];
            end
        end
        
        return corrupted;
    endfunction
endclass

// =============================================================================
// MONITOR CLASS - Captures DUT signals for analysis
// =============================================================================
class ecc_monitor;
    virtual ecc_interface vif;
    mailbox #(ecc_transaction) mon2scb;
    
    function new(virtual ecc_interface vif, mailbox #(ecc_transaction) mon2scb);
        this.vif = vif;
        this.mon2scb = mon2scb;
    endfunction
    
    task run();
        forever begin
            ecc_transaction trans = new();
            monitor_transaction(trans);
            mon2scb.put(trans);
        end
    endtask
    
    task monitor_transaction(ecc_transaction trans);
        // Monitor both Hamming and BCH simultaneously
        @(posedge vif.clk);
        
        // Capture Hamming signals
        trans.data_in = vif.hamming_data_in;
        trans.codeword = vif.hamming_codeword;
        trans.received_codeword = vif.hamming_received;
        trans.data_out = vif.hamming_data_out;
        trans.error_detected = vif.hamming_error_detected;
        trans.error_corrected = vif.hamming_error_corrected;
        trans.syndrome = vif.hamming_syndrome;
        
        // Additional monitoring logic can be added here
    endtask
endclass

// =============================================================================
// SCOREBOARD CLASS - Checks correctness and maintains statistics
// =============================================================================
class ecc_scoreboard;
    mailbox #(ecc_transaction) drv2scb;
    mailbox #(ecc_transaction) mon2scb;
    
    // Statistics
    int total_tests;
    int hamming_pass, hamming_fail;
    int bch_pass, bch_fail;
    int error_correction_success;
    int error_detection_success;
    
    // Coverage
    covergroup ecc_coverage;
        cp_ecc_type: coverpoint current_trans.ecc_type;
        cp_num_errors: coverpoint current_trans.num_errors {
            bins no_error = {0};
            bins single_error = {1};
            bins double_error = {2};
            bins triple_error = {3};
        }
        cp_error_detected: coverpoint current_trans.error_detected;
        cp_error_corrected: coverpoint current_trans.error_corrected;
        
        // Cross coverage
        cx_type_errors: cross cp_ecc_type, cp_num_errors;
        cx_detection_correction: cross cp_error_detected, cp_error_corrected;
    endgroup
    
    ecc_transaction current_trans;
    
    function new(mailbox #(ecc_transaction) drv2scb, mailbox #(ecc_transaction) mon2scb);
        this.drv2scb = drv2scb;
        this.mon2scb = mon2scb;
        ecc_coverage = new();
        reset_stats();
    endfunction
    
    task run();
        ecc_transaction trans;
        forever begin
            drv2scb.get(trans);
            current_trans = trans;
            check_transaction(trans);
            ecc_coverage.sample();
            update_stats(trans);
        end
    endtask
    
    task check_transaction(ecc_transaction trans);
    bit data_match = trans.compare_data();
    string ecc_name;
    
    case (trans.ecc_type)
        HAMMING_7_4: ecc_name = "HAMMING (7,4)";
        BCH_15_5:    ecc_name = "BCH (15,5)";
    endcase
    
    $display("\n=== %s TEST #%0d ===", ecc_name, total_tests+1);
      $display("Original Data:     %0d (0x%0b)", trans.data_in, trans.data_in);
      $display("Encoded Codeword:  0x%0b", trans.codeword);
    $display("Errors Injected:   %0d", trans.num_errors);
    $display("Error Positions:   %p", trans.error_positions);
      $display("Received Codeword: 0x%0b", trans.received_codeword);
      $display("Syndrome:          0x%0b", trans.syndrome);
    $display("Error Detected:    %s", trans.error_detected ? "YES" : "NO");
    $display("Error Corrected:   %s", trans.error_corrected ? "YES" : "NO");

    if (trans.ecc_type == HAMMING_7_4)
      $display("Decoded Data:      %0d (0x%0b)", trans.data_out[3:0], trans.data_out[3:0]);
    else
      $display("Decoded Data:      %0d (0x%0b)", trans.data_out[4:0], trans.data_out[4:0]);

    if (data_match) begin
        $display("RESULT: PASS - Decoded data matches original");
        if (trans.ecc_type == HAMMING_7_4) hamming_pass++; else bch_pass++;
    end else begin
        $display("RESULT: FAIL - Decoded data does not match original");
        if (trans.ecc_type == HAMMING_7_4) hamming_fail++; else bch_fail++;
    end

    // Analysis based on number of errors
    case (trans.num_errors)
        0: $display("Analysis: No errors - Should decode correctly");
        1: $display("Analysis: Single error - Should be corrected");
        2: begin
            if (trans.ecc_type == HAMMING_7_4)
                $display("Analysis: Double error - May be detected but not corrected");
            else
                $display("Analysis: Double error - Should be corrected (BCH can handle 2 errors)");
        end
        3: $display("Analysis: Triple error - Likely uncorrectable");
    endcase
    
    if (trans.error_detected == (trans.num_errors > 0)) error_detection_success++;
    if (trans.error_corrected == ((trans.ecc_type == HAMMING_7_4 && trans.num_errors == 1) || 
                                  (trans.ecc_type == BCH_15_5 && trans.num_errors <= 2)))
        error_correction_success++;

    total_tests++;
endtask
    
    task update_stats(ecc_transaction trans);
        // Additional statistics can be updated here
    endtask
    
    function void reset_stats();
        total_tests = 0;
        hamming_pass = 0; hamming_fail = 0;
        bch_pass = 0; bch_fail = 0;
        error_correction_success = 0;
        error_detection_success = 0;
    endfunction
    
    function void print_stats();
        real hamming_success_rate = (hamming_pass + hamming_fail > 0) ? 
            (hamming_pass * 100.0) / (hamming_pass + hamming_fail) : 0;
        real bch_success_rate = (bch_pass + bch_fail > 0) ? 
            (bch_pass * 100.0) / (bch_pass + bch_fail) : 0;
        real overall_success_rate = (total_tests > 0) ? 
            ((hamming_pass + bch_pass) * 100.0) / total_tests : 0;
        
        $display("\n" + {"="*60});
        $display("ECC TESTBENCH FINAL RESULTS");
        $display({"="*60});
        $display("Total Tests: %0d", total_tests);
        $display("\nHamming (7,4) Results:");
        $display("  PASS: %0d, FAIL: %0d", hamming_pass, hamming_fail);
        $display("  Success Rate: %.2f%%", hamming_success_rate);
        $display("\nBCH (15,5) Results:");
        $display("  PASS: %0d, FAIL: %0d", bch_pass, bch_fail);
        $display("  Success Rate: %.2f%%", bch_success_rate);
        $display("\nError Detection Success: %0d/%0d (%.2f%%)", 
                 error_detection_success, total_tests, 
                 (error_detection_success * 100.0) / total_tests);
        $display("Error Correction Success: %0d/%0d (%.2f%%)", 
                 error_correction_success, total_tests,
                 (error_correction_success * 100.0) / total_tests);
        $display("\nOverall Success Rate: %.2f%%", overall_success_rate);
        $display("Functional Coverage: %.2f%%", ecc_coverage.get_inst_coverage());
        $display({"="*60});
    endfunction
endclass

// =============================================================================
// GENERATOR CLASS - Creates randomized stimulus
// =============================================================================
class ecc_generator;
    mailbox #(ecc_transaction) gen2drv;
    int num_tests;
    
    function new(mailbox #(ecc_transaction) gen2drv, int num_tests = 100);
        this.gen2drv = gen2drv;
        this.num_tests = num_tests;
    endfunction
    
    task run();
        for (int i = 0; i < num_tests; i++) begin
            ecc_transaction trans = new();
            assert(trans.randomize()) else $fatal("Randomization failed");
            gen2drv.put(trans);
        end
    endtask
endclass

// =============================================================================
// ENVIRONMENT CLASS - Coordinates all testbench components
// =============================================================================
class ecc_environment;
    virtual ecc_interface vif;
    
    ecc_generator gen;
    ecc_driver drv;
    ecc_monitor mon;
    ecc_scoreboard scb;
    
    mailbox #(ecc_transaction) gen2drv;
    mailbox #(ecc_transaction) drv2scb;
    mailbox #(ecc_transaction) mon2scb;
    
    function new(virtual ecc_interface vif);
        this.vif = vif;
        
        // Create mailboxes
        gen2drv = new();
        drv2scb = new();
        mon2scb = new();
        
        // Create components
        gen = new(gen2drv);
        drv = new(vif, gen2drv, drv2scb);
        mon = new(vif, mon2scb);
        scb = new(drv2scb, mon2scb);
    endfunction
    
    task run(int num_tests = 100);
        gen.num_tests = num_tests;
        
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_any
        
        // Wait for all tests to complete
        #1000;
        scb.print_stats();
    endtask
endclass

// =============================================================================
// INTERFACE - Signal connections between testbench and DUT
// =============================================================================
interface ecc_interface(input logic clk, input logic rst_n);
    // Hamming (7,4) signals
    logic [3:0] hamming_data_in;
    logic [6:0] hamming_codeword;
    logic [6:0] hamming_received;
    logic [3:0] hamming_data_out;
    logic hamming_error_detected;
    logic hamming_error_corrected;
    logic [6:0] hamming_corrected_codeword;
    logic [2:0] hamming_syndrome;
    
    // BCH (15,5) signals
    logic [4:0] bch_data_in;
    logic [14:0] bch_codeword;
    logic [14:0] bch_received;
    logic [4:0] bch_data_out;
    logic bch_error_detected;
    logic bch_error_corrected;
    logic [14:0] bch_corrected_codeword;
    logic [9:0] bch_syndrome;
    
    // Clocking blocks for synchronous operation
    clocking cb @(posedge clk);
        default input #1 output #1;
        output hamming_data_in, hamming_received;
        output bch_data_in, bch_received;
        input hamming_codeword, hamming_data_out, hamming_error_detected;
        input hamming_error_corrected, hamming_corrected_codeword, hamming_syndrome;
        input bch_codeword, bch_data_out, bch_error_detected;
        input bch_error_corrected, bch_corrected_codeword, bch_syndrome;
    endclocking
    
    modport TB (clocking cb, input clk, rst_n);
endinterface

// =============================================================================
// TEST CLASS - Defines test scenarios
// =============================================================================
class ecc_test_base;
    virtual ecc_interface vif;
    ecc_environment env;
    
    function new(virtual ecc_interface vif);
        this.vif = vif;
        env = new(vif);
    endfunction
    
    virtual task run();
        $display("Running base ECC test...");
      env.run(50);
    endtask
endclass

class ecc_smoke_test extends ecc_test_base;
    function new(virtual ecc_interface vif);
        super.new(vif);
    endfunction
    
    task run();
        $display("Running ECC smoke test...");
        env.run(10);
    endtask
endclass

class ecc_stress_test extends ecc_test_base;
    function new(virtual ecc_interface vif);
        super.new(vif);
    endfunction
    
    task run();
        $display("Running ECC stress test...");
        env.run(1000);
    endtask
endclass

// =============================================================================
// TOP-LEVEL TESTBENCH MODULE
// =============================================================================
module ecc_layered_testbench;
    // Clock and reset
    logic clk = 0;
    logic rst_n;
    
    // Clock generation
    always #5 clk = ~clk;
    
    // Interface instantiation
    ecc_interface ecc_if(clk, rst_n);
    
    // DUT instantiation
    hamming_encoder_7_4 hamming_enc (
        .data_in(ecc_if.hamming_data_in),
        .codeword(ecc_if.hamming_codeword)
    );
    
    hamming_decoder_7_4 hamming_dec (
        .codeword_in(ecc_if.hamming_received),
        .data_out(ecc_if.hamming_data_out),
        .error_detected(ecc_if.hamming_error_detected),
        .error_corrected(ecc_if.hamming_error_corrected),
        .corrected_codeword(ecc_if.hamming_corrected_codeword),
        .syndrome(ecc_if.hamming_syndrome)
    );
    
    bch_encoder_15_5 bch_enc (
        .data_in(ecc_if.bch_data_in),
        .codeword(ecc_if.bch_codeword)
    );
    
    bch_decoder_15_5 bch_dec (
        .codeword_in(ecc_if.bch_received),
        .data_out(ecc_if.bch_data_out),
        .error_detected(ecc_if.bch_error_detected),
        .error_corrected(ecc_if.bch_error_corrected),
        .corrected_codeword(ecc_if.bch_corrected_codeword),
        .syndrome(ecc_if.bch_syndrome)
    );
    
    // Test execution
    initial begin
        ecc_test_base test;
        string test_name;
        
        // Get test name from command line
        if (!$value$plusargs("TEST=%s", test_name)) begin
            test_name = "ecc_test_base";
        end
        
        // Reset sequence
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        
        $display("=======================================================");
        $display("Starting Layered ECC Testbench");
        $display("Test: %s", test_name);
        $display("=======================================================");
        
        // Create and run appropriate test
        if (test_name == "smoke") begin
        ecc_smoke_test smoke_test = new(ecc_if);
        test = smoke_test;
    end else if (test_name == "stress") begin
        ecc_stress_test stress_test = new(ecc_if);
        test = stress_test;
    end else begin
        test = new(ecc_if);
    end
        
        test.run();
        
        #100;
        $finish;
    end
    
    // Waveform dumping
    initial begin
        $dumpfile("ecc_layered_test.vcd");
        $dumpvars(0, ecc_layered_testbench);
    end
    
    // Timeout watchdog
    initial begin
        #100000; // 100us timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end
    
endmodule

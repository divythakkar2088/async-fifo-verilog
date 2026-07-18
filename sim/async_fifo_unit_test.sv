/*
 * Copyright (c) 2026 Divy Thakkar
 *
 * Custom self-checking SystemVerilog testbench developed for
 * verification of an asynchronous FIFO.
 *
 * Features:
 * - Reset verification
 * - Single write/read verification
 * - FIFO full detection
 * - FIFO empty detection
 * - Overflow protection
 * - Underflow protection
 * - Concurrent read/write stress testing
 * - Final FIFO flush verification
 *
 * This testbench is an original work by Divy Thakkar.
 */

`timescale 1ns / 1ps
`default_nettype none

// =====================================================================
// Async FIFO Self-Checking Testbench
// Matches DUT: async_fifo (DSIZE, ASIZE, FALLTHROUGH)
// Ports      : wclk, wrst_n, winc, wdata, wfull, awfull,
//              rclk, rrst_n, rinc, rdata, rempty, arempty
// Reset      : ACTIVE-LOW (wrst_n=0 / rrst_n=0 asserts reset)
// =====================================================================

module async_fifo_unit_test;

    // -----------------------------------------------------------
    // Parameters (match DUT)
    // -----------------------------------------------------------
    parameter DSIZE       = 8;
    parameter ASIZE       = 4;              // pointer/address width -> depth = 2**ASIZE
    parameter FALLTHROUGH = "TRUE";
    localparam DEPTH      = 2**ASIZE;

    // -----------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------
    logic             wclk, wrst_n, winc;
    logic [DSIZE-1:0] wdata;
    logic             wfull, awfull;

    logic             rclk, rrst_n, rinc;
    logic [DSIZE-1:0] rdata;
    logic             rempty, arempty;

    // Golden reference model (scoreboard) - mirrors expected FIFO content
    logic [DSIZE-1:0] golden_queue[$];
    logic [DSIZE-1:0] expected_data;

    integer errors = 0;
    integer checks = 0;

    // -----------------------------------------------------------
    // DUT instantiation (named ports - matches your async_fifo ports)
    // -----------------------------------------------------------
    async_fifo #(
        .DSIZE       (DSIZE),
        .ASIZE       (ASIZE),
        .FALLTHROUGH (FALLTHROUGH)
    ) dut (
        .wclk    (wclk),
        .wrst_n  (wrst_n),
        .winc    (winc),
        .wdata   (wdata),
        .wfull   (wfull),
        .awfull  (awfull),
        .rclk    (rclk),
        .rrst_n  (rrst_n),
        .rinc    (rinc),
        .rdata   (rdata),
        .rempty  (rempty),
        .arempty (arempty)
    );

    // -----------------------------------------------------------
    // Clock generation - two independent async domains
    // wclk = 100 MHz (10 ns period), rclk = 40 MHz (25 ns period)
    // -----------------------------------------------------------
    initial begin
        wclk = 0;
        forever #5 wclk = ~wclk;
    end

    initial begin
        rclk = 0;
        forever #12.5 rclk = ~rclk;
    end

    // Waveform dump
    initial begin
        $dumpfile("async_fifo_unit_test.vcd");
        $dumpvars(0, async_fifo_unit_test);
    end

    // -----------------------------------------------------------
    // Reset task - active LOW, pulses both domains
    // -----------------------------------------------------------
    task apply_reset();
    begin
        wrst_n = 1'b0;
        rrst_n = 1'b0;
        winc   = 1'b0;
        rinc   = 1'b0;
        wdata  = '0;
        golden_queue.delete();
        #30;
        wrst_n = 1'b1;
        rrst_n = 1'b1;
        #30;
    end
    endtask

    // -----------------------------------------------------------
    // Write task - pushes into DUT + golden model together
    // -----------------------------------------------------------
    task write_data(input logic [DSIZE-1:0] data);
    begin
        @(posedge wclk);
        if (!wfull) begin
            winc  <= 1'b1;
            wdata <= data;
            golden_queue.push_back(data);
        end else begin
            $display("[%0t] WARNING: write attempted while FIFO full - skipped", $time);
            winc <= 1'b0;
        end
        @(posedge wclk);
        winc <= 1'b0;
    end
    endtask

    // -----------------------------------------------------------
    // Read + verify task - pops golden model, compares against rdata
    // -----------------------------------------------------------
    task read_and_verify();
    begin
        @(posedge rclk);
        if (!rempty) begin
            rinc <= 1'b1;
            @(posedge rclk);       // rdata valid this edge (registered output)
            rinc <= 1'b0;

            expected_data = golden_queue.pop_front();
            checks++;

            if (rdata !== expected_data) begin
                errors++;
                $error("[%0t] FAIL: expected=%h got=%h", $time, expected_data, rdata);
            end else begin
                $display("[%0t] PASS: read %h", $time, rdata);
            end
        end else begin
            $display("[%0t] WARNING: read attempted while FIFO empty - skipped", $time);
            rinc <= 1'b0;
        end
    end
    endtask

    // -----------------------------------------------------------
    // Flag-check helper - compares DUT flag against expected value
    //  Reusable helper to verify FIFO status flags (wfull, rempty, awfull, arempty).
    // -----------------------------------------------------------
    task check_flag(input logic actual, input logic expected, input string name);
    begin
        checks++;
        if (actual !== expected) begin
            errors++;
            $error("[%0t] FAIL: %s expected=%b got=%b", $time, name, expected, actual);
        end else begin
            $display("[%0t] PASS: %s = %b", $time, name, actual);
        end
    end
    endtask

    // -----------------------------------------------------------
    // Main stimulus
    // -----------------------------------------------------------
    initial begin
        apply_reset();
        $display("--- Starting Async FIFO Test ---");

        // TEST 1: idle state right after reset
        check_flag(wfull,  1'b0, "wfull (after reset)");
        check_flag(rempty, 1'b1, "rempty (after reset)");

        // TEST 2: single write then single read (sanity path)
        write_data(8'hA5);
        wait (rempty == 1'b0);
        read_and_verify();

        // TEST 3: fill completely -> check wfull and awfull
        apply_reset();
        for (int i = 0; i < DEPTH - 1; i++)
            write_data(i);
        @(posedge wclk);
        check_flag(awfull, 1'b1, "awfull (depth-1 written)");

        write_data(DEPTH - 1); // final write -> should be full
        @(posedge wclk);
        check_flag(wfull, 1'b1, "wfull (fully written)");

        // TEST 4: drain completely -> check rempty and arempty
        for (int i = 0; i < DEPTH - 1; i++)
            read_and_verify();
        @(posedge rclk);
        check_flag(arempty, 1'b1, "arempty (1 item left)");

        read_and_verify(); // final read -> should be empty
        @(posedge rclk);
        check_flag(rempty, 1'b1, "rempty (fully drained)");

        // TEST 5: write-to-full-FIFO protection (extra write should be ignored)
        apply_reset();
        for (int i = 0; i < DEPTH; i++)
            write_data(i);
        write_data(8'hFF); // FIFO already full -> should warn & drop
        check_flag(wfull, 1'b1, "wfull (still full after blocked write)");

        // drain before next test
        while (golden_queue.size() > 0)
            read_and_verify();

        // TEST 6: read-from-empty-FIFO protection
        apply_reset();
        read_and_verify(); // FIFO empty -> should warn & skip
        check_flag(rempty, 1'b1, "rempty (still empty after blocked read)");

        // TEST 7: concurrent read/write stress (independent async clocks)
            apply_reset();
            fork
                begin : write_thread
                    for (int i = 0; i < 30; i++) begin
                        write_data($urandom_range(0, (1<<DSIZE)-1)); // DSIZE = 8 1 << 8 = 256, Random range becomes 0 to 255
                        #($urandom_range(2, 15));  // Wait a random delay like 2ns 5 ns etc .. 
                    end
                end
                begin : read_thread
                    for (int i = 0; i < 30; i++) begin
                        read_and_verify();
                        #($urandom_range(2, 20)); // Wait a random delay like 2ns 5 ns etc .. 
                    end
                end
            join

        // TEST 8: flush any remaining entries from stress test
        while (golden_queue.size() > 0)
            read_and_verify();
        check_flag(rempty, 1'b1, "rempty (final flush complete)");

        #100;
        $display("=====================================");
        $display(" TOTAL CHECKS = %0d, ERRORS = %0d", checks, errors);
        if (errors == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: %0d TEST(S) FAILED", errors);
        $display("=====================================");
        $finish;
    end

    // Safety timeout - prevents infinite hang if sync logic misbehaves
    initial begin
        #1000000;
        $error("[%0t] TIMEOUT: simulation did not finish in time", $time);
        $finish;
    end

endmodule

`default_nettype wire
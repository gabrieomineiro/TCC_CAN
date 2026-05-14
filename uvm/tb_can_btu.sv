//==================================================
// Top-level testbench for CAN BTU
//==================================================
module tb_can_btu;
    
    // UVM includes
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    // Include all testbench files
    `include "can_btu_seq_item.sv"
    `include "can_btu_sequence.sv"
    `include "can_btu_coverage.sv"
    `include "can_btu_driver.sv"
    `include "can_btu_monitor.sv"
    `include "can_btu_agent.sv"
    `include "can_btu_scoreboard.sv"
    `include "can_btu_env.sv"
    `include "can_btu_test.sv"
    
    // Clock generation
    logic clk;
    initial begin
        clk = 0;
        forever #10 clk = ~clk;  // 50MHz clock
    end
    
    // Interface instance
    can_btu_if btu_if(.clk(clk));
    
    // DUT instance
    can_btu_top #(
        .CLK_FREQ_HZ(50_000_000),
        .BAUD_RATE(500_000)
    )DUT (
        .clk(btu_if.clk),
        .rst_n(btu_if.rst_n),
        .prescaler(btu_if.prescaler),
        .prop_seg(btu_if.prop_seg),
        .phase_seg1(btu_if.phase_seg1),
        .phase_seg2(btu_if.phase_seg2),
        .sjw(btu_if.sjw),
        .can_rx(btu_if.can_rx),
        .sync_en(btu_if.sync_en),
        .hard_sync(btu_if.hard_sync),
        .bit_tick(btu_if.bit_tick),
        .sample_tick(btu_if.sample_tick),
        .tx_tick(btu_if.tx_tick),
        .sample_point(btu_if.sample_point),
        .bit_time_cnt(btu_if.bit_time_cnt),
        .sync_locked(btu_if.sync_locked),
        .edge_detected(btu_if.edge_detected),
        .sync_active(btu_if.sync_active),
        .fsm_state(btu_if.fsm_state)
    );
    
    // Initial block for UVM configuration and run
    initial begin
        // Set interface in config DB
        uvm_config_db #(virtual can_btu_if)::set(null, "*", "vif", btu_if);
        
        // Enable waveform dump
        $dumpfile("can_btu_tb.vcd");
        $dumpvars(0, tb_can_btu);
        
        // Run test
        run_test("can_btu_test");
    end
    
    // Initial block for reset
    initial begin
        btu_if.rst_n = 1'b0;
        #50;
        btu_if.rst_n = 1'b1;
    end
    
endmodule

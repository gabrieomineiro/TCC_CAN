//==================================================
// Top-level testbench for CAN BTU (RTL)
//==================================================
module tb_can_btu;

    // UVM e package do projeto
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import can_btu_pkg::*;

    // Geração de clock
    logic clk;
    initial begin
        clk = 0;
        forever #10 clk = ~clk;  // clock de 50 MHz (período 20 ns)
    end

    // Instância da interface
    can_btu_if btu_if(.clk(clk));

    // DUT em nível RTL (não o netlist sintetizado)
    can_btu #(
        .CLK_FREQ_HZ(50_000_000),
        .BAUD_RATE(500_000)
    ) DUT (
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

    // Configuração UVM e disparo do teste
    initial begin
        string tname;
        // Interface no config DB
        uvm_config_db #(virtual can_btu_if)::set(null, "*", "vif", btu_if);

        // Dump de formas de onda
        $dumpfile("can_btu_tb.vcd");
        $dumpvars(0, tb_can_btu);

        // Teste selecionado via +UVM_TESTNAME (default: can_btu_test)
        if ($value$plusargs("UVM_TESTNAME=%s", tname))
            run_test(tname);
        else
            run_test("can_btu_test");
    end

    // Nota: o reset é controlado pelo driver (apply_reset).
    // A interface inicializa rst_n=0 em time 0 (reset assíncrono seguro).

endmodule

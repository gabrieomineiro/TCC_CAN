//============================================================
// Driver do BTU.
// Recebe um cenário (can_btu_seq_item) e o expande em uma janela
// de clock cycles mantendo a configuração ESTÁVEL, dirigindo
// can_rx/hard_sync/rst_n de forma controlada. Assim o BTU
// efetivamente completa bits (corrige C3).
//============================================================
class can_btu_driver extends uvm_driver #(can_btu_seq_item);
    `uvm_component_utils(can_btu_driver)

    virtual can_btu_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual can_btu_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual can_btu_if não encontrada no config_db")
    endfunction

    task run_phase(uvm_phase phase);
        // Reset inicial sob controle do driver
        apply_reset(6);

        forever begin
            seq_item_port.get_next_item(req);
            drive_scenario(req);
            seq_item_port.item_done();
        end
    endtask

    // Aplica reset assíncrono por N ciclos
    task apply_reset(int n);
        vif.drv_cb.rst_n     <= 1'b0;
        vif.drv_cb.hard_sync <= 1'b0;
        vif.drv_cb.can_rx    <= 1'b1;
        vif.drv_cb.sync_en   <= 1'b1;
        repeat (n) @(vif.drv_cb);
        vif.drv_cb.rst_n     <= 1'b1;
        @(vif.drv_cb);
    endtask

    task drive_scenario(can_btu_seq_item req);
        int total_tq = req.total_tq();
        int presc    = req.presc_safe();
        int bit_len  = total_tq * presc;
        int window   = req.num_bits * bit_len;

        // Configuração estável
        vif.drv_cb.prescaler  <= req.prescaler;
        vif.drv_cb.prop_seg   <= req.prop_seg;
        vif.drv_cb.phase_seg1 <= req.phase_seg1;
        vif.drv_cb.phase_seg2 <= req.phase_seg2;
        vif.drv_cb.sjw        <= req.sjw;
        vif.drv_cb.sync_en    <= req.sync_en;
        vif.drv_cb.hard_sync  <= 1'b0;
        vif.drv_cb.rst_n      <= 1'b1;
        vif.drv_cb.can_rx     <= 1'b1;
        @(vif.drv_cb);  // efetiva config

        // Hard sync: segura por presc+2 ciclos para sobrepor um presc_tick
        if (req.do_hard_sync) begin
            vif.drv_cb.hard_sync <= 1'b1;
            repeat (presc + 2) @(vif.drv_cb);
            vif.drv_cb.hard_sync <= 1'b0;
        end

        // Janela de bits
        for (int c = 0; c < window; c++) begin
            int cyc_in_bit = c % bit_len;
            int tq         = cyc_in_bit / presc;
            logic bus      = 1'b1;  // recessivo por default
            if (req.edge_at_tq != 0 && tq == req.edge_at_tq)
                bus = 1'b0;          // dominante -> borda de descida (soft sync)
            vif.drv_cb.can_rx <= bus;

            // Reset injetado no meio da janela
            if (req.inject_reset && c == (window/2)) begin
                vif.drv_cb.rst_n <= 1'b0;
                repeat (3) @(vif.drv_cb);
                vif.drv_cb.rst_n <= 1'b1;
            end

            @(vif.drv_cb);
        end
    endtask
endclass

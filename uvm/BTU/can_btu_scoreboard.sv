//============================================================
// Scoreboard do BTU (verificação por propriedades + medições).
//
// Filosofia: em vez de espelhar a FSM de sincronismo do RTL
// (arriscado sem simulador), verificamos PROPRIEDADES/INVARIÁNTES
// derivadas da ISO 11898-1 que devem valer independentemente dos
// detalhes internos, mais medições diretas (período de bit,
// ponto de amostragem). Baixo risco de falso-negativo.
//
// Propriedades verificadas (por ciclo, quando fora de reset):
//   P1  edge_detected <=> borda de descida em can_rx
//   P2  bit_tick      => bit_time_cnt == 0
//   P3  tx_tick       => bit_time_cnt == 1
//   P4  sample_tick   => sample_point == 1
//   P5  sample_tick   => bit_time_cnt em [sample_tq_base, sample_tq_base+sjw]
//   P6  sample_point  => bit_time_cnt >= sample_tq_base  (não cedo demais)
//   P7  período entre bit_ticks em [nominal - sjw*presc, nominal + sjw*presc]
//   P8  reset: bit_tick/sample_tick não pulsam com rst_n=0
//============================================================
class can_btu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(can_btu_scoreboard)

    uvm_analysis_imp_monitor #(can_btu_seq_item, can_btu_scoreboard) monitor_export;

    // Estado
    can_btu_seq_item prev;
    int cycle_cnt;
    int last_bit_tick_cycle;
    bit have_prev_bit_tick;
    bit hs_in_interval;          // hard_sync visto no intervalo entre bit_ticks
    logic [31:0] last_cfg_sig;   // assinatura da config no último bit_tick
    bit in_reset;

    // Estatísticas
    int n_cycles;
    int n_bit_ticks;
    int n_sample_ticks;
    int n_edges;
    int err_edge, err_bit_tick, err_tx_tick, err_sample_point_consistency;
    int err_sample_window, err_sample_early, err_period, err_reset_activity;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor_export = new("monitor_export", this);
        cycle_cnt = 0;
        last_bit_tick_cycle = 0;
        have_prev_bit_tick = 0;
        hs_in_interval = 0;
        last_cfg_sig = 0;
        in_reset = 1;
    endfunction

    function logic [31:0] cfg_sig(can_btu_seq_item it);
        return {it.prescaler, it.prop_seg, it.phase_seg1, it.phase_seg2, it.sjw};
    endfunction

    function void write_monitor(can_btu_seq_item item);
        cycle_cnt++;
        n_cycles++;

        // ---- Reset ----
        if (item.rst_n == 1'b0) begin
            in_reset = 1;
            prev = item;
            have_prev_bit_tick = 0;   // pós-reset: nova linha de base
            hs_in_interval     = 0;
            // Em reset, sinais de tick não devem pulsar (P8)
            if (item.bit_tick || item.sample_tick || item.tx_tick) begin
                `uvm_error("BTU_RST", $sformatf("Tick ativo durante reset (ciclo %0d)", cycle_cnt))
                err_reset_activity++;
            end
            return;
        end
        in_reset = 0;

        // ---- P1: edge_detected <=> borda de descida ----
        if (prev != null) begin
            logic expected_edge = (prev.can_rx == 1'b1) && (item.can_rx == 1'b0);
            if (item.edge_detected !== expected_edge) begin
                `uvm_error("BTU_EDGE", $sformatf(
                    "edge_detected=%b mas borda esperada=%b (prev_rx=%b cur_rx=%b, ciclo %0d)",
                    item.edge_detected, expected_edge, prev.can_rx, item.can_rx, cycle_cnt))
                err_edge++;
            end
            if (expected_edge) n_edges++;
        end

        // ---- P2: bit_tick => btc==0 ----
        if (item.bit_tick) begin
            if (item.bit_time_cnt != 8'd0) begin
                `uvm_error("BTU_BITTICK", $sformatf(
                    "bit_tick=1 mas bit_time_cnt=%0d (esperado 0), ciclo %0d",
                    item.bit_time_cnt, cycle_cnt))
                err_bit_tick++;
            end
            n_bit_ticks++;
        end

        // ---- P3: tx_tick => btc==1 ----
        if (item.tx_tick) begin
            if (item.bit_time_cnt != 8'd1) begin
                `uvm_error("BTU_TXTICK", $sformatf(
                    "tx_tick=1 mas bit_time_cnt=%0d (esperado 1), ciclo %0d",
                    item.bit_time_cnt, cycle_cnt))
                err_tx_tick++;
            end
        end

        // ---- P4: sample_tick => sample_point ----
        if (item.sample_tick) begin
            if (!item.sample_point) begin
                `uvm_error("BTU_SPTICK", $sformatf(
                    "sample_tick=1 mas sample_point=0, ciclo %0d", cycle_cnt))
                err_sample_point_consistency++;
            end
            n_sample_ticks++;

            // ---- P5: sample_tick => btc em [base, base+sjw] ----
            begin
                int base = item.sample_tq_base();
                int lo   = base;
                int hi   = base + int'(item.sjw);
                int btc  = int'(item.bit_time_cnt);
                if (btc < lo || btc > hi) begin
                    `uvm_error("BTU_SPWIN", $sformatf(
                        "sample_tick em btc=%0d fora de [%0d,%0d] (sjw=%0d), ciclo %0d",
                        btc, lo, hi, item.sjw, cycle_cnt))
                    err_sample_window++;
                end
            end
        end

        // ---- P6: sample_point => btc >= base (não cedo demais) ----
        if (item.sample_point) begin
            int base = item.sample_tq_base();
            if (int'(item.bit_time_cnt) < base) begin
                `uvm_error("BTU_SPEARLY", $sformatf(
                    "sample_point=1 com btc=%0d < sample_tq_base=%0d, ciclo %0d",
                    item.bit_time_cnt, base, cycle_cnt))
                err_sample_early++;
            end
        end

        // ---- acompanha hard_sync no intervalo ----
        if (item.hard_sync) hs_in_interval = 1;

        // ---- P7: período entre bit_ticks ----
        if (item.bit_tick) begin
            if (have_prev_bit_tick && !hs_in_interval && cfg_sig(item) == last_cfg_sig) begin
                int presc    = item.presc_safe();
                int nominal  = item.total_tq() * presc;
                int measured = cycle_cnt - last_bit_tick_cycle;
                int slack    = int'(item.sjw) * presc;
                if (measured < nominal - slack || measured > nominal + slack) begin
                    `uvm_error("BTU_PERIOD", $sformatf(
                        "período de bit=%0d fora de [%0d,%0d] (nominal=%0d, sjw*presc=%0d), ciclo %0d",
                        measured, nominal-slack, nominal+slack, nominal, slack, cycle_cnt))
                    err_period++;
                end
            end
            last_bit_tick_cycle = cycle_cnt;
            last_cfg_sig        = cfg_sig(item);
            have_prev_bit_tick  = 1;
            hs_in_interval      = 0;   // reinicia para o próximo intervalo
        end

        prev = item;
    endfunction

    function void report_phase(uvm_phase phase);
        string s;
        int total_err;
        total_err = err_edge + err_bit_tick + err_tx_tick +
                    err_sample_point_consistency + err_sample_window +
                    err_sample_early + err_period + err_reset_activity;

        s = "\n----------------------------------------------------------\n";
        s = {s, "CAN BTU SCOREBOARD (verificacao por propriedades)\n"};
        s = {s, $sformatf("  Ciclos amostrados ......... %0d\n", n_cycles)};
        s = {s, $sformatf("  bit_ticks observados ...... %0d\n", n_bit_ticks)};
        s = {s, $sformatf("  sample_ticks observados ... %0d\n", n_sample_ticks)};
        s = {s, $sformatf("  bordas de descida ......... %0d\n", n_edges)};
        s = {s, "  ---- erros ----\n"};
        s = {s, $sformatf("  P1 edge_detected .......... %0d\n", err_edge)};
        s = {s, $sformatf("  P2 bit_tick@0 ............. %0d\n", err_bit_tick)};
        s = {s, $sformatf("  P3 tx_tick@1 .............. %0d\n", err_tx_tick)};
        s = {s, $sformatf("  P4 sample_tick=>sp ........ %0d\n", err_sample_point_consistency)};
        s = {s, $sformatf("  P5 sample window .......... %0d\n", err_sample_window)};
        s = {s, $sformatf("  P6 sample_point cedo ...... %0d\n", err_sample_early)};
        s = {s, $sformatf("  P7 periodo de bit ......... %0d\n", err_period)};
        s = {s, $sformatf("  P8 atividade em reset ..... %0d\n", err_reset_activity)};
        if (total_err == 0)
            s = {s, "  Resultado: PASSOU\n"};
        else
            s = {s, $sformatf("  Resultado: FALHOU (%0d erros)\n", total_err)};
        s = {s, "----------------------------------------------------------\n"};
        `uvm_info(get_type_name(), s, UVM_LOW)
    endfunction
endclass

//============================================================
// Cobertura do BTU.
// Recebe os itens por ciclo (env: agent_ap -> cov), mantém um
// rastreador de bits próprio e amostra covergroups nas fronteiras
// de bit. Bins ALCANÇÁVEIS (sem os placeholders coverpoint 0).
//
// Covergroups:
//   cfg_cg        : F01,F02 - config exercitada (presc, segs, sjw, total_tq)
//   sample_cg     : F03     - ponto de amostragem observado (% do bit)
//   sync_cg       : F04,F05,F06 - hard sync, soft sync (antes/depois), clamp sjw
//   period_cg     : F09     - consistência/medida do período de bit
//============================================================
`ifndef CAN_BTU_COV_SV
`define CAN_BTU_COV_SV

class can_btu_coverage extends uvm_component;
    `uvm_component_utils(can_btu_coverage)

    uvm_analysis_imp #(can_btu_seq_item, can_btu_coverage) analysis_export;

    int total_samples;

    // ---- rastreador de bits ----
    can_btu_seq_item prev;
    int cycle_cnt;
    int last_bit_tick_cycle;
    bit have_prev_bit_tick;
    bit hs_in_interval;
    logic [31:0] last_cfg_sig;

    // eventos no bit corrente
    bit hard_sync_in_bit;
    int edge_pos_before;   // qtos edges antes do sample
    int edge_pos_after;    // qtos edges depois do sample
    bit sjw_clamp_seen;    // edge com |delta|>sjw do sample

    //==== Covergroup: configuração (F01, F02) ====
    covergroup cfg_cg with function sample(can_btu_seq_item it);
        option.per_instance = 1;
        option.name = "cfg_cg";
        cp_prescaler: coverpoint it.prescaler {
            bins p_min  = {1};
            bins p_low  = {[2:6]};
            bins p_mid  = {[7:20]};
            bins p_high = {[21:255]};
        }
        cp_prop_seg: coverpoint it.prop_seg   { bins b[] = {[1:7]}; }
        cp_phase1:   coverpoint it.phase_seg1 { bins b[] = {[1:7]}; }
        cp_phase2:   coverpoint it.phase_seg2 { bins b[] = {[2:7]}; }
        cp_sjw:      coverpoint it.sjw        { bins b[] = {[1:3]}; }
        cp_total_tq: coverpoint it.total_tq() {
            bins tq_min = {5};
            bins tq_low = {[6:10]};
            bins tq_mid = {[11:16]};
            bins tq_max = {[17:22]};
        }
    endgroup

    //==== Covergroup: ponto de amostragem (F03) ====
    // Amostrado a cada sample_tick com a config observada.
    covergroup sample_cg with function sample(int sample_tq, int total_tq);
        option.per_instance = 1;
        option.name = "sample_cg";
        cp_sample_permille: coverpoint ((sample_tq*1000)/total_tq) {
            bins sp_very_early = {[0:499]};    // < 50%  (fora do recomendado ISO)
            bins sp_early      = {[500:624]};  // 50-62.5%
            bins sp_nominal    = {[625:749]};  // 62.5-75%
            bins sp_late       = {[750:875]};  // 75-87.5%
            bins sp_very_late  = {[876:1000]}; // > 87.5%
        }
    endgroup

    //==== Covergroup: sincronismo (F04, F05, F06) ====
    covergroup sync_cg with function sample(bit hs_in_bit, int e_before, int e_after, bit clamp);
        option.per_instance = 1;
        option.name = "sync_cg";
        cp_hard_sync:  coverpoint hs_in_bit { bins no={0}; bins yes={1}; }
        cp_edge_pos:   coverpoint ((e_before>0) ? 1 : ((e_after>0) ? 2 : 0)) {
            bins none=    {0};
            bins before = {1};  // edge antes do sample -> alonga phase_seg1
            bins after  = {2};  // edge depois do sample -> encurta phase_seg2
        }
        cp_sjw_clamp:  coverpoint clamp { bins no_clamp={0}; bins clamped={1}; }
    endgroup

    //==== Covergroup: período de bit (F09) ====
    covergroup period_cg with function sample(int measured, int nominal);
        option.per_instance = 1;
        option.name = "period_cg";
        cp_category: coverpoint ((measured < nominal) ? 0 : ((measured > nominal) ? 2 : 1)) {
            bins shortened = {0};
            bins nominal   = {1};
            bins extended  = {2};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        analysis_export = new("analysis_export", this);
        total_samples = 0;
        cycle_cnt = 0;
        have_prev_bit_tick = 0;
        hs_in_interval = 0;
        cfg_cg   = new();
        sample_cg= new();
        sync_cg  = new();
        period_cg= new();
    endfunction

    function logic [31:0] cfg_sig(can_btu_seq_item it);
        return {it.prescaler, it.prop_seg, it.phase_seg1, it.phase_seg2, it.sjw};
    endfunction

    function void write(can_btu_seq_item it);
        int sample_tq_base;
        total_samples++;
        if (it.rst_n == 1'b0) begin
            prev = it;
            have_prev_bit_tick = 0;   // pós-reset: nova linha de base
            hs_in_interval     = 0;
            hard_sync_in_bit   = 0;
            edge_pos_before    = 0;
            edge_pos_after     = 0;
            sjw_clamp_seen     = 0;
            return;
        end

        sample_tq_base = it.sample_tq_base();

        // detecta borda (como o scoreboard) e classifica posição
        if (prev != null && prev.can_rx == 1'b1 && it.can_rx == 1'b0) begin
            int eq = int'(it.bit_time_cnt);
            if (eq < sample_tq_base) edge_pos_before++;
            else                     edge_pos_after++;
            if ((eq < sample_tq_base && (sample_tq_base - eq) > int'(it.sjw)) ||
                (eq >= sample_tq_base && (eq - sample_tq_base) > int'(it.sjw)))
                sjw_clamp_seen = 1;
        end
        if (it.hard_sync) begin
            hard_sync_in_bit = 1;
            hs_in_interval = 1;
        end

        // sample_tick -> ponto de amostragem observado
        if (it.sample_tick)
            sample_cg.sample(int'(it.bit_time_cnt), it.total_tq());

        // bit_tick -> fecha o bit, amostra cfg/sync/period
        if (it.bit_tick) begin
            cfg_cg.sample(it);
            sync_cg.sample(hard_sync_in_bit, edge_pos_before, edge_pos_after, sjw_clamp_seen);

            if (have_prev_bit_tick && !hs_in_interval && cfg_sig(it) == last_cfg_sig) begin
                int presc    = it.presc_safe();
                int nominal  = it.total_tq() * presc;
                int measured = cycle_cnt - last_bit_tick_cycle;
                period_cg.sample(measured, nominal);
            end

            // reinicia acumuladores do bit
            last_bit_tick_cycle = cycle_cnt;
            last_cfg_sig        = cfg_sig(it);
            have_prev_bit_tick  = 1;
            hs_in_interval      = 0;
            hard_sync_in_bit    = 0;
            edge_pos_before     = 0;
            edge_pos_after      = 0;
            sjw_clamp_seen      = 0;
        end

        cycle_cnt++;
        prev = it;
    endfunction

    function void report_phase(uvm_phase phase);
        string s;
        real c_cfg, c_samp, c_sync, c_per;
        c_cfg  = cfg_cg.get_coverage();
        c_samp = sample_cg.get_coverage();
        c_sync = sync_cg.get_coverage();
        c_per  = period_cg.get_coverage();
        s = "\n";
        s = {s, "+----------------------------------------------------------+\n"};
        s = {s, "|              CAN BTU COVERAGE REPORT                     |\n"};
        s = {s, "+----------------------------------------------------------+\n"};
        s = {s, $sformatf("| Amostras (ciclos) ............ %0d\n", total_samples)};
        s = {s, $sformatf("| Config (F01,F02) ............. %5.2f%%\n", c_cfg)};
        s = {s, $sformatf("| Sample point (F03) ........... %5.2f%%\n", c_samp)};
        s = {s, $sformatf("| Sincronismo (F04,F05,F06) .... %5.2f%%\n", c_sync)};
        s = {s, $sformatf("| Periodo de bit (F09) ......... %5.2f%%\n", c_per)};
        s = {s, "+----------------------------------------------------------+\n"};
        `uvm_info(get_type_name(), s, UVM_LOW)
    endfunction
endclass

`endif

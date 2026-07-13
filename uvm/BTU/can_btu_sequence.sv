//============================================================
// Sequências do BTU.
//   can_btu_random_seq     : cenários aleatórios (F01,F02,F03,F07)
//   can_btu_hard_sync_seq  : hard sync (F04)
//   can_btu_soft_sync_seq  : bordas em TQs antes/depois do sample (F05)
//   can_btu_sjw_sat_seq    : phase error > sjw -> clamp (F06)
//   can_btu_baud_seq       : configs 125k/250k/500k/1M (F09)
//   can_btu_boundary_seq   : config mínima/máxima
//   can_btu_reset_seq      : reset no meio da operação (F10)
//============================================================

class can_btu_base_seq extends uvm_sequence #(can_btu_seq_item);
    `uvm_object_utils(can_btu_base_seq)
    function new(string name = "can_btu_base_seq");
        super.new(name);
    endfunction
endclass

//---------------- RANDOM ----------------
class can_btu_random_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_random_seq)
    int count = 40;
    function new(string name = "can_btu_random_seq");
        super.new(name);
    endfunction
    task body();
        can_btu_seq_item it;
        `uvm_info(get_type_name(), "Sequencia aleatoria iniciada", UVM_MEDIUM)
        repeat (count) begin
            it = can_btu_seq_item::type_id::create("it");
            start_item(it);
            if (!it.randomize()) `uvm_error(get_type_name(), "randomize falhou (random)")
            finish_item(it);
        end
    endtask
endclass

//---------------- HARD SYNC (F04) ----------------
class can_btu_hard_sync_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_hard_sync_seq)
    function new(string name = "can_btu_hard_sync_seq");
        super.new(name);
    endfunction
    task body();
        `uvm_info(get_type_name(), "Sequencia hard-sync iniciada", UVM_MEDIUM)
        for (int i = 0; i < 8; i++) begin
            can_btu_seq_item it = can_btu_seq_item::type_id::create("it");
            start_item(it);
            if (!it.randomize() with {
                do_hard_sync == 1;
                edge_at_tq   == 0;
                inject_reset == 0;
                num_bits     == 5;
            }) `uvm_error(get_type_name(), "randomize falhou (hard_sync)")
            finish_item(it);
        end
    endtask
endclass

//---------------- SOFT SYNC (F05) ----------------
class can_btu_soft_sync_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_soft_sync_seq)
    function new(string name = "can_btu_soft_sync_seq");
        super.new(name);
    endfunction
    task body();
        `uvm_info(get_type_name(), "Sequencia soft-sync iniciada", UVM_MEDIUM)
        for (int i = 0; i < 16; i++) begin
            can_btu_seq_item it = can_btu_seq_item::type_id::create("it");
            start_item(it);
            if (!it.randomize() with {
                do_hard_sync == 0;
                edge_at_tq   != 0;
                inject_reset == 0;
                num_bits     == 5;
            }) `uvm_error(get_type_name(), "randomize falhou (soft_sync)")
            finish_item(it);
        end
    endtask
endclass

//---------------- SJW SATURATION (F06) ----------------
class can_btu_sjw_sat_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_sjw_sat_seq)
    function new(string name = "can_btu_sjw_sat_seq");
        super.new(name);
    endfunction
    task body();
        `uvm_info(get_type_name(), "Sequencia SJW-saturation iniciada", UVM_MEDIUM)
        for (int i = 0; i < 8; i++) begin
            can_btu_seq_item it = can_btu_seq_item::type_id::create("it");
            start_item(it);
            if (!it.randomize() with {
                sjw          == 1;
                phase_seg1   == 7;
                phase_seg2   == 7;
                prop_seg     == 7;
                do_hard_sync == 0;
                edge_at_tq   == 1;
                inject_reset == 0;
                num_bits     == 5;
            }) `uvm_error(get_type_name(), "randomize falhou (sjw_sat)")
            finish_item(it);
        end
    endtask
endclass

//---------------- BAUD RATES (F09) ----------------
// total_tq=10 (prop=2,seg1=5,seg2=2) -> sample 80%.
// 50MHz: baud = 50e6/(10*presc)
class can_btu_baud_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_baud_seq)
    function new(string name = "can_btu_baud_seq");
        super.new(name);
    endfunction
    task body();
        int prescs[] = '{5, 10, 20, 40};   // 1M, 500k, 250k, 125k
        `uvm_info(get_type_name(), "Sequencia baud-rates iniciada", UVM_MEDIUM)
        foreach (prescs[i]) begin
            can_btu_seq_item it = can_btu_seq_item::type_id::create("it");
            start_item(it);
            if (!it.randomize() with {
                prescaler    == prescs[i];
                prop_seg     == 2;
                phase_seg1   == 5;
                phase_seg2   == 2;
                sjw          == 2;
                sync_en      == 1;
                do_hard_sync == 0;
                edge_at_tq   == 0;
                inject_reset == 0;
                num_bits     == 6;
            }) `uvm_error(get_type_name(), "randomize falhou (baud)")
            finish_item(it);
        end
    endtask
endclass

//---------------- BOUNDARY ----------------
class can_btu_boundary_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_boundary_seq)
    function new(string name = "can_btu_boundary_seq");
        super.new(name);
    endfunction
    task body();
        can_btu_seq_item it;
        `uvm_info(get_type_name(), "Sequencia boundary iniciada", UVM_MEDIUM)

        it = can_btu_seq_item::type_id::create("it");
        start_item(it);
        if (!it.randomize() with {
            prescaler == 1; prop_seg == 1; phase_seg1 == 1; phase_seg2 == 2; sjw == 1;
            do_hard_sync == 0; edge_at_tq == 0; inject_reset == 0; num_bits == 6;
        }) `uvm_error(get_type_name(), "randomize falhou (boundary min)")
        finish_item(it);

        it = can_btu_seq_item::type_id::create("it");
        start_item(it);
        if (!it.randomize() with {
            prescaler == 255; prop_seg == 7; phase_seg1 == 7; phase_seg2 == 7; sjw == 3;
            do_hard_sync == 0; edge_at_tq == 0; inject_reset == 0; num_bits == 3;
        }) `uvm_error(get_type_name(), "randomize falhou (boundary max)")
        finish_item(it);
    endtask
endclass

//---------------- RESET (F10) ----------------
class can_btu_reset_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_reset_seq)
    function new(string name = "can_btu_reset_seq");
        super.new(name);
    endfunction
    task body();
        `uvm_info(get_type_name(), "Sequencia reset iniciada", UVM_MEDIUM)
        for (int i = 0; i < 4; i++) begin
            can_btu_seq_item it = can_btu_seq_item::type_id::create("it");
            start_item(it);
            if (!it.randomize() with {
                do_hard_sync == 0;
                edge_at_tq   == 0;
                inject_reset == 1;
                num_bits     == 6;
            }) `uvm_error(get_type_name(), "randomize falhou (reset)")
            finish_item(it);
        end
    endtask
endclass

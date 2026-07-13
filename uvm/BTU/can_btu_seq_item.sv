//============================================================
// Transação do BTU.
//   - Seção CONFIG/CENÁRIO (rand): usada pelo driver para
//     descrever uma janela de verificação com config estável.
//   - Seção OBSERVADO (não-rand): preenchida pelo monitor a
//     cada ciclo com os sinais do DUT; consumida pelo
//     scoreboard/coverage.
//============================================================
class can_btu_seq_item extends uvm_sequence_item;

    // ---- Configuração (estável durante a janela) ----
    rand logic [7:0] prescaler;
    rand logic [2:0] prop_seg;
    rand logic [2:0] phase_seg1;
    rand logic [2:0] phase_seg2;
    rand logic [1:0] sjw;
    rand logic       sync_en;

    // ---- Cenário (driver) ----
    rand logic       do_hard_sync;
    rand logic [4:0] edge_at_tq;
    rand int         num_bits;
    rand logic       inject_reset;

    // ---- Observado (monitor) ----
    logic       rst_n;
    logic       can_rx;
    logic       hard_sync;
    logic       bit_tick;
    logic       sample_tick;
    logic       tx_tick;
    logic       sample_point;
    logic [7:0] bit_time_cnt;
    logic       sync_locked;
    logic       edge_detected;
    logic       sync_active;
    logic [2:0] fsm_state;

    `uvm_object_utils_begin(can_btu_seq_item)
        `uvm_field_int(prescaler,    UVM_DEFAULT)
        `uvm_field_int(prop_seg,     UVM_DEFAULT)
        `uvm_field_int(phase_seg1,   UVM_DEFAULT)
        `uvm_field_int(phase_seg2,   UVM_DEFAULT)
        `uvm_field_int(sjw,          UVM_DEFAULT)
        `uvm_field_int(sync_en,      UVM_DEFAULT)
        `uvm_field_int(do_hard_sync, UVM_DEFAULT)
        `uvm_field_int(edge_at_tq,   UVM_DEFAULT)
        `uvm_field_int(num_bits,     UVM_DEFAULT)
        `uvm_field_int(inject_reset, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "can_btu_seq_item");
        super.new(name);
    endfunction

    // Encoding atual: 3-bit seg = 0..7, 2-bit sjw = 0..3, 8-bit presc = 0..255.
    constraint c_valid_timing {
        prescaler  inside {[1:255]};
        prop_seg   inside {[1:7]};
        phase_seg1 inside {[1:7]};
        phase_seg2 inside {[2:7]};
        sjw        inside {[1:3]};
        sjw <= phase_seg1;
        sjw <= phase_seg2;
    }
    constraint c_prescaler_dist {
        prescaler dist {1 := 25, [2:6] :/ 35, [7:20] :/ 25, [21:255] :/ 15};
    }
    constraint c_sync_en    { sync_en dist {1'b1 := 9, 1'b0 := 1}; }
    constraint c_hard_sync  { do_hard_sync dist {1'b1 := 2, 1'b0 := 8}; }
    constraint c_edge       { edge_at_tq dist {0 := 45, [1:22] :/ 55}; }
    constraint c_num_bits   { num_bits inside {[3:8]}; }
    constraint c_inject_rst { inject_reset dist {1'b0 := 19, 1'b1 := 1}; }
    constraint c_edge_range { edge_at_tq == 0 || edge_at_tq <= 22; }

    // ---- Helpers ----
    function int presc_safe();
        return (prescaler == 8'd0) ? 1 : int'(prescaler);
    endfunction
    function int total_tq();
        return 1 + int'(prop_seg) + int'(phase_seg1) + int'(phase_seg2);
    endfunction
    function int sample_tq_base();
        return 1 + int'(prop_seg) + int'(phase_seg1);
    endfunction
    function int bit_cycles();
        return total_tq() * presc_safe();
    endfunction
    function int sample_point_permille();
        return (sample_tq_base() * 1000) / total_tq();
    endfunction

endclass

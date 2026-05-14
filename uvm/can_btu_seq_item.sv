//==================================================
// Transaction for CAN BTU
//==================================================
class can_btu_seq_item extends uvm_sequence_item;
    // Configuration inputs
    rand logic [7:0] prescaler;
    rand logic [2:0] prop_seg;
    rand logic [2:0] phase_seg1;
    rand logic [2:0] phase_seg2;
    rand logic [1:0] sjw;
    
    // CAN bus input
    rand logic       can_rx;
    
    // Synchronization inputs
    rand logic       sync_en;
    rand logic       hard_sync;
    
    // Timing outputs (monitored)
    logic            bit_tick;
    logic            sample_tick;
    logic            tx_tick;
    logic            sample_point;
    logic [7:0]      bit_time_cnt;
    logic            sync_locked;
    logic            edge_detected;
    logic            sync_active;
    logic [2:0]      fsm_state;  // BTU FSM actual state
    
    // Constraints for valid CAN timing
    constraint valid_timing {
        prescaler inside {[1:256]};
        prop_seg inside {[1:8]};
        phase_seg1 inside {[1:8]};
        phase_seg2 inside {[2:8]};  // Phase seg2 minimum is 2
        sjw inside {[1:4]};
        
        // SJW cannot exceed phase segments
        sjw <= phase_seg1;
        sjw <= phase_seg2;
    }
    
    // CAN bus constraints
    constraint can_bus {
        can_rx dist {1'b1 := 8, 1'b0 := 2};  // More recessive than dominant
    }
    
    // Sync constraints
    constraint sync_ctrl {
        sync_en dist {1'b1 := 9, 1'b0 := 1};
        hard_sync dist {1'b1 := 1, 1'b0 := 9};
    }
    
    `uvm_object_utils_begin(can_btu_seq_item)
        `uvm_field_int(prescaler, UVM_DEFAULT)
        `uvm_field_int(prop_seg, UVM_DEFAULT)
        `uvm_field_int(phase_seg1, UVM_DEFAULT)
        `uvm_field_int(phase_seg2, UVM_DEFAULT)
        `uvm_field_int(sjw, UVM_DEFAULT)
        `uvm_field_int(can_rx, UVM_DEFAULT)
        `uvm_field_int(sync_en, UVM_DEFAULT)
        `uvm_field_int(hard_sync, UVM_DEFAULT)
        `uvm_field_int(bit_tick, UVM_DEFAULT)
        `uvm_field_int(sample_tick, UVM_DEFAULT)
        `uvm_field_int(tx_tick, UVM_DEFAULT)
        `uvm_field_int(sample_point, UVM_DEFAULT)
        `uvm_field_int(bit_time_cnt, UVM_DEFAULT)
        `uvm_field_int(sync_locked, UVM_DEFAULT)
        `uvm_field_int(edge_detected, UVM_DEFAULT)
        `uvm_field_int(sync_active, UVM_DEFAULT)
        `uvm_field_int(fsm_state, UVM_DEFAULT)
    `uvm_object_utils_end
    
    function new(string name = "can_btu_seq_item");
        super.new(name);
    endfunction
    
    // Function to calculate total time quanta
    function int get_total_tq();
        return 1 + prop_seg + phase_seg1 + phase_seg2;
    endfunction
    
    // Function to calculate sample point position
    function int get_sample_tq();
        return 1 + prop_seg + phase_seg1;
    endfunction
    
    // Function to check if item has valid timing
    function bit is_valid_timing();
        return (prescaler >= 1 && prescaler <= 256) &&
               (prop_seg >= 1 && prop_seg <= 8) &&
               (phase_seg1 >= 1 && phase_seg1 <= 8) &&
               (phase_seg2 >= 2 && phase_seg2 <= 8) &&
               (sjw >= 1 && sjw <= 4) &&
               (sjw <= phase_seg1) &&
               (sjw <= phase_seg2);
    endfunction

endclass

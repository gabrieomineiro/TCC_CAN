//==================================================
// Monitor for CAN BTU
//==================================================
class can_btu_monitor extends uvm_monitor;
    `uvm_component_utils(can_btu_monitor)
    
    virtual can_btu_if vif;
    
    uvm_analysis_port #(can_btu_seq_item) mon_ap;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
        mon_ap = new("mon_ap", this);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db #(virtual can_btu_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Interface not found!")
        end
    endfunction
    
    task run_phase(uvm_phase phase);
        can_btu_seq_item item;
        
        forever begin
            @(vif.mon_cb);
            
            item = can_btu_seq_item::type_id::create("item");
            
            // Capture inputs
            //item.rst_n = vif.mon_cb.rst_n;
            item.prescaler = vif.mon_cb.prescaler;
            item.prop_seg = vif.mon_cb.prop_seg;
            item.phase_seg1 = vif.mon_cb.phase_seg1;
            item.phase_seg2 = vif.mon_cb.phase_seg2;
            item.sjw = vif.mon_cb.sjw;
            item.can_rx = vif.mon_cb.can_rx;
            item.sync_en = vif.mon_cb.sync_en;
            item.hard_sync = vif.mon_cb.hard_sync;
            
            // Capture outputs
            item.bit_tick = vif.mon_cb.bit_tick;
            item.sample_tick = vif.mon_cb.sample_tick;
            item.tx_tick = vif.mon_cb.tx_tick;
            item.sample_point = vif.mon_cb.sample_point;
            item.bit_time_cnt = vif.mon_cb.bit_time_cnt;
            item.sync_locked = vif.mon_cb.sync_locked;
            item.edge_detected = vif.mon_cb.edge_detected;
            item.sync_active = vif.mon_cb.sync_active;
            item.fsm_state = vif.mon_cb.fsm_state;
            
            `uvm_info(get_type_name(), $sformatf("Monitored: bit_tick=%0d, sample_tick=%0d", item.bit_tick, item.sample_tick), UVM_HIGH)
            
            mon_ap.write(item);
        end
    endtask
endclass

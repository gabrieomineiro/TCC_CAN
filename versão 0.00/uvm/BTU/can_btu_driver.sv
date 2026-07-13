//==================================================
// Driver for CAN BTU
//==================================================
class can_btu_driver extends uvm_driver #(can_btu_seq_item);
    `uvm_component_utils(can_btu_driver)
    
    virtual can_btu_if vif;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual can_btu_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Interface not found!")
        end
    endfunction
    
    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            
            // Wait for clock edge
            @(vif.drv_cb);
            
            // Drive signals to DUT
            //vif.drv_cb.rst_n <= req.rst_n;
            vif.drv_cb.prescaler <= req.prescaler;
            vif.drv_cb.prop_seg <= req.prop_seg;
            vif.drv_cb.phase_seg1 <= req.phase_seg1;
            vif.drv_cb.phase_seg2 <= req.phase_seg2;
            vif.drv_cb.sjw <= req.sjw;
            vif.drv_cb.can_rx <= req.can_rx;
            vif.drv_cb.sync_en <= req.sync_en;
            vif.drv_cb.hard_sync <= req.hard_sync;
            
            // Sample outputs
            @(vif.drv_cb);
            req.bit_tick = vif.drv_cb.bit_tick;
            req.sample_tick = vif.drv_cb.sample_tick;
            req.tx_tick = vif.drv_cb.tx_tick;
            req.sample_point = vif.drv_cb.sample_point;
            req.bit_time_cnt = vif.drv_cb.bit_time_cnt;
            req.sync_locked = vif.drv_cb.sync_locked;
            req.edge_detected = vif.drv_cb.edge_detected;
            req.sync_active = vif.drv_cb.sync_active;
            req.fsm_state = vif.drv_cb.fsm_state;
            
            `uvm_info(get_type_name(), $sformatf("Driven: prescaler=%0d, prop_seg=%0d", 
                      req.prescaler, req.prop_seg), UVM_HIGH)
            
            seq_item_port.item_done();
        end
    endtask
endclass

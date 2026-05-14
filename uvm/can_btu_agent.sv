//==================================================
// Agent for CAN BTU
//==================================================
class can_btu_agent extends uvm_agent;
    `uvm_component_utils(can_btu_agent)
    
    uvm_analysis_port #(can_btu_seq_item) agent_ap;
    
    can_btu_driver    drv;
    can_btu_monitor   mon;
    uvm_sequencer #(can_btu_seq_item) seqr;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        agent_ap = new("agent_ap", this);
        
        drv = can_btu_driver::type_id::create("drv", this);
        mon = can_btu_monitor::type_id::create("mon", this);
        seqr = uvm_sequencer #(can_btu_seq_item)::type_id::create("seqr", this);
    endfunction
    
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Connect driver to sequencer
        drv.seq_item_port.connect(seqr.seq_item_export);
        
        // Connect monitor analysis port to agent analysis port
        agent_ap = mon.mon_ap;
    endfunction
endclass
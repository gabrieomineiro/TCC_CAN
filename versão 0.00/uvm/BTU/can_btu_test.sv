//==================================================
// Test for CAN BTU
//==================================================
class can_btu_test extends uvm_test;
    `uvm_component_utils(can_btu_test)
    
    can_btu_env env;
    
    // Test sequences
    can_btu_normal_seq      normal_seq;
    can_btu_hard_sync_seq   hard_sync_seq;
    can_btu_edge_detect_seq edge_detect_seq;
    can_btu_boundary_seq    boundary_seq;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        env = can_btu_env::type_id::create("env", this);
        
        normal_seq = can_btu_normal_seq::type_id::create("normal_seq");
        hard_sync_seq = can_btu_hard_sync_seq::type_id::create("hard_sync_seq");
        edge_detect_seq = can_btu_edge_detect_seq::type_id::create("edge_detect_seq");
        boundary_seq = can_btu_boundary_seq::type_id::create("boundary_seq");
    endfunction
    
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        
        `uvm_info(get_type_name(), "Starting CAN BTU tests...", UVM_LOW)
        
        // Test 1: Normal operation
        `uvm_info(get_type_name(), "Test 1: Normal operation", UVM_LOW)
        normal_seq.start(env.agt.seqr);
        
        // Test 2: Hard synchronization
        `uvm_info(get_type_name(), "Test 2: Hard synchronization", UVM_LOW)
        hard_sync_seq.start(env.agt.seqr);
        
        // Test 3: Edge detection
        `uvm_info(get_type_name(), "Test 3: Edge detection", UVM_LOW)
        edge_detect_seq.start(env.agt.seqr);
        
        // Test 4: Boundary values
        `uvm_info(get_type_name(), "Test 4: Boundary values", UVM_LOW)
        boundary_seq.start(env.agt.seqr);
        
        // Wait a bit for last transactions to complete
        #100;
        
        `uvm_info(get_type_name(), "All tests completed", UVM_LOW)
        
        phase.drop_objection(this);
    endtask
    
    function void report_phase(uvm_phase phase);
        `uvm_info(get_type_name(), "CAN BTU Test completed", UVM_LOW)
    endfunction
endclass
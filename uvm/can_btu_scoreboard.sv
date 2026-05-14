//==================================================
// Scoreboard for CAN BTU
//==================================================
class can_btu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(can_btu_scoreboard)
    
    // Analysis implementation declaration
    `uvm_analysis_imp_decl(_monitor)
    uvm_analysis_imp_monitor #(can_btu_seq_item, can_btu_scoreboard) monitor_export;
    
    // FIFO for storing monitored transactions
    protected uvm_tlm_analysis_fifo #(can_btu_seq_item) item_fifo;
    
    // Reference model predictions
    protected can_btu_seq_item expected_item;
    
    // Statistics
    int total_transactions;
    int matched_transactions;
    int mismatched_transactions;
    int timing_errors;
    int sync_errors;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
        total_transactions = 0;
        matched_transactions = 0;
        mismatched_transactions = 0;
        timing_errors = 0;
        sync_errors = 0;
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        monitor_export = new("monitor_export", this);
        item_fifo = new("item_fifo", this);
        expected_item = can_btu_seq_item::type_id::create("expected_item");
    endfunction
    
    task run_phase(uvm_phase phase);
        can_btu_seq_item actual_item;
        can_btu_seq_item last_item;
	
        
        forever begin
            item_fifo.get(actual_item);
if(last_item == null) last_item = actual_item;
            total_transactions++;
            
            // Perform checks
            check_timing(actual_item);
            check_synchronization(actual_item, last_item);
            check_outputs(actual_item);
	    last_item = actual_item;
	
        end
    endtask
    
    // Write method for monitor
    function void write_monitor(can_btu_seq_item item);
        can_btu_seq_item item_clone;
        $cast(item_clone, item.clone());
        item_fifo.write(item_clone);
    endfunction
    
    // Check timing relationships
    function void check_timing(can_btu_seq_item item);
        // Bit tick should occur at TQ=0
        if (item.bit_tick && item.bit_time_cnt != 0) begin
            `uvm_error(get_type_name(), $sformatf("bit_tick at wrong time: TQ=%0d", item.bit_time_cnt))
            timing_errors++;
        end
        
        // TX tick should occur at TQ=1
        if (item.tx_tick && item.bit_time_cnt != 1) begin
            `uvm_error(get_type_name(), $sformatf("tx_tick at wrong time: TQ=%0d", item.bit_time_cnt))
            timing_errors++;
        end
        
        // Sample point should be within valid range
        if (item.sample_tick) begin
            int sample_tq = 1 + item.prop_seg + item.phase_seg1;
            if (item.bit_time_cnt != sample_tq) begin
                `uvm_error(get_type_name(), $sformatf("sample_tick at wrong TQ: expected=%0d, actual=%0d", 
                          sample_tq, item.bit_time_cnt))
                timing_errors++;
            end
        end
    endfunction
    
    // Check synchronization behavior
    function void check_synchronization(can_btu_seq_item item, can_btu_seq_item last_item);
        // Hard sync should reset counter
        if (item.hard_sync && last_item.hard_sync) begin
            if (item.bit_time_cnt != 0) begin
                `uvm_error(get_type_name(), "Hard sync did not reset TQ counter")
                sync_errors++;
            end
        end
        
        // Edge detection should occur on falling edges
        if (last_item.can_rx == 1 && item.can_rx == 0) begin
            if (!item.edge_detected) begin
                `uvm_error(get_type_name(), "Falling edge not detected")
                sync_errors++;
            end
        end
    endfunction
    
    // Check output consistency
    function void check_outputs(can_btu_seq_item item);
        // Sample_point should be high after sample tick
        if (item.sample_tick && !item.sample_point) begin
            `uvm_error(get_type_name(), "sample_point not high at sample_tick")
            mismatched_transactions++;
        end else if (!item.sample_tick && item.sample_point && item.bit_time_cnt < (1 + item.prop_seg + item.phase_seg1)) begin
            `uvm_error(get_type_name(), "sample_point high before sample point")
            mismatched_transactions++;
        end else begin
            matched_transactions++;
        end
    endfunction
    
    function void report_phase(uvm_phase phase);
        string report_msg;
        
        report_msg = "\n-----------------------------------------------------\n";
        report_msg = {report_msg, "CAN BTU Scoreboard Report\n"};
        report_msg = {report_msg, $sformatf("Total transactions: %0d\n", total_transactions)};
        report_msg = {report_msg, $sformatf("Matched: %0d\n", matched_transactions)};
        report_msg = {report_msg, $sformatf("Mismatched: %0d\n", mismatched_transactions)};
        report_msg = {report_msg, $sformatf("Timing errors: %0d\n", timing_errors)};
        report_msg = {report_msg, $sformatf("Sync errors: %0d\n", sync_errors)};
        
        if (mismatched_transactions == 0 && timing_errors == 0 && sync_errors == 0) begin
            report_msg = {report_msg, "Result: PASSED\n"};
        end else begin
            report_msg = {report_msg, "Result: FAILED\n"};
        end
        
        report_msg = {report_msg, "-----------------------------------------------------\n"};
        
        `uvm_info(get_type_name(), report_msg, UVM_LOW)
    endfunction
    
endclass

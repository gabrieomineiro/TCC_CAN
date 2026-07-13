//==================================================
// Sequences for CAN BTU
//==================================================

// Base sequence
class can_btu_base_seq extends uvm_sequence #(can_btu_seq_item);
    `uvm_object_utils(can_btu_base_seq)
    
    can_btu_seq_item item;
    
    function new(string name = "can_btu_base_seq");
        super.new(name);
    endfunction
    
    task pre_start();
        item = can_btu_seq_item::type_id::create("item");
    endtask
    
    virtual task body();
        `uvm_info(get_type_name(), "Base sequence starting...", UVM_LOW)
    endtask
endclass

// Sequence for normal operation with random values
class can_btu_normal_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_normal_seq)
    
    function new(string name = "can_btu_normal_seq");
        super.new(name);
    endfunction
    
    task body();
        `uvm_info(get_type_name(), "Normal operation sequence", UVM_MEDIUM)
        
        repeat (50) begin
            start_item(item);
            void'(item.randomize());
            finish_item(item);
        end
    endtask
endclass

// Sequence for hard synchronization testing
class can_btu_hard_sync_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_hard_sync_seq)
    
    function new(string name = "can_btu_hard_sync_seq");
        super.new(name);
    endfunction
    
    task body();
        `uvm_info(get_type_name(), "Hard sync test sequence", UVM_MEDIUM)
        
        // First, configure normal timing
        start_item(item);
        void'(item.randomize() with {
            hard_sync == 0;
        });
        finish_item(item);
        
        repeat (5) begin
            // Generate some normal traffic
            start_item(item);
            void'(item.randomize() with {
                hard_sync == 0;
            });
            finish_item(item);
        end
        
        // Force hard sync
        start_item(item);
        void'(item.randomize() with {
            hard_sync == 1;
        });
        finish_item(item);
        
        // Continue normal operation
        repeat (10) begin
            start_item(item);
            void'(item.randomize() with {
                hard_sync == 0;
            });
            finish_item(item);
        end
    endtask
endclass

// Sequence for edge detection testing
class can_btu_edge_detect_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_edge_detect_seq)
    
    function new(string name = "can_btu_edge_detect_seq");
        super.new(name);
    endfunction
    
    task body();
        `uvm_info(get_type_name(), "Edge detection test sequence", UVM_MEDIUM)
        
        // Test falling edges at different times
        for (int i = 0; i < 20; i++) begin
            start_item(item);
            // Generate falling edge (recessive -> dominant)
            void'(item.randomize() with {
                can_rx == 1'b0;  // Dominant
            });
            finish_item(item);
            
            // Stay dominant for a while
            repeat (3) begin
                start_item(item);
                void'(item.randomize() with {
                    can_rx == 1'b0;
                });
                finish_item(item);
            end
            
            // Back to recessive
            start_item(item);
            void'(item.randomize() with {
                can_rx == 1'b1;
            });
            finish_item(item);
        end
    endtask
endclass

// Sequence for boundary value testing
class can_btu_boundary_seq extends can_btu_base_seq;
    `uvm_object_utils(can_btu_boundary_seq)
    
    function new(string name = "can_btu_boundary_seq");
        super.new(name);
    endfunction
    
    task body();
        `uvm_info(get_type_name(), "Boundary value test sequence", UVM_MEDIUM)
        
        // Test minimum values
        start_item(item);
        void'(item.randomize() with {
            prescaler == 1;
            prop_seg == 1;
            phase_seg1 == 1;
            phase_seg2 == 2;
            sjw == 1;
        });
        finish_item(item);
        
        // Test maximum values
        start_item(item);
        void'(item.randomize() with {
            prescaler == 8'd255;
            prop_seg == 8;
            phase_seg1 == 8;
            phase_seg2 == 8;
            sjw == 4;
        });
        finish_item(item);
        
        // Test invalid values (should be constrained)
        repeat (10) begin
            start_item(item);
            void'(item.randomize());
            finish_item(item);
        end
    endtask
endclass

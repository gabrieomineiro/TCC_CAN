//==================================================
// Interface for CAN Bit Timing Unit (BTU)
//==================================================
interface can_btu_if(input logic clk);
    // Reset
    logic       rst_n;
    
    // Configuration inputs
    logic [7:0] prescaler;
    logic [2:0] prop_seg;
    logic [2:0] phase_seg1;
    logic [2:0] phase_seg2;
    logic [1:0] sjw;
    
    // CAN bus input for edge detection
    logic       can_rx;
    
    // Synchronization inputs
    logic       sync_en;
    logic       hard_sync;
    
    // Timing outputs
    logic       bit_tick;
    logic       sample_tick;
    logic       tx_tick;
    logic       sample_point;
    
    // Status outputs
    logic [7:0] bit_time_cnt;
    logic       sync_locked;
    logic       edge_detected;
    logic       sync_active;
    logic [2:0] fsm_state; // BTU FSM actual state
    
    // Clocking block for driver (inputs to DUT)
    clocking drv_cb @(posedge clk);
        default input #1 output #1;
        output rst_n;
        output prescaler;
        output prop_seg;
        output phase_seg1;
        output phase_seg2;
        output sjw;
        output can_rx;
        output sync_en;
        output hard_sync;
        input  bit_tick;
        input  sample_tick;
        input  tx_tick;
        input  sample_point;
        input  bit_time_cnt;
        input  sync_locked;
        input  edge_detected;
        input  sync_active;
        input  fsm_state; 
    endclocking
    
    // Clocking block for monitor (inputs to DUT)
    clocking mon_cb @(posedge clk);
        default input #1 output #1;
        input rst_n;
        input prescaler;
        input prop_seg;
        input phase_seg1;
        input phase_seg2;
        input sjw;
        input can_rx;
        input sync_en;
        input hard_sync;
        input bit_tick;
        input sample_tick;
        input tx_tick;
        input sample_point;
        input bit_time_cnt;
        input sync_locked;
        input edge_detected;
        input sync_active;
        input fsm_state;
    endclocking
    
    // Modports
    modport driver_mp (clocking drv_cb);
    modport monitor_mp (clocking mon_cb);
    
    // Initial values
    initial begin
        rst_n = 1'b0;
        prescaler = 8'd4;      // Default prescaler
        prop_seg = 3'd2;        // Default propagation segment
        phase_seg1 = 3'd4;      // Default phase segment 1
        phase_seg2 = 3'd4;      // Default phase segment 2
        sjw = 2'd2;             // Default sync jump width
        can_rx = 1'b1;          // Default recessive
        sync_en = 1'b1;         // Enable sync by default
        hard_sync = 1'b0;
        //fsm_state = 3'b000;     //Default fsm_state
    end
    
endinterface : can_btu_if

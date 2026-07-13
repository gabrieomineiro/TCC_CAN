module can_arbitration (
    input  logic        clk,
    input  logic        rst_n,
    
    // FIFOs
    input  logic        tx_fifo_empty,
    output logic        tx_fifo_rd_en,
    input  logic [31:0] tx_fifo_data,
    
    // Bus CAN
    input  logic        can_rx,
    output logic        can_tx,
    
    // Protocol_FSM control
    output logic        arbitration_start,
    input  logic        arbitration_done,
    output logic        arbitration_lost,
    
    // Message data
    output logic [10:0] arbitration_id,
    output logic [3:0]  arbitration_dlc,
    output logic [63:0] arbitration_data
);

    // Internal variables
    logic [10:0] current_id;
    logic [3:0]  current_dlc;
    logic [63:0] current_data;
    logic        arbitration_active;
    logic [3:0]  bit_position;
    logic        tx_bit, rx_bit;
    logic        lost_arbitration;
endmodule
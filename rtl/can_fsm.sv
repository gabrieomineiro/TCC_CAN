module can_fsm (
    input  logic        clk,
    input  logic        rst_n,
    
    // Timers
    input  logic        bit_tick,
    input  logic        sample_tick,
    input  logic        tx_tick,
    
    // BTU sync
    input  logic        sync_en,
    input  logic        hard_sync,
    output logic        sync_locked,
    
    // Arbitration
    input  logic        arbitration_start,
    output logic        arbitration_done,
    input  logic        arbitration_lost,
    input  logic [10:0] arbitration_id,
    input  logic [3:0]  arbitration_dlc,
    input  logic [63:0] arbitration_data,
    
    // BSP
    output logic        tx_start,
    input  logic        tx_ack,
    input  logic        tx_eof,
    output logic        rx_data,
    input  logic        rx_ack,
    input  logic        rx_eof,
    
    // CRC
    output logic        crc_en,
    output logic        crc_clear,
    input  logic [14:0] crc_out,
    input  logic        crc_match,
    
    // FIFOs
    output logic        rx_fifo_wr_en,
    input  logic        rx_fifo_full,
    output logic [31:0] rx_fifo_data,
    
    // Error
    output logic        crc_error,
    output logic        stuff_error,
    output logic        ack_error,
    output logic        form_error,
    
    // Status
    output logic [3:0]  fsm_state
);

    // Internal variables
    typedef enum logic [3:0] {
        IDLE,
        START_TX,
        ARBITRATION,
        TX_SOF,
        TX_ID,
        TX_RTR,
        TX_CTRL,
        TX_DATA,
        TX_CRC,
        TX_ACK,
        TX_EOF,
        TX_INTERMISSION,
        RX_IDLE,
        RX_SOF,
        RX_ID,
        RX_RTR,
        RX_CTRL,
        RX_DATA,
        RX_CRC,
        RX_ACK,
        RX_EOF,
        ERROR_FRAME
    } state_t;
    
    state_t current_state, next_state;
    logic [3:0] bit_counter;
    logic [1:0] byte_counter;
    logic [63:0] rx_buffer;
    logic ack_sent, ack_received;
endmodule
//-----------------------------------------------------------------------------
// Módulo: can_fsm
// Descrição: FSM principal do controlador CAN
//            Gerencia estados de transmissão/recepção conforme protocolo CAN
//-----------------------------------------------------------------------------

module can_fsm (
    input  logic        clk,
    input  logic        rst_n,
    
    // Timing signals (from BTU)
    input  logic        bit_tick,
    input  logic        sample_tick,
    input  logic        tx_tick,
    
    // BTU sync
    input  logic        sync_en,
    input  logic        hard_sync,
    output logic        sync_locked,
    
    // Arbitration
    input  logic        arbitration_start,
    input  logic        arbitration_lost,
    input  logic [10:0] arbitration_id,
    input  logic [3:0]  arbitration_dlc,
    input  logic [63:0] arbitration_data,
    
    // BSP
    output logic        bsp_tx_en,
    output logic        bsp_rx_en,
    
    // CRC
    output logic        crc_en,
    output logic        crc_clear,
    input  logic [14:0] crc_out,
    input  logic        crc_match,
    input  logic        crc_error,
    
    // Acceptance filter
    input  logic        id_accepted,
    input  logic        id_rejected,
    
    // FIFOs
    output logic        rx_fifo_wr_en,
    output logic [31:0] rx_fifo_data,
    
    // Error
    input  logic        error_active,
    input  logic        error_passive,
    input  logic        bus_off,
    
    // TX FIFO
    input  logic        tx_fifo_empty,
    input  logic        tx_fifo_full,
    output logic        tx_fifo_rd_en,
    
    // Status outputs
    output logic [3:0]  fsm_state
);

    // Import defines
    `include "can_defines.svh"
    
    // State register
    fsm_state_t current_state, next_state;
    
    // Counters
    logic [3:0] bit_counter;
    logic [1:0] byte_counter;
    
    // Data storage
    logic [63:0] tx_buffer;
    logic [63:0] rx_buffer;
    logic [10:0] rx_id_buffer;
    logic [3:0] rx_dlc_buffer;
    
    // Control signals
    logic ack_sent, ack_received;
    logic tx_complete;
    logic rx_complete;
    logic error_frame_sent;
    
    // FSM sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            bit_counter <= 4'd0;
            byte_counter <= 2'd0;
            rx_id_buffer <= 11'd0;
            rx_dlc_buffer <= 4'd0;
        end else begin
            current_state <= next_state;
            
            case (next_state)
                TX_SOF, TX_ID, TX_EXT_ID, TX_RTR, TX_CTRL, TX_DATA, TX_CRC, TX_ACK, TX_EOF: begin
                    if (tx_tick) begin
                        bit_counter <= bit_counter + 4'd1;
                    end
                end
                
                RX_SOF, RX_ID, RX_EXT_ID, RX_RTR, RX_CTRL, RX_DATA, RX_CRC, RX_ACK, RX_EOF: begin
                    if (sample_tick) begin
                        bit_counter <= bit_counter + 4'd1;
                    end
                end
                
                ERROR_FLAG: begin
                    if (tx_tick) begin
                        bit_counter <= bit_counter + 4'd1;
                    end
                end
                
                default: begin
                    bit_counter <= 4'd0;
                end
            endcase
        end
    end
    
    // FSM combinational next state
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (!tx_fifo_empty && error_active)
                    next_state = TX_SETUP;
                else
                    next_state = RX_IDLE;
            end
            
            TX_SETUP: next_state = TX_SOF;
            
            TX_SOF: begin
                if (bit_counter >= 4'd1) next_state = TX_ID;
            end
            
            TX_ID: begin
                if (arbitration_lost)
                    next_state = RX_IDLE;  // Lost arbitration, become receiver
                else if (bit_counter >= 4'd11)
                    next_state = TX_RTR;
            end
            
            TX_RTR: next_state = TX_CTRL;
            
            TX_CTRL: begin
                if (bit_counter >= 4'd6) next_state = TX_DATA;
            end
            
            TX_DATA: begin
                if (bit_counter >= {2'd0, rx_dlc_buffer, 1'd0}) next_state = TX_CRC;
            end
            
            TX_CRC: begin
                if (bit_counter >= 4'd15) next_state = TX_ACK;
            end
            
            TX_ACK: begin
                if (bit_counter >= 4'd1) next_state = TX_EOF;
            end
            
            TX_EOF: begin
                if (bit_counter >= 4'd7) next_state = INTERMISSION;
            end
            
            INTERMISSION: begin
                next_state = IDLE;
            end
            
            RX_IDLE: begin
                if (!error_active && error_passive) next_state = ERROR_FLAG;
            end
            
            RX_SOF: begin
                if (bit_counter >= 4'd1) next_state = RX_ID;
            end
            
            RX_ID: begin
                if (bit_counter >= 4'd11) next_state = RX_CTRL;
            end
            
            RX_CTRL: begin
                if (bit_counter >= 4'd6) next_state = RX_DATA;
            end
            
            RX_DATA: begin
                if (bit_counter >= {2'd0, rx_dlc_buffer, 1'd0}) next_state = RX_CRC;
            end
            
            RX_CRC: begin
                if (bit_counter >= 4'd15) next_state = RX_ACK;
            end
            
            RX_ACK: begin
                if (bit_counter >= 4'd1) next_state = RX_EOF;
            end
            
            ERROR_FLAG: begin
                if (bit_counter >= 4'd12) next_state = ERROR_WAIT;
            end
            
            ERROR_WAIT: next_state = IDLE;
            
            default: next_state = IDLE;
        endcase
    end
    
    // Control outputs
    assign bsp_tx_en = (current_state inside {TX_SOF, TX_ID, TX_EXT_ID, TX_RTR, TX_CTRL, TX_DATA, TX_CRC, TX_ACK, TX_EOF});
    assign bsp_rx_en = (current_state inside {RX_SOF, RX_ID, RX_EXT_ID, RX_RTR, RX_CTRL, RX_DATA, RX_CRC, RX_ACK});
    assign crc_en = (current_state == TX_CRC);
    assign crc_clear = (current_state inside {TX_SOF, IDLE, RX_SOF});
    
    // Output assignments
    assign fsm_state = current_state;
    assign tx_fifo_rd_en = (current_state == TX_SETUP);

endmodule
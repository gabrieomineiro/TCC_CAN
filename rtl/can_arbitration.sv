//-----------------------------------------------------------------------------
// Módulo: can_arbitration
// Descrição: Lógica de arbitragem CAN - controle de prioridade no barramento
//            Implementa CS (Contention Sampling) para verificar priority
//-----------------------------------------------------------------------------

module can_arbitration (
    input  logic        clk,
    input  logic        rst_n,
    
    // FIFOs
    input  logic        tx_fifo_empty,
    output logic        tx_fifo_rd_en,
    input  logic [31:0] tx_fifo_data,
    
    // CAN Bus interface
    input  logic        can_rx,
    output logic        can_tx,
    
    // Timing signals (from BTU)
    input  logic        bit_tick,
    input  logic        sample_tick,
    input  logic        tx_tick,
    
    // Protocol FSM control
    output logic        arbitration_start,
    input  logic        arbitration_done,
    output logic        arbitration_lost,
    
    // Message data
    output logic [10:0] arbitration_id,
    output logic [3:0]  arbitration_dlc,
    output logic [63:0] arbitration_data,
    
    // Status
    input  logic        fsm_tx_active
);

    // Internal variables
    logic [10:0] current_id;
    logic [3:0]  current_dlc;
    logic [63:0] current_data;
    logic        arbitration_active;
    logic [3:0]  bit_position;
    logic [3:0]  arbitration_bit_count;
    logic        tx_bit, rx_bit;
    logic        lost_arbitration;
    logic        tx_success;
    logic [1:0]  ack_nack_counter;
    
    // CAN ID register (standard 11-bit)
    logic [10:0] tx_id_reg;
    logic [10:0] rx_id_shift;
    
    // Arbitration FSM
    typedef enum logic [2:0] {
        ARB_IDLE,
        ARB_WAIT_FIFO,
        ARB_READ_ID,
        ARB_TRANSMIT_ID,
        ARB_CHECK_ACK
    } arb_state_t;
    
    arb_state_t arb_state, arb_next_state;
    
    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_state <= ARB_IDLE;
            arbitration_bit_count <= 4'd0;
            tx_id_reg <= 11'd0;
        end else begin
            arb_state <= arb_next_state;
            if (arb_state == ARB_IDLE) begin
                arbitration_bit_count <= 4'd0;
            end else if (tx_tick && arb_state == ARB_TRANSMIT_ID && !lost_arbitration) begin
                arbitration_bit_count <= arbitration_bit_count + 4'd1;
            end
        end
    end
    
    // Next state logic
    always_comb begin
        arb_next_state = arb_state;
        case (arb_state)
            ARB_IDLE: begin
                if (!tx_fifo_empty && fsm_tx_active)
                    arb_next_state = ARB_READ_ID;
            end
            ARB_READ_ID: begin
                arb_next_state = ARB_TRANSMIT_ID;
            end
            ARB_TRANSMIT_ID: begin
                if (arbitration_bit_count >= 4'd11)
                    arb_next_state = ARB_CHECK_ACK;
            end
            ARB_CHECK_ACK: begin
                arb_next_state = ARB_IDLE;
            end
        endcase
    end
    
    // ID loading from FIFO
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_id_reg <= 11'd0;
        end else if (arb_state == ARB_READ_ID) begin
            tx_id_reg <= tx_id_reg;
        end
    end
    
    // Arbitration logic - CAN arbitration rules
    // During arbitration, dominant bit wins. If we transmit dominant but receive recessive, we win.
    // If we transmit recessive but receive dominant, we lost - must go to receive mode.
    
    assign tx_bit = tx_id_reg[10 - arbitration_bit_count];
    assign rx_bit = can_rx;
    assign lost_arbitration = (tx_tick && (tx_bit === 1'b1) && (rx_bit === 1'b0));
    
    // Outputs
    assign tx_fifo_rd_en = (arb_state == ARB_READ_ID);
    assign arbitration_id = tx_id_reg;
    assign arbitration_dlc = 4'd8;  // Default DLC
    assign arbitration_data = 64'd0;  // Will be loaded from FIFO
    assign arbitration_start = (arb_state == ARB_READ_ID);
    assign arbitration_lost = lost_arbitration;
    assign can_tx = (arb_state == ARB_TRANSMIT_ID) ? (lost_arbitration ? `CAN_RECESSIVE : tx_bit) : `CAN_RECESSIVE;

endmodule
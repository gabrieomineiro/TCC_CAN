//-----------------------------------------------------------------------------
// Módulo: can_bsp
// Descrição: Bit Stuffing Processor - manipula stuffing e transmissão de bits
//-----------------------------------------------------------------------------

module can_bsp #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 500_000
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // Configuração
    input  logic [7:0]  prescaler,
    input  logic [2:0]  prop_seg,
    input  logic [2:0]  phase_seg1,
    input  logic [2:0]  phase_seg2,
    input  logic [1:0]  sjw,
    
    // Clock signals (from BTU)
    input  logic        bit_tick,
    input  logic        sample_tick,
    input  logic        tx_tick,
    input  logic        sample_point,
    
    // CAN Bus
    input  logic        can_rx,
    output logic        can_tx,
    
    // FSM Interface
    input  logic        fsm_tx_active,
    input  logic        fsm_rx_active,
    input  logic        fsm_crc_en,
    input  logic [3:0]  fsm_tx_bit_count,
    input  logic [3:0]  fsm_rx_bit_count,
    input  logic [63:0] fsm_tx_data,
    input  logic [3:0]  fsm_dlc,
    
    // Error inputs
    input  logic        stuff_error_in,
    
    // Status outputs
    output logic        bsp_busy,
    output logic        stuff_error,
    output logic        bsp_error,
    output logic [2:0]  bsp_state
);

    // Estado do BSP
    typedef enum logic [2:0] {
        BSP_IDLE,
        BSP_TX_STUFFING,
        BSP_RX_STUFFING,
        BSP_TX_ACTIVE,
        BSP_RX_ACTIVE,
        BSP_ERROR
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal signals
    logic [63:0] tx_shift_reg;
    logic [63:0] rx_shift_reg;
    logic [3:0] tx_bit_pos;
    logic [3:0] rx_bit_pos;
    logic tx_bit_out;
    logic tx_stuff_bit;
    logic [2:0] consecutive_count;
    logic tx_stuff_needed;
    logic rx_stuff_needed;
    logic sample_bit;
    logic can_tx_out;
    
    // Bit stuffing encoder/decoder
    // CAN uses bit stuffing after 5 consecutive bits of same value
    // Stuff bit is opposite of the 5 consecutive bits
    
    // TX Stuffing logic
    always_comb begin
        tx_stuff_bit = ~tx_shift_reg[fsm_tx_bit_count[3:0]];
        tx_stuff_needed = (consecutive_count == 3'd5);
    end
    
    // RX Stuffing detection
    assign rx_stuff_needed = (consecutive_count == 3'd5);
    assign sample_bit = (fsm_rx_active) ? can_rx : 1'b1;
    
    // Main FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= BSP_IDLE;
            tx_shift_reg <= 64'h0;
            rx_shift_reg <= 64'h0;
            tx_bit_pos <= 4'd0;
            rx_bit_pos <= 4'd0;
            consecutive_count <= 3'd0;
        end else begin
            current_state <= next_state;
            
            case (current_state)
                BSP_IDLE: begin
                    tx_bit_pos <= 4'd0;
                    rx_bit_pos <= 4'd0;
                    consecutive_count <= 3'd0;
                end
                
                BSP_TX_STUFFING: begin
                    if (tx_tick && !tx_stuff_needed) begin
                        tx_shift_reg[tx_bit_pos] <= tx_bit_out;
                        tx_bit_pos <= tx_bit_pos + 4'd1;
                    end
                    // Track consecutive bits for stuffing
                    if (bit_tick) begin
                        consecutive_count <= 3'd0;
                    end else if (tx_tick) begin
                        if (tx_shift_reg[tx_bit_pos] == tx_shift_reg[tx_bit_pos-1]) begin
                            consecutive_count <= consecutive_count + 3'd1;
                        end else begin
                            consecutive_count <= 3'd1;
                        end
                    end
                end
                
                BSP_RX_STUFFING: begin
                    if (sample_tick && !rx_stuff_needed) begin
                        rx_shift_reg[rx_bit_pos] <= sample_bit;
                        rx_bit_pos <= rx_bit_pos + 4'd1;
                    end
                    // Track consecutive bits for stuffing check
                    if (bit_tick) begin
                        consecutive_count <= 3'd0;
                    end else if (sample_tick) begin
                        if (rx_shift_reg[rx_bit_pos] == sample_bit) begin
                            consecutive_count <= consecutive_count + 3'd1;
                        end else begin
                            consecutive_count <= 3'd1;
                        end
                    end
                end
                
                default: begin
                    consecutive_count <= 3'd0;
                end
            endcase
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            BSP_IDLE: begin
                if (fsm_tx_active) 
                    next_state = BSP_TX_STUFFING;
                else if (fsm_rx_active)
                    next_state = BSP_RX_STUFFING;
            end
            
            BSP_TX_STUFFING: begin
                if (!fsm_tx_active)
                    next_state = BSP_IDLE;
            end
            
            BSP_RX_STUFFING: begin
                if (!fsm_rx_active)
                    next_state = BSP_IDLE;
            end
        endcase
    end
    
    // TX output with bit stuffing
    assign can_tx_out = (tx_stuff_needed) ? tx_stuff_bit : fsm_tx_data[fsm_tx_bit_count[3:0]];
    assign can_tx = can_tx_out;
    
    // Stuff error detection
    assign stuff_error = (fsm_rx_active && rx_stuff_needed && (sample_tick && ~sample_bit !== (rx_shift_reg[rx_bit_pos-1] ? 1'b0 : 1'b1)));
    
    // Status outputs
    assign bsp_busy = (current_state != BSP_IDLE);
    assign bsp_error = stuff_error | stuff_error_in;
    assign bsp_state = current_state;

endmodule
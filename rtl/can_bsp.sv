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
    
    // Controle
    input  logic        tx_start,      // Inicia transmissão
    input  logic        tx_data,       // Dado a ser transmitido
    output logic        tx_ack,        // Confirma transmissão
    output logic        tx_eof,        // Fim da transmissão
    
    // Recepção
    input  logic        rx_data,       // Dado recebido
    output logic        rx_ack,        // Confirma recepção
    output logic        rx_eof,        // Fim da recepção
    
    // Status
    output logic        bsp_busy,      // BSP ocupado
    output logic        bsp_error,     // Erro de stuffing
    output logic [2:0]  bsp_state      // Estado interno
);

    // Internal variables
    logic [3:0] bit_count;
    logic [63:0] shift_reg;
    logic [7:0] stuffed_bits;
    logic [3:0] consecutive_bits;
    logic bit_stuff_enable;
    logic tx_active, rx_active;
    logic stuff_error_detected;
endmodule
module can_interrupt (
    input  logic        clk,
    input  logic        rst_n,
    
    // Fontes de interrupção
    input  logic        rx_available,   // Dado recebido disponível
    input  logic        tx_ready,       // Buffer de transmissão vazio
    input  logic        error_occurred, // Erro detectado
    input  logic        bus_off,        // Bus off condition
    input  logic        arbitration_lost,// Arbitragem perdida
    
    // Máscaras de interrupção
    input  logic [7:0]  interrupt_mask,
    
    // Controle
    input  logic        interrupt_clear,
    output logic [7:0]  interrupt_status,
    
    // Saída
    output logic        interrupt
);

    // Internal variables
    logic [7:0] pending_interrupts;
    logic [7:0] masked_interrupts;
    logic        any_interrupt;
endmodule
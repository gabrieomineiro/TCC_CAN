//-----------------------------------------------------------------------------
// Módulo: can_interrupt
// Descrição: Gerenciamento de interrupções do controlador CAN
//            Combina múltiplas fontes de interrupção com máscara
//-----------------------------------------------------------------------------

module can_interrupt (
    input  logic        clk,
    input  logic        rst_n,
    
    // Fontes de interrupção
    input  logic        rx_available,   // Dado recebido disponível
    input  logic        tx_ready,       // Buffer de transmissão vazio
    input  logic        error_occurred, // Erro detectado
    input  logic        bus_off,        // Bus off condition
    input  logic        arbitration_lost, // Arbitragem perdida
    
    // Máscaras de interrupção
    input  logic [7:0]  interrupt_mask,
    
    // Controle
    input  logic        interrupt_clear,
    
    // Saída
    output logic        interrupt
);

    // Interrupt source priority (bit position)
    // [0] - Error interrupt
    // [1] - Bus off interrupt
    // [2] - Arbitration lost interrupt
    // [3] - TX ready interrupt
    // [4] - RX available interrupt
    
    // Internal signals
    logic [7:0] pending_interrupts;
    logic [7:0] masked_interrupts;
    logic       any_interrupt;
    
    // Pending interrupt register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_interrupts <= 8'd0;
        end else if (interrupt_clear) begin
            pending_interrupts <= 8'd0;
        end else begin
            pending_interrupts[0] <= error_occurred | pending_interrupts[0];
            pending_interrupts[1] <= bus_off | pending_interrupts[1];
            pending_interrupts[2] <= arbitration_lost | pending_interrupts[2];
            pending_interrupts[3] <= tx_ready | pending_interrupts[3];
            pending_interrupts[4] <= rx_available | pending_interrupts[4];
            // Bits 5-7 reserved for extended interrupts
        end
    end
    
    // Mask and combine interrupts
    assign masked_interrupts = pending_interrupts & interrupt_mask;
    assign any_interrupt = |masked_interrupts;
    
    // Interrupt output (active high)
    assign interrupt = any_interrupt;

endmodule
//-----------------------------------------------------------------------------
// Módulo: can_acceptance_filter
// Descrição: Filtro de aceitação de mensagens CAN
//            Implementa filtragem baseada em máscara e código
//-----------------------------------------------------------------------------

module can_acceptance (
    input  logic        clk,
    input  logic        rst_n,
    
    // Configuração
    input  logic [10:0] filter_mask,
    input  logic [10:0] filter_code,
    input  logic        filter_enable,
    
    // ID recebido
    input  logic [10:0] can_id_in,
    input  logic        id_valid,
    
    // Resultado
    output logic        id_accepted,   // ID aceito pelo filtro
    output logic        id_rejected    // ID rejeitado
);

    // Internal signals
    logic [10:0] filtered_id;
    logic        match_result;
    
    // Acceptance filtering logic
    // ID is accepted if: (can_id_in & filter_mask) == filter_code
    // If mask bit is 0, that bit is "don't care" in comparison
    // If mask bit is 1, that bit must match filter_code
    
    assign filtered_id = can_id_in & filter_mask;
    assign match_result = (filtered_id == filter_code);
    
    // Output logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_accepted <= 1'b0;
            id_rejected <= 1'b0;
        end else begin
            if (id_valid) begin
                if (filter_enable) begin
                    id_accepted <= match_result;
                    id_rejected <= !match_result;
                end else begin
                    // Filter disabled: accept all messages
                    id_accepted <= 1'b1;
                    id_rejected <= 1'b0;
                end
            end else begin
                id_accepted <= 1'b0;
                id_rejected <= 1'b0;
            end
        end
    end

endmodule
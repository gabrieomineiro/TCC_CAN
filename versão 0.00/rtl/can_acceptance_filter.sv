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

    // Internal variables
    logic [10:0] filtered_id;
    logic        match_result;
endmodule
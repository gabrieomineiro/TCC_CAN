module can_crc (
    input  logic        clk,
    input  logic        rst_n,
    
    // Entrada de dados
    input  logic [63:0] data_in,       // Dados para cálculo do CRC
    input  logic [3:0]  dlc,           // Data length code
    input  logic        crc_en,        // Habilita cálculo
    input  logic        crc_clear,     // Limpa CRC
    
    // CRC para transmissão
    output logic [14:0] crc_out,       // CRC calculado
    
    // CRC para verificação
    input  logic [14:0] crc_received,  // CRC recebido
    output logic        crc_match,     // CRC verificado
    output logic        crc_error      // Erro de CRC
);

    // Internal variables
    logic [14:0] crc_reg;
    logic [14:0] crc_polynomial = 15'h4599;  // CRC-15: x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1
    logic [5:0]  bit_counter;
    logic [63:0] data_shift;
    logic        crc_calculating;
endmodule
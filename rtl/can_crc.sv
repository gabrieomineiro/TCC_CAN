//-----------------------------------------------------------------------------
// Módulo: can_crc
// Descrição: Cálculo e verificação de CRC-15 para CAN
//            Polinômio: x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1
//-----------------------------------------------------------------------------

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

    // CRC polynomial for CAN: 0x4599 (CRC-15)
    localparam logic [14:0] CRC_POLY = 15'h4599;
    
    // Internal registers
    logic [14:0] crc_reg;
    logic [5:0]  bit_counter;
    logic [63:0] data_shift;
    logic        crc_calculating;
    logic [14:0] crc_rx_reg;
    
    // CRC calculation for transmission
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg <= 15'h0;
            bit_counter <= 6'd0;
            data_shift <= 64'd0;
            crc_calculating <= 1'b0;
        end else begin
            if (crc_clear) begin
                crc_reg <= 15'h0;
                bit_counter <= 6'd0;
                crc_calculating <= 1'b0;
            end else if (crc_en) begin
                data_shift <= data_in;
                crc_reg <= 15'h0;
                bit_counter <= 6'd0;
                crc_calculating <= 1'b1;
            end else if (crc_calculating && bit_counter < {2'd0, dlc, 1'd0}) begin
                // Process one byte at a time
                if (bit_counter[2:0] == 3'd0) begin
                    // Load new byte
                    data_shift <= data_in;
                end
                // CRC shift and calculation
                if (crc_reg[14] ^ data_shift[7]) begin
                    crc_reg <= (crc_reg << 1) ^ CRC_POLY ^ data_shift[7];
                end else begin
                    crc_reg <= (crc_reg << 1) ^ data_shift[7];
                end
                data_shift <= {data_shift[6:0], 1'b0};
                bit_counter <= bit_counter + 6'd1;
            end else begin
                crc_calculating <= 1'b0;
            end
        end
    end
    
    // CRC for reception and verification
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_rx_reg <= 15'h0;
            crc_match <= 1'b1;
        end else begin
            if (crc_clear) begin
                crc_rx_reg <= 15'h0;
                crc_match <= 1'b1;
            end else if (crc_en) begin
                crc_rx_reg <= 15'h0;
            end else begin
                // Receive CRC bits
                crc_rx_reg <= {crc_rx_reg[13:0], crc_received[14]};
                // Check match at end of CRC reception
                if (bit_counter >= {2'd0, dlc, 1'd0} + 6'd15) begin
                    crc_match <= (crc_rx_reg == crc_reg);
                end
            end
        end
    end
    
    assign crc_out = crc_reg;
    assign crc_error = !crc_match;

endmodule
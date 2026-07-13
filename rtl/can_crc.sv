//-----------------------------------------------------------------------------
// can_crc
// CRC-15 bit-serial do CAN (polinômio 0x4599). Processa 1 bit por crc_shift.
// crc_clear zera o LFSR (início do frame). check_strobe compara rx_crc.
//-----------------------------------------------------------------------------
module can_crc (
    input  logic        clk,
    input  logic        rst_n,

    // cálculo (controlado pelo FSM)
    input  logic        crc_clear,    // zera o LFSR
    input  logic        crc_shift,    // strobe: inclui bit_in
    input  logic        bit_in,       // bit (destuffed) a incluir

    // resultado
    output logic [14:0] crc_out,

    // verificação (campo CRC, recepção)
    input  logic [14:0] rx_crc,       // CRC recebido do frame
    input  logic        check_strobe, // compara rx_crc com crc_out
    output logic        crc_match,    // 1 se rx_crc == crc_out (no strobe; sticky)
    output logic        crc_error     // 1 se rx_crc != crc_out (no strobe; sticky)
);

    localparam logic [14:0] POLY = 15'h4599;

    logic [14:0] crc_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)              crc_reg <= 15'h0;
        else if (crc_clear)      crc_reg <= 15'h0;
        else if (crc_shift)      crc_reg <= (crc_reg >> 1) ^ ((crc_reg[0] ^ bit_in) ? POLY : 15'h0);
    end

    assign crc_out = crc_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_match <= 1'b0;
            crc_error <= 1'b0;
        end else if (check_strobe) begin
            crc_match <= (rx_crc == crc_reg);
            crc_error <= (rx_crc != crc_reg);
        end
        // caso contrário: mantém (sticky) até o próximo strobe
    end

endmodule

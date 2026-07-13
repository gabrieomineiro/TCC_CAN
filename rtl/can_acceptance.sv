//-----------------------------------------------------------------------------
// can_acceptance
// 4 filtros de aceitação (código + máscara), 11/29-bit. Política RESTRITIVA:
// só aceita se algum filtro HABILITADO casar (OR). Avaliação combinacional,
// registrada em check_strobe.
// mask bit = 1 -> don't care; mask bit = 0 -> deve casar.
//-----------------------------------------------------------------------------
module can_acceptance #(
    parameter int NUM_FILTERS = 4
)(
    input  logic             clk,
    input  logic             rst_n,

    // mensagem recebida (do FSM)
    input  logic [28:0]      id,
    input  logic             ide,

    // configuração (do reg_file)
    input  logic [29:0]      filt_code [NUM_FILTERS],   // {ide[29], id[28:0]}
    input  logic [29:0]      filt_mask [NUM_FILTERS],
    input  logic [NUM_FILTERS-1:0] filt_en,

    // strobe de avaliação
    input  logic             check_strobe,
    output logic             accept,
    output logic             reject
);

    logic accept_comb;

    always_comb begin
        accept_comb = 1'b0;
        for (int i = 0; i < NUM_FILTERS; i++) begin
            // match de ID (bits onde mask=0 devem casar)
            // match de IDE (se mask[29]=1 -> don't care)
            if (filt_en[i] &&
                ((id & ~filt_mask[i][28:0]) == (filt_code[i][28:0] & ~filt_mask[i][28:0])) &&
                (filt_mask[i][29] || (filt_code[i][29] == ide)))
                accept_comb = 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accept <= 1'b0;
            reject <= 1'b0;
        end else if (check_strobe) begin
            accept <= accept_comb;
            reject <= ~accept_comb;
        end
        // senão: mantém
    end

endmodule

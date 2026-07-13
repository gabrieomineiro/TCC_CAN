//-----------------------------------------------------------------------------
// can_error  (Error Management Logic - EML)
// Mantém TEC e REC segundo ISO 11898-1 (versão de regras principais) e deriva
// os estados Error Active / Error Passive / Bus Off.
//
// Regras implementadas (simplificação documentada da ISO; ajuste fino guiado
// pela verificação UVM dirigida):
//   - erro como TRANSMISSOR (tx_context=1):  TEC += 8
//   - erro como RECEPTOR   (tx_context=0):   REC += 1
//   - frame TX bem-sucedido:                 TEC -= 1 (se 0 < TEC < 256)
//   - frame RX bem-sucedido:                 REC -= 1 (se REC > 0)
//   - Bus Off quando TEC >= 256; recuperação via err_reset (TEC=REC=0)
//   - arb_lost NÃO conta como erro (informativo).
// TEC interno 9 bits para detectar 256; REC 8 bits saturando em 0xFF.
//-----------------------------------------------------------------------------
module can_error (
    input  logic        clk,
    input  logic        rst_n,

    // eventos de erro (do FSM)
    input  logic        bit_error,
    input  logic        stuff_error,
    input  logic        crc_error,
    input  logic        ack_error,
    input  logic        form_error,

    // contexto (do FSM)
    input  logic        tx_context,      // 1 = erro em TX, 0 = em RX
    input  logic        arb_lost,        // não conta como erro (informativo)

    // sucesso
    input  logic        frame_tx_ok,
    input  logic        frame_rx_ok,

    // controle
    input  logic        err_reset,       // SFT_RST / início de recuperação Bus Off

    // contadores
    output logic [7:0]  tec,
    output logic [7:0]  rec,

    // estado
    output logic        error_active,
    output logic        error_passive,
    output logic        bus_off,

    // gatilho de Error Frame
    output logic        error_flag_req
);

    logic [8:0] tec_int;   // 9 bits: 0..256
    logic [7:0] rec_int;

    wire any_err = bit_error | stuff_error | crc_error | ack_error | form_error;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tec_int <= 9'd0;
            rec_int <= 8'd0;
        end else if (err_reset) begin
            tec_int <= 9'd0;
            rec_int <= 8'd0;
        end else begin
            // ---- TEC ----
            if (any_err && tx_context) begin
                tec_int <= (tec_int + 9'd8 > 9'd256) ? 9'd256 : (tec_int + 9'd8);
            end else if (frame_tx_ok && (tec_int > 9'd0) && (tec_int < 9'd256)) begin
                tec_int <= tec_int - 9'd1;
            end

            // ---- REC ----
            if (any_err && !tx_context) begin
                rec_int <= (rec_int == 8'hFF) ? 8'hFF : (rec_int + 8'd1);
            end else if (frame_rx_ok && (rec_int > 8'd0)) begin
                rec_int <= rec_int - 8'd1;
            end
        end
    end

    assign tec            = tec_int[7:0];
    assign rec            = rec_int;
    assign bus_off        = (tec_int >= 9'd256);
    assign error_passive  = (tec_int >= 9'd128) || (rec_int >= 8'd128);
    assign error_active   = !bus_off && !error_passive;
    assign error_flag_req = any_err;

    // arb_lost é intencionalmente não usado na contagem (ISO: não é erro).
    wire _unused = arb_lost;

endmodule

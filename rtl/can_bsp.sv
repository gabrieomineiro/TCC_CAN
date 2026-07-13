//-----------------------------------------------------------------------------
// can_bsp  (Bit Stream Processor)
// Serializa (TX) e desserializa (RX) o fluxo de bits no barramento CAN,
// aplicando/removendo bit-stuffing (NRZ) e drive/amostra da linha física.
// Único módulo que drive can_tx. Alimenta o CRC com bits destuffed/pre-stuff.
//
// Handshake de stuffing: o FSM avança por BIT DE PROTOCOLO, não por bit de
// barramento. Em TX, tx_bit_done pulsa quando um bit de protocolo foi
// consumido (1 a cada bit-time, exceto quando um stuff-bit é inserido). Em RX,
// rx_valid pulsa a cada bit destuffed (stuff-bits são descartados e não geram
// rx_valid). Assim o FSM desloca seus contadores/registradores nessas strobes.
// Contadores de stuffing correm contínuos; stuff_en só habilita descarte/erro.
//-----------------------------------------------------------------------------
module can_bsp (
    input  logic        clk,
    input  logic        rst_n,

    // cadenciamento (do BTU)
    input  logic        bit_tick,     // início do bit (TQ=0)
    input  logic        sample_tick,  // ponto de amostragem

    // TX (do FSM)
    input  logic        tx_bit,       // bit de protocolo a transmitir (pré-stuff)
    input  logic        tx_valid,     // tx_bit é válido neste bit-time
    input  logic        stuff_en,     // 1 = aplicar stuffing na região atual

    // bus físico
    input  logic        can_rx,       // linha recebida
    output logic        can_tx,       // linha transmitida
    output logic        can_tx_oe,    // output-enable (1 quando transmitindo)

    // RX (para FSM)
    output logic        rx_bit,       // bit recebido destuffed
    output logic        rx_valid,     // 1 pulso por bit destuffed (alinhado a sample_tick)

    // consumo TX (para FSM) — strobe por bit de protocolo consumido
    output logic        tx_bit_done,

    // CRC (alimentação — bits destuffed/pre-stuff)
    output logic        bit_to_crc,
    output logic        crc_bit_valid,

    // status
    output logic        stuff_error,  // 6 bits iguais em região stuffed
    output logic        bsp_busy
);

    localparam logic CAN_RECESSIVE = 1'b1;
    localparam logic CAN_DOMINANT  = 1'b0;

    // ---- estado de stuffing TX ----
    logic [3:0] tx_consec_r;   // run de bits idênticos na saída (0..15, sat)
    logic       tx_last_r;     // último bit de saída
    logic       tx_out_r;      // bit atualmente drivado (segurado p/ o bit-time)
    logic       oe_r;          // output enable registrado
    logic       tx_bit_done_r;

    // ---- estado de stuffing RX ----
    logic [3:0] rx_consec_r;   // run de bits idênticos recebidos (0..15, sat)
    logic       rx_last_r;
    logic       rx_bit_r;
    logic       rx_valid_r;
    logic       stuff_error_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_consec_r   <= 4'd0;
            tx_last_r     <= CAN_RECESSIVE;
            tx_out_r      <= CAN_RECESSIVE;
            oe_r          <= 1'b0;
            tx_bit_done_r <= 1'b0;
            rx_consec_r   <= 4'd0;
            rx_last_r     <= CAN_RECESSIVE;
            rx_bit_r      <= CAN_RECESSIVE;
            rx_valid_r    <= 1'b0;
            stuff_error_r <= 1'b0;
        end else begin
            // defaults (pulsos de 1 ciclo)
            tx_bit_done_r <= 1'b0;
            rx_valid_r    <= 1'b0;
            stuff_error_r <= 1'b0;

            // ============ TX (decide em bit_tick; segura por todo o bit-time) ===
            if (bit_tick) begin
                if (!tx_valid) begin
                    // ocioso: libera o bus e zera o contador de stuffing
                    tx_consec_r <= 4'd0;
                    tx_last_r   <= CAN_RECESSIVE;
                    oe_r        <= 1'b0;
                    tx_out_r    <= CAN_RECESSIVE;
                end else begin
                    oe_r <= 1'b1;
                    if (stuff_en && (tx_consec_r == 4'd5)) begin
                        // insere stuff-bit (oposto) sem consumir tx_bit
                        tx_out_r    <= ~tx_last_r;
                        tx_consec_r <= 4'd1;
                        tx_last_r   <= ~tx_last_r;
                    end else begin
                        // consome bit de protocolo
                        tx_out_r      <= tx_bit;
                        tx_bit_done_r <= 1'b1;
                        if (tx_bit != tx_last_r) begin
                            tx_consec_r <= 4'd1;
                            tx_last_r   <= tx_bit;
                        end else if (tx_consec_r < 4'd15) begin
                            tx_consec_r <= tx_consec_r + 4'd1;
                        end
                    end
                end
            end

            // ============ RX (destuffing em sample_tick) ========================
            if (sample_tick) begin
                if (stuff_en && (rx_consec_r == 4'd5)) begin
                    // bit esperado como stuff-bit
                    if (can_rx == rx_last_r) begin
                        // 6 idênticos consecutivos -> stuff error
                        stuff_error_r <= 1'b1;
                        rx_bit_r      <= can_rx;
                        rx_valid_r    <= 1'b1;
                        rx_consec_r   <= 4'd1;
                        rx_last_r     <= can_rx;
                    end else begin
                        // stuff-bit válido (oposto): descarta, não emite rx_valid
                        rx_consec_r <= 4'd1;
                        rx_last_r   <= can_rx;
                    end
                end else begin
                    // bit normal (ou região não-stuffed): repassa
                    rx_bit_r   <= can_rx;
                    rx_valid_r <= 1'b1;
                    if (can_rx != rx_last_r) begin
                        rx_consec_r <= 4'd1;
                        rx_last_r   <= can_rx;
                    end else if (rx_consec_r < 4'd15) begin
                        rx_consec_r <= rx_consec_r + 4'd1;
                    end
                end
            end
        end
    end

    // ---- saídas ----
    assign can_tx       = oe_r ? tx_out_r : CAN_RECESSIVE;
    assign can_tx_oe    = oe_r;
    assign rx_bit       = rx_bit_r;
    assign rx_valid     = rx_valid_r;
    assign tx_bit_done  = tx_bit_done_r;
    assign stuff_error  = stuff_error_r;
    assign bsp_busy     = oe_r;

    // CRC: em TX alimenta o bit de protocolo (pré-stuff); em RX o bit destuffed.
    // crc_bit_valid é a strobe de bit-de-protocolo (o FSM gera crc_shift no
    // janela SOF..DATA a partir dela).
    assign bit_to_crc   = tx_valid ? tx_bit  : rx_bit_r;
    assign crc_bit_valid = tx_valid ? tx_bit_done_r : rx_valid_r;

endmodule

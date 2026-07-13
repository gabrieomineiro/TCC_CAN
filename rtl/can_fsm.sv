//-----------------------------------------------------------------------------
// can_fsm  (Frame Sequencer) — SUBCONJUNTO (data frame padrão 11-bit)
// Orquestra TX/RX de frames CAN 2.0B padrão (base frame), controlando BSP,
// CRC, Arbitration, EML, FIFOs e Acceptance.
//
// Modelo de avanço por BIT DE PROTOCOLO: em TX o FSM avança em tx_bit_done
// (strobe do BSP, 1 por bit de protocolo consumido); em RX avança em rx_valid
// (1 por bit destuffed). O CRC é alimentado nessa cadência (crc_shift).
//
// FORA DO SUBCONJUNTO (TODO fase extensão): frames estendidos (29-bit,
// SRR/IDE/ID18), remote frames (RTR), overload frame, error-frame completo
// (passive/echo), bit-error detalhado.
//-----------------------------------------------------------------------------
module can_fsm (
    input  logic        clk,
    input  logic        rst_n,

    // enable/modo (reg_file)
    input  logic        can_en,
    output logic        fsm_busy,

    // BTU
    input  logic        bit_tick,
    input  logic        sample_tick,
    input  logic        tx_tick,
    input  logic        sync_locked,
    output logic        sync_en,
    output logic        hard_sync,

    // BSP
    output logic        bsp_tx_bit,
    output logic        bsp_tx_valid,
    output logic        stuff_en,
    input  logic        rx_bit,
    input  logic        rx_valid,
    input  logic        stuff_error,
    input  logic        tx_bit_done,     // strobe por bit de protocolo consumido (TX)

    // CRC
    output logic        crc_clear,
    output logic        crc_shift,
    input  logic [14:0] crc_out,
    input  logic        crc_match,
    input  logic        crc_error,
    output logic [14:0] rx_crc,
    output logic        check_strobe,

    // Arbitration
    output logic        arb_en,
    input  logic        arb_lost,
    input  logic [5:0]  arb_lost_bit,

    // Tx FIFO
    output logic        tx_pop,
    input  logic [98:0] tx_msg,
    input  logic        tx_empty,

    // Rx FIFO
    output logic        rx_push,
    output logic [98:0] rx_msg,
    input  logic        rx_full,

    // Acceptance
    output logic [28:0] flt_id,
    output logic        flt_ide,
    output logic        flt_check,
    input  logic        flt_accept,

    // EML
    output logic        e_bit_err,
    output logic        e_stuff_err,
    output logic        e_crc_err,
    output logic        e_ack_err,
    output logic        e_form_err,
    output logic        tx_context,
    output logic        frame_tx_ok,
    output logic        frame_rx_ok,
    input  logic        error_active,
    input  logic        error_passive,
    input  logic        bus_off,
    input  logic        error_flag_req,

    // Interrupt
    output logic        int_tx_done,
    output logic        int_rx_avail,
    output logic        int_arb_lost,
    output logic        int_stuff_err,
    output logic        int_crc_err,

    // status
    output logic [5:0]  fsm_state
);

    localparam logic CAN_DOMINANT  = 1'b0;
    localparam logic CAN_RECESSIVE = 1'b1;

    typedef enum logic [5:0] {
        IDLE           = 6'd0,
        TX_SOF         = 6'd1,  TX_ARB = 6'd2,  TX_CTRL = 6'd3,  TX_DATA = 6'd4,
        TX_CRCSEQ      = 6'd5,  TX_CRCDEL = 6'd6, TX_ACK = 6'd7, TX_ACKDEL = 6'd8,
        TX_EOF         = 6'd9,  TX_INTERMISSION = 6'd10,
        RX_SOF         = 6'd11, RX_ARB = 6'd12, RX_CTRL = 6'd13, RX_DATA = 6'd14,
        RX_CRCSEQ      = 6'd15, RX_CRCDEL = 6'd16, RX_ACK = 6'd17, RX_ACKDEL = 6'd18,
        RX_EOF         = 6'd19,
        ERROR_FLAG     = 6'd20, ERROR_DELIMITER = 6'd21
    } state_t;

    state_t state;

    // ---- contadores ----
    logic [6:0] bit_cnt;       // contador de bits do campo corrente
    logic [6:0] arb_rx_cnt;    // contador de bits recebidos do campo arb (p/ perda)
    logic [6:0] idle_cnt;       // recessivos consecutivos em IDLE

    // ---- TX datapath ----
    logic [11:0] arb_sr;        // {ID[10:0], RTR}, MSB first
    logic [5:0]  ctrl_sr;       // {IDE, r0, DLC[3:0]}, MSB first
    logic [63:0] data_sr;       // byte-swap (byte0 primeiro, MSB first)
    logic [14:0] crc_sr;        // sequência CRC a transmitir
    logic [3:0]  dlc_r;
    logic [6:0]  data_target;   // 8*dlc

    // ---- RX datapath ----
    logic [11:0] rx_arb_cap;
    logic [5:0]  rx_ctrl_cap;
    logic [63:0] rx_data_cap;
    logic [14:0] rx_crc_cap;
    logic [10:0] rx_id;         // = rx_arb_cap[11:1]
    logic        rx_rtr, rx_ide;
    logic [3:0]  rx_dlc;        // = rx_ctrl_cap[3:0]
    logic [6:0]  rx_data_target;
    logic        rx_err_seen;   // erro durante RX (stuff/form)
    logic        ack_seen;      // TX: ACK dominante foi amostrado

    // ---- strobes registrados (1 ciclo) ----
    logic crc_clear_r, hard_sync_r, check_strobe_r, tx_pop_r, rx_push_r, flt_check_r;
    logic e_bit_err_r, e_stuff_err_r, e_crc_err_r, e_ack_err_r, e_form_err_r;
    logic frame_tx_ok_r, frame_rx_ok_r;
    logic int_tx_done_r, int_rx_avail_r, int_arb_lost_r, int_crc_err_r;
    logic crc_shift_r;

    // janela de cálculo CRC: SOF é tratado por crc_clear (bit dominante não
    // altera LFSR zerado); shift nos campos ARB..DATA.
    logic in_crc_win, is_tx_win;
    assign in_crc_win = (state==TX_ARB)||(state==TX_CTRL)||(state==TX_DATA)||
                        (state==RX_ARB)||(state==RX_CTRL)||(state==RX_DATA);
    assign is_tx_win  = (state==TX_ARB)||(state==TX_CTRL)||(state==TX_DATA);

    // decisão de ACK na recepção (receptor envia ACK se recebeu sem erro)
    logic ack_send;
    assign ack_send = (state==RX_ACK) && crc_match && !rx_err_seen;

    // contexto TX/RX para o EML
    logic in_tx_context;
    assign in_tx_context = (state>=TX_SOF) && (state<=TX_INTERMISSION);

    // target de bytes do campo de dados
    wire [6:0] tx_data_target_w = {dlc_r, 3'b000};
    wire [6:0] rx_data_target_w = {rx_dlc, 3'b000};

    // --------------------------------------------------------------------
    // sempre combinacional: bsp_tx_bit / bsp_tx_valid por estado
    // --------------------------------------------------------------------
    always_comb begin
        bsp_tx_bit = CAN_RECESSIVE;
        case (state)
            TX_SOF, ERROR_FLAG:               bsp_tx_bit = CAN_DOMINANT;
            TX_ARB:                           bsp_tx_bit = arb_sr[11];
            TX_CTRL:                          bsp_tx_bit = ctrl_sr[5];
            TX_DATA:                          bsp_tx_bit = data_sr[63];
            TX_CRCSEQ:                        bsp_tx_bit = crc_sr[14];
            RX_ACK:                           bsp_tx_bit = ack_send ? CAN_DOMINANT : CAN_RECESSIVE;
            default:                          bsp_tx_bit = CAN_RECESSIVE;
        endcase
    end

    always_comb begin
        bsp_tx_valid = 1'b0;
        case (state)
            TX_SOF, TX_ARB, TX_CTRL, TX_DATA, TX_CRCSEQ, TX_CRCDEL,
            TX_ACKDEL, TX_EOF, TX_INTERMISSION, ERROR_FLAG, ERROR_DELIMITER:
                bsp_tx_valid = 1'b1;
            RX_ACK:     bsp_tx_valid = ack_send;       // drive ACK dominante só se aceitar
            default:    bsp_tx_valid = 1'b0;
        endcase
    end

    // sinais steady por estado
    always_comb begin
        stuff_en = (state==TX_SOF)||(state==TX_ARB)||(state==TX_CTRL)||
                   (state==TX_DATA)||(state==TX_CRCSEQ)||(state==RX_ARB)||
                   (state==RX_CTRL)||(state==RX_DATA)||(state==RX_CRCSEQ);
        arb_en      = (state==TX_ARB);
        sync_en     = can_en;
        fsm_busy    = (state!=IDLE);
        tx_context  = in_tx_context;
    end

    assign crc_shift = in_crc_win && (is_tx_win ? tx_bit_done : rx_valid);

    // montagem do descritor RX (válido no pulso de rx_push)
    wire [63:0] rx_data_desc =
        {rx_data_cap[7:0],  rx_data_cap[15:8],  rx_data_cap[23:16], rx_data_cap[31:24],
         rx_data_cap[39:32], rx_data_cap[47:40], rx_data_cap[55:48], rx_data_cap[63:56]};
    assign rx_msg = {rx_rtr, rx_ide, rx_id, 18'b0, rx_dlc, rx_data_desc};
    assign flt_id  = {rx_id, 18'b0};
    assign flt_ide = rx_ide;

    assign fsm_state = state;

    // --------------------------------------------------------------------
    // FSM principal
    // --------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            bit_cnt        <= 7'd0;
            arb_rx_cnt     <= 7'd0;
            idle_cnt       <= 7'd0;
            arb_sr         <= 12'b0;
            ctrl_sr        <= 6'b0;
            data_sr        <= 64'b0;
            crc_sr         <= 15'b0;
            dlc_r          <= 4'b0;
            rx_arb_cap     <= 12'b0;
            rx_ctrl_cap    <= 6'b0;
            rx_data_cap    <= 64'b0;
            rx_crc_cap     <= 15'b0;
            rx_id          <= 11'b0;
            rx_rtr         <= 1'b0;
            rx_ide         <= 1'b0;
            rx_dlc         <= 4'b0;
            rx_err_seen    <= 1'b0;
            ack_seen       <= 1'b0;
            crc_clear_r    <= 1'b0; hard_sync_r <= 1'b0; check_strobe_r <= 1'b0;
            tx_pop_r       <= 1'b0; rx_push_r <= 1'b0; flt_check_r <= 1'b0;
            e_bit_err_r    <= 1'b0; e_stuff_err_r <= 1'b0; e_crc_err_r <= 1'b0;
            e_ack_err_r    <= 1'b0; e_form_err_r <= 1'b0;
            frame_tx_ok_r  <= 1'b0; frame_rx_ok_r <= 1'b0;
            int_tx_done_r  <= 1'b0; int_rx_avail_r <= 1'b0; int_arb_lost_r <= 1'b0;
            int_crc_err_r  <= 1'b0;
            crc_shift_r    <= 1'b0;
        end else begin
            // defaults de strobes
            crc_clear_r <= 1'b0; hard_sync_r <= 1'b0; check_strobe_r <= 1'b0;
            tx_pop_r    <= 1'b0; rx_push_r <= 1'b0; flt_check_r <= 1'b0;
            e_bit_err_r <= 1'b0; e_stuff_err_r <= 1'b0; e_crc_err_r <= 1'b0;
            e_ack_err_r <= 1'b0; e_form_err_r <= 1'b0;
            frame_tx_ok_r <= 1'b0; frame_rx_ok_r <= 1'b0;
            int_tx_done_r <= 1'b0; int_rx_avail_r <= 1'b0; int_arb_lost_r <= 1'b0;
            int_crc_err_r <= 1'b0;
            crc_shift_r <= 1'b0;

            case (state)
                // ===================================================== IDLE
                IDLE: begin
                    if (!can_en || bus_off) begin
                        idle_cnt <= 7'd0;
                    end else if (rx_valid) begin
                        if (rx_bit == CAN_DOMINANT) begin
                            // SOF de outro nó -> recepção
                            idle_cnt    <= 7'd0;
                            crc_clear_r <= 1'b1;
                            hard_sync_r <= 1'b1;
                            rx_err_seen <= 1'b0;
                            state       <= RX_ARB;
                            bit_cnt     <= 7'd0;
                            arb_rx_cnt  <= 7'd0;
                        end else begin
                            // recessivo: conta idle; inicia TX se bus livre e há msg
                            if (idle_cnt < 7'd15) idle_cnt <= idle_cnt + 7'd1;
                            if ((idle_cnt >= 7'd11) && !tx_empty) begin
                                // inicia transmissão
                                crc_clear_r <= 1'b1;
                                hard_sync_r <= 1'b1;
                                // carrega shift regs a partir de tx_msg
                                arb_sr  <= {tx_msg[96:86], tx_msg[98]};      // {ID11, RTR}
                                ctrl_sr <= {1'b0, 1'b0, tx_msg[67:64]};      // {IDE,r0,DLC}
                                dlc_r   <= tx_msg[67:64];
                                data_sr <= {tx_msg[7:0],  tx_msg[15:8],  tx_msg[23:16], tx_msg[31:24],
                                            tx_msg[39:32], tx_msg[47:40], tx_msg[55:48], tx_msg[63:56]};
                                state   <= TX_SOF;
                                bit_cnt <= 7'd0;
                            end
                        end
                    end
                end

                // ===================================================== TX
                TX_SOF: begin
                    if (tx_bit_done) begin
                        state   <= TX_ARB;
                        bit_cnt <= 7'd0;
                    end
                end

                TX_ARB: begin
                    // captura recebida em paralelo (para eventual perda de arb)
                    if (rx_valid) begin
                        rx_arb_cap <= {rx_arb_cap[10:0], rx_bit};
                        arb_rx_cnt <= arb_rx_cnt + 7'd1;
                        if (arb_lost) begin
                            int_arb_lost_r <= 1'b1;
                            state          <= RX_ARB;   // vira receptor
                            bit_cnt        <= arb_rx_cnt + 7'd1; // prossegue contagem
                        end
                    end
                    // drive TX
                    if (tx_bit_done && !arb_lost) begin
                        arb_sr   <= {arb_sr[10:0], 1'b0};
                        bit_cnt  <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd11) begin
                            state   <= TX_CTRL;
                            bit_cnt <= 7'd0;
                        end
                    end
                end

                TX_CTRL: begin
                    if (tx_bit_done) begin
                        ctrl_sr <= {ctrl_sr[4:0], 1'b0};
                        bit_cnt <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd5) begin
                            if (tx_data_target_w == 7'd0) begin
                                state  <= TX_CRCSEQ;
                                crc_sr <= crc_out;   // DLC=0: congela CRC após controle
                            end else begin
                                state <= TX_DATA;
                            end
                            bit_cnt <= 7'd0;
                        end
                    end
                    if (stuff_error) begin
                        e_stuff_err_r <= 1'b1;
                        state         <= ERROR_FLAG;
                        bit_cnt       <= 7'd0;
                    end
                end

                TX_DATA: begin
                    if (tx_bit_done) begin
                        data_sr <= {data_sr[62:0], 1'b0};
                        bit_cnt <= bit_cnt + 7'd1;
                        if (bit_cnt == tx_data_target_w - 7'd1) begin
                            state   <= TX_CRCSEQ;
                            bit_cnt <= 7'd0;
                            crc_sr  <= crc_out;     // congela CRC no fim do data field
                        end
                    end
                    if (stuff_error) begin
                        e_stuff_err_r <= 1'b1;
                        state         <= ERROR_FLAG;
                        bit_cnt       <= 7'd0;
                    end
                end

                TX_CRCSEQ: begin
                    if (tx_bit_done) begin
                        crc_sr  <= {crc_sr[13:0], 1'b0};
                        bit_cnt <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd14) begin
                            state   <= TX_CRCDEL;
                            bit_cnt <= 7'd0;
                        end
                    end
                    if (stuff_error) begin
                        e_stuff_err_r <= 1'b1;
                        state         <= ERROR_FLAG;
                        bit_cnt       <= 7'd0;
                    end
                end

                TX_CRCDEL: begin
                    if (tx_bit_done) begin
                        state   <= TX_ACK;
                        bit_cnt <= 7'd0;
                        ack_seen <= 1'b0;
                    end
                end

                TX_ACK: begin
                    // transmissor escuta o ACK no ponto de amostragem
                    if (sample_tick) begin
                        ack_seen <= (rx_bit == CAN_DOMINANT);
                        if (rx_bit != CAN_DOMINANT) begin
                            e_ack_err_r <= 1'b1;
                            state       <= ERROR_FLAG;
                            bit_cnt     <= 7'd0;
                        end else begin
                            state   <= TX_ACKDEL;
                        end
                    end
                end

                TX_ACKDEL: begin
                    if (tx_bit_done) begin
                        state   <= TX_EOF;
                        bit_cnt <= 7'd0;
                    end
                end

                TX_EOF: begin
                    if (tx_bit_done) begin
                        bit_cnt <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd6) begin
                            state   <= TX_INTERMISSION;
                            bit_cnt <= 7'd0;
                        end
                    end
                end

                TX_INTERMISSION: begin
                    if (tx_bit_done) begin
                        bit_cnt <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd2) begin
                            // frame TX concluído com sucesso
                            frame_tx_ok_r <= 1'b1;
                            int_tx_done_r <= 1'b1;
                            tx_pop_r      <= 1'b1;        // confirma consumo do Tx FIFO
                            state         <= IDLE;
                            idle_cnt      <= 7'd0;
                            bit_cnt       <= 7'd0;
                        end
                    end
                end

                // ===================================================== RX
                RX_ARB: begin
                    if (rx_valid) begin
                        rx_arb_cap <= {rx_arb_cap[10:0], rx_bit};  // sempre captura
                        bit_cnt <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd11) begin
                            // 11 bits de ID em rx_arb_cap[10:0]; 12º bit (RTR) é rx_bit
                            rx_id   <= rx_arb_cap[10:0];
                            rx_rtr  <= rx_bit;
                            state   <= RX_CTRL;
                            bit_cnt <= 7'd0;
                        end
                    end
                    if (stuff_error) begin
                        e_stuff_err_r <= 1'b1;
                        rx_err_seen   <= 1'b1;
                    end
                end

                RX_CTRL: begin
                    if (rx_valid) begin
                        rx_ctrl_cap <= {rx_ctrl_cap[4:0], rx_bit};
                        bit_cnt     <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd5) begin
                            // 6º bit (DLC0) é rx_bit; IDE=bit0 já em rx_ctrl_cap[4]
                            rx_ide <= rx_ctrl_cap[4];
                            rx_dlc <= {rx_ctrl_cap[2:0], rx_bit};
                            state  <= ({rx_ctrl_cap[2:0], rx_bit} == 4'd0) ? RX_CRCSEQ : RX_DATA;
                            bit_cnt <= 7'd0;
                        end
                    end
                    if (stuff_error) begin
                        e_stuff_err_r <= 1'b1;
                        rx_err_seen   <= 1'b1;
                    end
                end

                RX_DATA: begin
                    if (rx_valid) begin
                        rx_data_cap <= {rx_data_cap[62:0], rx_bit};
                        bit_cnt     <= bit_cnt + 7'd1;
                        if (bit_cnt == rx_data_target_w - 7'd1) begin
                            state   <= RX_CRCSEQ;
                            bit_cnt <= 7'd0;
                        end
                    end
                    if (stuff_error) begin
                        e_stuff_err_r <= 1'b1;
                        rx_err_seen   <= 1'b1;
                    end
                end

                RX_CRCSEQ: begin
                    if (rx_valid) begin
                        rx_crc_cap <= {rx_crc_cap[13:0], rx_bit};
                        bit_cnt    <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd14) begin
                            // 15º bit (CRC LSB) é rx_bit
                            rx_crc         <= {rx_crc_cap[13:0], rx_bit};
                            check_strobe_r <= 1'b1;     // dispara comparação no CRC
                            state          <= RX_CRCDEL;
                            bit_cnt        <= 7'd0;
                        end
                    end
                    if (stuff_error) begin
                        e_stuff_err_r <= 1'b1;
                        rx_err_seen   <= 1'b1;
                    end
                end

                RX_CRCDEL: begin
                    if (rx_valid) begin
                        if (rx_bit != CAN_RECESSIVE) begin
                            e_form_err_r <= 1'b1;
                            rx_err_seen  <= 1'b1;
                        end
                        if (!crc_match) begin
                            e_crc_err_r   <= 1'b1;
                            int_crc_err_r <= 1'b1;
                            rx_err_seen   <= 1'b1;
                        end
                        state   <= RX_ACK;
                        bit_cnt <= 7'd0;
                    end
                end

                RX_ACK: begin
                    // receptor drive ACK dominante (ack_send); avança na amostragem
                    // (sample_tick ocorre mesmo se não estiver drivando)
                    if (sample_tick) begin
                        state <= RX_ACKDEL;
                    end
                end

                RX_ACKDEL: begin
                    if (rx_valid) begin
                        if (rx_bit != CAN_RECESSIVE) begin
                            e_form_err_r <= 1'b1;
                            rx_err_seen  <= 1'b1;
                        end
                        state   <= RX_EOF;
                        bit_cnt <= 7'd0;
                    end
                end

                RX_EOF: begin
                    if (rx_valid) begin
                        if (rx_bit != CAN_RECESSIVE) begin
                            e_form_err_r <= 1'b1;
                            rx_err_seen  <= 1'b1;
                        end
                        bit_cnt <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd6) begin
                            // fim do frame RX
                            if (!rx_err_seen) begin
                                frame_rx_ok_r <= 1'b1;
                                flt_check_r   <= 1'b1;   // pede avaliação do filtro
                                if (flt_accept && !rx_full) begin
                                    rx_push_r     <= 1'b1;
                                    int_rx_avail_r<= 1'b1;
                                end
                                state    <= IDLE;
                                idle_cnt <= 7'd0;
                            end else begin
                                // frame com erro -> sinaliza error frame
                                state   <= ERROR_FLAG;
                                bit_cnt <= 7'd0;
                            end
                            bit_cnt  <= 7'd0;
                        end
                    end
                end

                // ===================================================== Erro
                ERROR_FLAG: begin
                    // subconjunto: 6 bits dominantes (active). TODO: passive/echo.
                    if (tx_bit_done) begin
                        bit_cnt <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd5) begin
                            state   <= ERROR_DELIMITER;
                            bit_cnt <= 7'd0;
                        end
                    end
                end

                ERROR_DELIMITER: begin
                    if (tx_bit_done) begin
                        bit_cnt <= bit_cnt + 7'd1;
                        if (bit_cnt == 7'd7) begin
                            state    <= IDLE;
                            idle_cnt <= 7'd0;
                            bit_cnt  <= 7'd0;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // ---- saídas de strobes ----
    assign crc_clear    = crc_clear_r;
    assign hard_sync    = hard_sync_r;
    assign check_strobe = check_strobe_r;
    assign tx_pop       = tx_pop_r;
    assign rx_push      = rx_push_r;
    assign flt_check    = flt_check_r;
    assign e_bit_err    = e_bit_err_r;
    assign e_stuff_err  = e_stuff_err_r;
    assign e_crc_err    = e_crc_err_r;
    assign e_ack_err    = e_ack_err_r;
    assign e_form_err   = e_form_err_r;
    assign frame_tx_ok  = frame_tx_ok_r;
    assign frame_rx_ok  = frame_rx_ok_r;
    assign int_tx_done  = int_tx_done_r;
    assign int_rx_avail = int_rx_avail_r;
    assign int_arb_lost = int_arb_lost_r;
    assign int_stuff_err= stuff_error;   // pulso direto do BSP (detecção de stuff)
    assign int_crc_err  = int_crc_err_r;

    // _unused: sinais previstos para a fase de extensão
    wire _u1 = tx_tick; wire _u2 = sync_locked; wire _u3 = crc_error;
    wire _u4 = |arb_lost_bit; wire _u5 = error_flag_req; wire _u6 = error_passive;

endmodule

//-----------------------------------------------------------------------------
// Módulo: can_btu (Bit Timing Unit)
// Descrição: Gera sinais de temporização para sincronização de bits CAN
//            Implementa temporização de bit configurável conforme especificação CAN
//            Suporta sincronização forte (hard) e suave (soft) com detecção de borda
// Autor: Gabriel de Lima Pessoa
// Versão: 1.0
//-----------------------------------------------------------------------------

module can_btu_top #(
    parameter int CLK_FREQ_HZ = 50_000_000,  // Frequência do clock do sistema
    parameter int BAUD_RATE   = 500_000      // Taxa de transmissão CAN alvo
)(
    input  logic        clk,           // Clock do sistema
    input  logic        rst_n,         // Reset ativo baixo
    
    // Entradas de configuração
    input  logic [7:0]  prescaler,     // Prescaler da taxa de transmissão (1-256)
    input  logic [2:0]  prop_seg,      // Segmento de propagação (1-8 quantum de tempo)
    input  logic [2:0]  phase_seg1,    // Segmento de fase 1 (1-8 quantum de tempo)
    input  logic [2:0]  phase_seg2,    // Segmento de fase 2 (2-8 quantum de tempo)
    input  logic [1:0]  sjw,           // Largura do salto de sincronização (1-4 quantum de tempo)
    
    // Entrada do barramento CAN para detecção de borda
    input  logic        can_rx,        // Linha de recepção CAN
    
    // Entradas de sincronização
    input  logic        sync_en,       // Habilita sincronização
    input  logic        hard_sync,     // Requisição de sincronização forte (hard sync)
    
    // Saídas de temporização
    output logic        bit_tick,      // Pulso a cada tempo de bit
    output logic        sample_tick,   // Pulso no ponto de amostragem
    output logic        tx_tick,       // Pulso no ponto de transmissão
    output logic        sample_point,  // Alto durante a fase de amostragem
    
    // Saídas de status
    output logic [7:0]  bit_time_cnt,  // Contador atual do tempo de bit
    output logic        sync_locked,   // Sincronização estabelecida (locked)
    output logic        edge_detected, // Flag de borda detectada (para monitoramento)
    output logic        sync_active,    // Sincronização em andamento
    output logic [2:0]	fsm_state
);

    //-----------------------------------------------------------------------------
    // Sinais Internos
    //-----------------------------------------------------------------------------
    
    // Contador de quantum de tempo
    logic [7:0] tq_counter;           // Contador de TQ
    logic [4:0] tq_limit;              // Limite de TQ (agora com 5 bits para lidar com máx 22 TQ)
    
    // Valores de temporização calculados (5 bits para lidar com máx 22 TQ)
    logic [4:0] sample_tq_base;        // Contagem base de TQ para ponto de amostragem
    logic [4:0] sample_tq_adj;         // Ponto de amostragem ajustado para sincronização
    logic [4:0] tx_tq;                  // Contagem de TQ para ponto de TX
    logic [4:0] total_tq_base;          // Total base de TQ por bit
    logic [4:0] total_tq_adj;           // Total ajustado para sincronização
    
    // Contador do prescaler
    logic [7:0] presc_counter;          // Contador do prescaler
    logic [7:0] prescaler_safe;         // Valor protegido do prescaler
    logic       presc_tick;              // Pulso do prescaler (tick)
    
    // Estado da sincronização
    typedef enum logic [1:0] {
        SYNC_IDLE,                       // Sincronização ociosa
        SYNC_WAIT_EDGE,                   // Aguardando borda
        SYNC_ADJUSTING,                    // Ajustando
        SYNC_COMPLETE                       // Sincronização completa
    } sync_state_t;
    
    sync_state_t sync_state;              // Estado atual da sincronização
    
    // Registradores de ajuste de fase
    logic [3:0] phase_seg1_adj;            // phase_seg1 ajustado (4 bits para overflow)
    logic [3:0] phase_seg2_adj;            // phase_seg2 ajustado (4 bits para underflow)
    logic       sync_done;                  // Sincronização concluída
    logic       phase_adjusted;              // Flag indicando que a fase foi ajustada
    
    // Detecção de borda
    logic       prev_bus_value;              // Valor anterior do barramento
    logic       edge_detected_int;            // Sinal interno de detecção de borda
    logic [3:0] phase_error;                  // Magnitude do erro de fase
    
    //-----------------------------------------------------------------------------
    // Proteção das Entradas
    //-----------------------------------------------------------------------------
    
    // Protege contra prescaler zero
    assign prescaler_safe = (prescaler == 8'd0) ? 8'd1 : prescaler;
    
    //-----------------------------------------------------------------------------
    // Cálculo dos Parâmetros de Temporização
    //-----------------------------------------------------------------------------
    
    // Total de quantum de tempo por bit = 1 (sync) + prop_seg + phase_seg1 + phase_seg2
    // Nota: prop_seg, phase_seg1, phase_seg2 têm 3 bits mas representam valores 1-8
    // Máximo: 1 + 8 + 8 + 8 = 25 TQ (cabe em 5 bits)
    
    assign total_tq_base = 5'd1 + {2'b0, prop_seg} + {2'b0, phase_seg1} + {2'b0, phase_seg2};
    
    // Ponto de amostragem é após sync + prop_seg + phase_seg1
    assign sample_tq_base = 5'd1 + {2'b0, prop_seg} + {2'b0, phase_seg1};
    
    // Ponto de TX é no final do segmento de sincronização (início do bit)
    assign tx_tq = 5'd1;
    
    // Valores de temporização ajustados baseados na sincronização
    assign sample_tq_adj = 5'd1 + {2'b0, prop_seg} + phase_seg1_adj;
    assign total_tq_adj = 5'd1 + {2'b0, prop_seg} + phase_seg1_adj + phase_seg2_adj;
    
    // Limite do contador de TQ (usa valor ajustado quando sincronizando)
    assign tq_limit = phase_adjusted ? (total_tq_adj - 5'd1) : (total_tq_base - 5'd1);

    assign fsm_state = sync_state;
    
    //-----------------------------------------------------------------------------
    // Detecção de Borda
    //-----------------------------------------------------------------------------
    
    // Detecta borda de descida (recessivo para dominante) para sincronização
    // Barramento CAN usa estados dominante (0) e recessivo (1)
    // Uma borda de descida indica um ponto potencial de sincronização
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_bus_value    <= 1'b1;  // Padrão: recessivo
            edge_detected_int <= 1'b0;
        end else begin
            prev_bus_value    <= can_rx;
            // Detecta borda de descida (recessivo -> dominante)
            edge_detected_int <= prev_bus_value && !can_rx;
        end
    end
    
    // Saída do status de detecção de borda
    assign edge_detected = edge_detected_int;
    
    //-----------------------------------------------------------------------------
    // Prescaler
    //-----------------------------------------------------------------------------
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            presc_counter <= 8'd0;
            presc_tick    <= 1'b0;
        end else begin
            if (presc_counter >= prescaler_safe - 8'd1) begin
                presc_counter <= 8'd0;
                presc_tick    <= 1'b1;
            end else begin
                presc_counter <= presc_counter + 8'd1;
                presc_tick    <= 1'b0;
            end
        end
    end
    
    //-----------------------------------------------------------------------------
    // Contador de Quantum de Tempo
    //-----------------------------------------------------------------------------
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tq_counter <= 8'd0;
        end else if (presc_tick) begin
            if (hard_sync) begin
                // Sincronização forte: reinicia do início
                tq_counter <= 8'd0;
            end else if (tq_counter >= {3'b0, tq_limit}) begin
                tq_counter <= 8'd0;
            end else begin
                tq_counter <= tq_counter + 8'd1;
            end
        end
    end
    
    //-----------------------------------------------------------------------------
    // Máquina de Estados de Sincronização
    //-----------------------------------------------------------------------------
    
    // Calcula o erro de fase
    always_comb begin
        if (tq_counter < {3'b0, sample_tq_base}) begin
            phase_error = {1'b0, sample_tq_base[3:0]} - {1'b0, tq_counter[3:0]};
        end else begin
            phase_error = {1'b0, tq_counter[3:0]} - {1'b0, sample_tq_base[3:0]};
        end
    end
    
    // Máquina de estados de sincronização
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_state     <= SYNC_IDLE;
            phase_seg1_adj <= {1'b0, phase_seg1};
            phase_seg2_adj <= {1'b0, phase_seg2};
            sync_done      <= 1'b0;
            phase_adjusted <= 1'b0;
            sync_active    <= 1'b0;
        end else begin
            // Padrão: reinicia ajustes no início de um novo bit
            if (presc_tick && tq_counter == 8'd0 && !hard_sync) begin
                phase_seg1_adj <= {1'b0, phase_seg1};
                phase_seg2_adj <= {1'b0, phase_seg2};
                sync_done      <= 1'b0;
                phase_adjusted <= 1'b0;
                sync_active    <= 1'b0;
                sync_state     <= SYNC_IDLE;
            end else begin
                case (sync_state)
                    SYNC_IDLE: begin
                        if (hard_sync) begin
                            // Sincronização forte: reinicia ajustes de fase
                            phase_seg1_adj <= {1'b0, phase_seg1};
                            phase_seg2_adj <= {1'b0, phase_seg2};
                            sync_done      <= 1'b1;
                            sync_active    <= 1'b1;
                            sync_state     <= SYNC_COMPLETE;
                        end else if (sync_en && edge_detected_int && !sync_done) begin
                            sync_state  <= SYNC_WAIT_EDGE;
                            sync_active <= 1'b1;
                        end
                    end
                    
                    SYNC_WAIT_EDGE: begin
                        // Processa a borda e calcula o ajuste
                        if (tq_counter < {3'b0, sample_tq_base}) begin
                            // Erro de fase: borda antes do ponto de amostragem, alonga phase_seg1
                            // Limita o ajuste ao SJW
                            if (phase_error <= {2'b0, sjw}) begin
                                phase_seg1_adj <= {1'b0, phase_seg1} + phase_error[2:0];
                            end else begin
                                phase_seg1_adj <= {1'b0, phase_seg1} + {2'b0, sjw};
                            end
                            phase_seg2_adj <= {1'b0, phase_seg2};
                        end else begin
                            // Erro de fase: borda após o ponto de amostragem, encurta phase_seg2
                            // Limita o ajuste ao SJW
                            if (phase_error <= {2'b0, sjw}) begin
                                phase_seg2_adj <= {1'b0, phase_seg2} - phase_error[2:0];
                            end else begin
                                phase_seg2_adj <= {1'b0, phase_seg2} - {2'b0, sjw};
                            end
                            phase_seg1_adj <= {1'b0, phase_seg1};
                        end
                        phase_adjusted <= 1'b1;
                        sync_state     <= SYNC_ADJUSTING;
                    end
                    
                    SYNC_ADJUSTING: begin
                        // Aguarda a nova temporização ajustada entrar em vigor
                        sync_done  <= 1'b1;
                        sync_state <= SYNC_COMPLETE;
                    end
                    
                    SYNC_COMPLETE: begin
                        // Sincronização completa, aguarda próximo bit
                        sync_active <= 1'b0;
                        if (presc_tick && tq_counter == 8'd0) begin
                            sync_state <= SYNC_IDLE;
                        end
                    end
                    
                    default: begin
                        sync_state <= SYNC_IDLE;
                    end
                endcase
            end
        end
    end
    
    //-----------------------------------------------------------------------------
    // Geração das Saídas
    //-----------------------------------------------------------------------------
    
    // Bit tick: pulso no início de cada bit (TQ = 0)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_tick <= 1'b0;
        end else if (presc_tick && tq_counter == 8'd0) begin
            bit_tick <= 1'b1;
        end else begin
            bit_tick <= 1'b0;
        end
    end
    
    // Sample tick: pulso no ponto de amostragem
    // Usa o ponto de amostragem ajustado quando a sincronização está ativa
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_tick <= 1'b0;
        end else if (presc_tick) begin
            if (phase_adjusted) begin
                // Usa ponto de amostragem ajustado
                if (tq_counter == {3'b0, sample_tq_adj}) begin
                    sample_tick <= 1'b1;
                end else begin
                    sample_tick <= 1'b0;
                end
            end else begin
                // Usa ponto de amostragem base
                if (tq_counter == {3'b0, sample_tq_base}) begin
                    sample_tick <= 1'b1;
                end else begin
                    sample_tick <= 1'b0;
                end
            end
        end else begin
            sample_tick <= 1'b0;
        end
    end
    
    // TX tick: pulso no ponto de transmissão (segmento sync, TQ = 1)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_tick <= 1'b0;
        end else if (presc_tick && tq_counter == {3'b0, tx_tq}) begin
            tx_tick <= 1'b1;
        end else begin
            tx_tick <= 1'b0;
        end
    end
    
    // Sample point: alto durante a fase de amostragem (do ponto de amostragem ao final do bit)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_point <= 1'b0;
        end else if (presc_tick) begin
            if (phase_adjusted) begin
                sample_point <= (tq_counter >= {3'b0, sample_tq_adj});
            end else begin
                sample_point <= (tq_counter >= {3'b0, sample_tq_base});
            end
        end
    end
    
    // Saída do contador de tempo de bit
    assign bit_time_cnt = tq_counter;
    
    // Status de sincronização estabelecida (locked): indica que a temporização está estável
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_locked <= 1'b0;
        end else begin
            // Estabelecida (locked) quando completamos pelo menos um bit ou sincronização
            sync_locked <= sync_done || (tq_counter > 8'd0);
        end
    end

endmodule : can_btu_top

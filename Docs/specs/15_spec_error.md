# 15 — Spec: can_error (Error Management Logic — EML)

## 1. Função
Mantém o **Transmit Error Counter (TEC)** e o **Receive Error Counter (REC)** segundo ISO 11898-1, e deriva o estado do nó: **Error Active** (TEC<128 e REC<128), **Error Passive** (TEC≥128 ou REC≥128), **Bus Off** (TEC≥256). Dispara o Error Flag via FSM e gerencia a recuperação de Bus Off.

## 2. Interface
```systemverilog
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
    input  logic        tx_context,     // 1 = erro ocorreu em transmissão; 0 = recepção
    input  logic        arb_lost,       // perdeu arbitragem (não conta como erro)

    // sucesso (para decrementar REC)
    input  logic        frame_tx_ok,    // frame TX concluído com ACK
    input  logic        frame_rx_ok,    // frame RX concluído OK

    // controle
    input  logic        err_reset,      // CAN_MOD.SFT_RST ouEntrada em bus-off recovery

    // contadores
    output logic [7:0]  tec,
    output logic [7:0]  rec,

    // estado
    output logic        error_active,
    output logic        error_passive,
    output logic        bus_off,

    // gatilho de Error Frame
    output logic        error_flag_req  // pede ao FSM para emitir Error Flag
);
```

## 3. Contadores — interno
- `tec_int [8:0]` (9 bits para detectar 256 e saturar); saída `tec = tec_int[7:0]`.
- `rec_int [8:0]`; saída `rec = rec_int[7:0]`.

## 4. Regras ISO de incremento (resumo)
**TEC:**
- Bit error TX em Error Active/Passive: +8
- Perdeu ACK (TX): +8
- Demais erros em TX (stuff/form/crc que não o próprio): segundo ISO (em geral +8 se erro "próprio")
- TX bem-sucedida: −1 (TEC>0)
- Entrou em Bus Off: TEC=0 na recuperação

**REC:**
- Erro em RX (qualquer): +1 (Error Active); +8 se em Error Passive e erro de ACK? (ISO: REC+1 a cada erro, com regras especiais)
- RX bem-sucedida: −1 (REC>0) ou para 0xC0–0xFE: 11011111 após sucesso
- Satura em 127/128

> **Nota:** as regras exatas ISO 11898-1 § (error counters) devem ser codificadas fielmente. A spec definitiva referencia a tabela ISO; o UVM deve verificar com vetores dirigidos.

## 5. Estados derivados
```
bus_off       = (tec_int >= 9'd256)
error_passive = (tec_int >= 8'd128) || (rec_int >= 8'd128)
error_active  = !bus_off && !error_passive
```
- Transição para Bus Off: TEC alcança 256 → `bus_off=1`, FSM para de TX/RX, aguarda **128 ocorrências de 11 bits recessivos** (bus idle) antes de voltar a Error Active com TEC=REC=0.

## 6. Error Flag
`error_flag_req` sobe quando um erro é detectado e o nó está Error Active (Active Error Flag: 6 bits dominantes) ou Error Passive (Passive Error Flag: 6 bits recessivos seguidos de espera). O FSM emite o flag via BSP.

## 7. Conexões
- FSM → (eventos, contexto, frame_ok, err_reset); recebe (estados, error_flag_req).
- reg_file → `CAN_ERR` (TEC/REC), `CAN_STAT` (bus_off, err_passive).
- interrupt → `src_err_warn` (TEC/REC≥96), `src_err_passive`, `src_bus_off`.

## 8. Features para verificação (UVM)
| ID | Feature |
|---|---|
| EML-01 | TEC +8 em bit error TX |
| EML-02 | TEC +8 em ACK missing TX |
| EML-03 | TEC −1 após TX ok |
| EML-04 | REC incrementa em erro RX |
| EML-05 | REC −1/após RX ok |
| EML-06 | Error Active < 128 |
| EML-07 | Error Passive ≥ 128 |
| EML-08 | Bus Off ≥ 256 (TEC) |
| EML-09 | recuperação Bus Off após 128×11 recessivos |
| EML-10 | saturação dos contadores |
| EML-11 | error_flag_req em Error Active vs Passive |

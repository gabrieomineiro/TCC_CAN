# 13 — Spec: can_fsm (Frame Sequencer)

## 1. Função
Máquina de estados principal que orquestra a montagem/transmissão e a recepção/decodificação dos frames CAN 2.0B. Controla BSP, CRC, Arbitration, EML, FIFOs e Acceptance, gerando os campos na ordem correta e tratando arbitragem, ACK, erros e interframe.

> **Estado da implementação (Fase 3):** subconjunto funcional — apenas **data
> frame padrão 11-bit** (TX e RX completos), com CRC-15, arbitragem, ACK e
> Error Frame simplificado (active only). Fora do subconjunto (TODO fase de
> extensão): frames estendidos (29-bit), remote frames (RTR), overload frame,
> error-frame completo (passive/echo) e bit-error detalhado.
>
> **Modelo de avanço:** o FSM avança por **bit de protocolo** — em TX pelo
> strobe `tx_bit_done` (1 por bit consumido; absorve stuff-bits); em RX por
> `rx_valid` (1 por bit destuffed).

## 2. Interface (agrupada por parceiro)
```systemverilog
module can_fsm (
    input  logic        clk, rst_n,

    // ---- enable/modo (reg_file) ----
    input  logic        can_en,
    output logic        fsm_busy,

    // ---- BTU ----
    input  logic        bit_tick, sample_tick, tx_tick, sync_locked,
    output logic        sync_en, hard_sync,          // hard_sync no SOF

    // ---- BSP ----
    output logic        bsp_tx_bit, bsp_tx_valid, stuff_en,
    input  logic        rx_bit, rx_valid, stuff_error,
    input  logic        tx_bit_done,   // strobe por bit de protocolo consumido (TX)

    // ---- CRC ----
    output logic        crc_clear, crc_shift,
    input  logic [14:0] crc_out, input logic crc_match, crc_error,
    output logic [14:0] rx_crc, output logic check_strobe,
    // (bit_to_crc é encaminhado do BSP ao CRC no topo; FSM só gera crc_shift)

    // ---- Arbitration ----
    output logic        arb_en,
    input  logic        arb_lost, input logic [5:0] arb_lost_bit,

    // ---- Tx FIFO ----
    output logic        tx_pop,
    input  logic [98:0] tx_msg,
    input  logic        tx_empty,

    // ---- Rx FIFO ----
    output logic        rx_push,
    output logic [98:0] rx_msg,
    input  logic        rx_full,

    // ---- Acceptance ----
    output logic [28:0] flt_id, output logic flt_ide, output logic flt_check,
    input  logic        flt_accept,

    // ---- EML ----
    output logic        e_bit_err, e_stuff_err, e_crc_err, e_ack_err, e_form_err,
    output logic        tx_context, output logic frame_tx_ok, frame_rx_ok,
    input  logic        error_active, error_passive, bus_off, error_flag_req,

    // ---- Interrupt ----
    output logic        int_tx_done, int_rx_avail, int_arb_lost, int_stuff_err, int_crc_err,

    // ---- status ----
    output logic [5:0]  fsm_state
);
```

## 3. Estados (enum `logic [5:0]`)
```
IDLE
// TX
TX_SOF, TX_ARB, TX_CTRL, TX_DATA, TX_CRCSEQ, TX_CRCDEL, TX_ACK, TX_ACKDEL, TX_EOF, TX_INTERMISSION
// RX
RX_SOF, RX_ARB, RX_CTRL, RX_DATA, RX_CRCSEQ, RX_CRCDEL, RX_ACK, TXRX_ACKDEL, RX_EOF
// erros / interframe
ERROR_FLAG, ERROR_DELIMITER, OVERLOAD_FLAG, OVERLOAD_DELIMITER
```

## 4. Detecção de bus idle
Contador de bits recessivos consecutivos. Após **11 recessivos** → bus idle; se `can_en && !tx_empty`, inicia TX (TX_SOF). Em qualquer estado, um SOF (dominante após recessivo) detectado em IDLE → RX_SOF (e `hard_sync`).

## 5. Fluxo TX (resumo por estado)
- **TX_SOF:** emite bit dominante; `crc_clear`, `crc_shift` começa.
- **TX_ARB:** emite ID (+ RTR/IDE/SRR para ext); `arb_en=1`, `stuff_en=1`. Se `arb_lost` → vai a RX_ARB (vira receptor do vencedor).
- **TX_CTRL:** emite IDE/r0/DLC.
- **TX_DATA:** emite `dlc` bytes (0–8) da msg Tx.
- **TX_CRCSEQ:** emite `crc_out[14:0]` (stuff ainda ativo).
- **TX_CRCDEL:** 1 recessivo; `stuff_en=0`.
- **TX_ACK:** emite recessivo; amostra ACK: se dominante → ok; senão `e_ack_err`.
- **TX_ACKDEL:** 1 recessivo.
- **TX_EOF:** 7 recessivos (sem stuff). Se erro → ERROR.
- **TX_INTERMISSION:** 3 recessivos → IDLE. `frame_tx_ok`; `int_tx_done`; `tx_pop` confirma.

## 6. Fluxo RX (resumo por estado)
- **RX_SOF:** SOF detectado; `hard_sync`; `crc_clear`.
- **RX_ARB:** captura ID/IDE/RTR; (sem arb_en, só escuta).
- **RX_CTRL:** captura DLC.
- **RX_DATA:** captura bytes do payload.
- **RX_CRCSEQ:** captura CRC recebido → `rx_crc`; no fim, `check_strobe` → `crc_match`.
- **RX_CRCDEL:** 1 recessivo.
- **RX_ACK:** se `crc_match && !form_err` → drive ACK dominante (via BSP `bsp_tx_bit/valid`).
- **RX_EOF:** 7 recessivos; se ok → monta `rx_msg`, `flt_check` (acceptance), se `flt_accept && !rx_full` → `rx_push`; `int_rx_avail`; `frame_rx_ok`.

## 7. Tratamento de erros
- `stuff_error`, `crc_error`, `ack_error`, `form_error`, `bit_error` → `ERROR_FLAG` (6 bits dominantes em Active / recessivos em Passive), depois `ERROR_DELIMITER`, volta a IDLE (ou sobrecarga). Eventos vão ao EML com `tx_context`.
- Se `bus_off` (do EML) → fica em IDLE sem TX/RX até recuperação.

## 8. Sinais derivados pelo FSM
- `stuff_en`: 1 em SOF..TX_CRCSEQ / RX análogo; 0 a partir do CRC delimiter.
- `crc_clear`: em SOF.
- `crc_shift`: 1 bit por sample_tick durante SOF..DATA.
- `hard_sync`: strobe no SOF.

## 9. Conexões
Conecta-se a todos os módulos (ver interface). No topo, `bit_to_crc` (BSP→CRC) é encaminhado; o FSM só gera `crc_shift`.

## 10. Features para verificação (UVM)
| ID | Feature |
|---|---|
| FSM-01 | frame padrão TX completo com ACK |
| FSM-02 | frame estendido TX completo |
| FSM-03 | frame padrão RX aceito (push Rx FIFO) |
| FSM-04 | frame estendido RX |
| FSM-05 | perde arbitragem → vira receptor |
| FSM-06 | ACK missing → ack_error → EML |
| FSM-07 | CRC errado → rejeita, sem ACK |
| FSM-08 | stuff_error → Error Frame |
| FSM-09 | form_error (EOF/CRC del) |
| FSM-10 | bus idle → inicia TX |
| FSM-11 | remote frame (RTR) |
| FSM-12 | DLC 0 e DLC 8 |
| FSM-13 | transições de estado cobertas (FSM coverage) |
| FSM-14 | intermission e sobrecarga |

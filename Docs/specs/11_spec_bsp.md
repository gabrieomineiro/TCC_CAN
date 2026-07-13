# 11 — Spec: can_bsp (Bit Stream Processor)

## 1. Função
Serializa (TX) e desserializa (RX) o fluxo de bits no barramento CAN, aplicando/removendo **bit stuffing** (NRZ), e drive/amostra a linha física. É o **único** módulo que drive `can_tx`. Fornece ao CRC os bits **destuffed** e detecta erros de stuffing.

## 2. Escopo do bit stuffing (ISO)
- **Stuffing ativo** (stuff_en=1): SOF, Arbitration, Control, DATA e a própria **sequência de CRC**.
- **Stuffing inativo** (stuff_en=0): CRC delimiter, ACK slot, ACK delimiter, EOF, Intermission, Error/Overload frames.
- Regra: após 5 bits consecutivos de mesmo valor lógico, **insere 1 bit de valor oposto**.
- Erro de stuffing: 6 bits consecutivos iguais na região stuffed → `stuff_error`.

## 3. Interface
```systemverilog
module can_bsp (
    input  logic        clk,
    input  logic        rst_n,

    // cadenciamento (do BTU)
    input  logic        bit_tick,     // início de bit (TQ=0)
    input  logic        sample_tick,  // ponto de amostragem

    // TX (do FSM)
    input  logic        tx_bit,       // bit de protocolo a transmitir (pré-stuff)
    input  logic        tx_valid,     // tx_bit é válido neste bit-time
    input  logic        stuff_en,     // 1 = aplicar stuffing

    // bus físico
    input  logic        can_rx,       // linha recebida
    output logic        can_tx,       // linha transmitida
    output logic        can_tx_oe,    // output-enable (1 quando transmitindo)

    // RX (para FSM)
    output logic        rx_bit,       // bit recebido destuffed
    output logic        rx_valid,     // rx_bit atualizado em sample_tick

    // consumo TX (para FSM) — strobe de 1 ciclo por bit de protocolo consumido
    // (0 no bit-time em que um stuff-bit é inserido). O FSM avança por bit de
    // protocolo em TX (e por rx_valid em RX), absorvendo os stuff-bits aqui.
    output logic        tx_bit_done,

    // CRC (alimentação do cálculo — bits destuffed)
    output logic        bit_to_crc,   // bit destuffed (rx em RX; tx pré-stuff em TX)
    output logic        crc_bit_valid,

    // status
    output logic        stuff_error,  // 6 bits iguais na região stuffed
    output logic        bsp_busy
);
```

## 4. Comportamento

### TX
- No `bit_tick`, se `tx_valid`: pega `tx_bit`. Decide se insere stuff-bit: conta bits consecutivos de mesmo valor (na saída stuffed); ao atingir 5, o próximo bit de saída é o oposto (stuff) e a contagem reseta.
- Mantém `can_tx` no bit de saída por todo o bit-time; `can_tx_oe=1` durante TX.
- `tx_bit_done` pulsa em 1 a cada bit de protocolo consumido (permanece 0 no bit-time em que se insere um stuff-bit). É o "relógio de bit de protocolo" do FSM em TX.
- `bit_to_crc = tx_bit` (pré-stuff) e `crc_bit_valid` gating definido pelo FSM — o CRC consome o bit **destuffed/pre-stuff** na janela SOF..DATA.

### RX
- Em cada `sample_tick`: amostra `can_rx` → bit recebido (stuffed).
- Destuffing: se `stuff_en` e contador atingiu 5 e o próximo bit é o stuff esperado → descarta-o; senão repassa como `rx_bit`. Se aparecer 6º bit igual → `stuff_error`.
- `rx_bit`/`rx_valid` entregues ao FSM (pulso só em bit destuffed; stuff-bit descartado não gera `rx_valid`).
- `bit_to_crc = rx_bit` (destuffed) na janela SOF..DATA.

### Contadores de stuffing (decisão de implementação)
Os contadores de bits consecutivos (TX e RX) **correm contínuos** a cada
`bit_tick`/`sample_tick`; `stuff_en` apenas **habilita** a inserção/descarte e
a detecção de erro. Assim o SOF (dominante após recessivos do intermission)
reinicia naturalmente a corrida pela mudança de valor — sem necessidade de
reset explícito entre frames. O contador TX zera quando `tx_valid=0` (ocioso).

### Detecção de bit-error (opcional, pode ficar no FSM)
Comparar o bit transmitido com o amostrado (fora do campo de arbitragem e do ACK) → se divergir → bit error. (Decisão: tratar no FSM com dados do BSP.)

## 5. Conexões
- BTU → (`bit_tick`, `sample_tick`).
- FSM → (`tx_bit`, `tx_valid`, `stuff_en`); recebe (`rx_bit`, `rx_valid`, `stuff_error`).
- Pinos → (`can_rx`, `can_tx`, `can_tx_oe`).
- CRC ← (`bit_to_crc`, `crc_bit_valid`).

## 6. Modo (normal)
Sem loopback: `can_tx` sempre reflete o bit transmitido; `can_tx_oe=1` apenas durante a transmissão ativa do frame.

## 7. Features para verificação (UVM)
| ID | Feature |
|---|---|
| BSP-01 | stuffing: insere bit oposto após 5 iguais (vetores conhecidos) |
| BSP-02 | destuffing: remove stuff bits corretamente |
| BSP-03 | stuff_error ao detectar 6 iguais |
| BSP-04 | stuff_en=0 desliga stuffing (CRC del/ACK/EOF sem stuff) |
| BSP-05 | can_tx held por todo o bit-time |
| BSP-06 | rx_bit alinhado a sample_tick |
| BSP-07 | loopback interno de bit_to_crc confere com rx_bit/tx_bit |
| BSP-08 | OE timing (drive só durante TX) |

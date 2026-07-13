# 12 — Spec: can_crc (CRC-15 bit-serial)

## 1. Função
Calcula e verifica o CRC-15 do frame CAN (polinômio `0x4599`), processando **1 bit por `sample_tick`** durante os campos SOF..DATA. Ao final, compara o valor calculado com o CRC recebido.

## 2. Interface
```systemverilog
module can_crc (
    input  logic        clk,
    input  logic        rst_n,

    // cálculo (controlado pelo FSM, 1 bit por sample_tick)
    input  logic        crc_clear,    // zera o LFSR (início do frame; CRC CAN inicializa em 0)
    input  logic        crc_shift,    // strobe: inclui bit_in no LFSR
    input  logic        bit_in,       // bit (não-stuffed) a incluir

    // resultado
    output logic [14:0] crc_out,      // valor atual do LFSR

    // verificação (campo CRC, na recepção)
    input  logic [14:0] rx_crc,       // CRC recebido do frame
    input  logic        check_strobe, // compara rx_crc com crc_out
    output logic        crc_match,    // 1 se rx_crc == crc_out (no strobe)
    output logic        crc_error     // ~crc_match (no strobe)
);
```

## 3. Parâmetros
`localparam logic [14:0] CRC_POLY = 15'h4599;`

## 4. Comportamento
LFSR CRC-15 padrão CAN, inicializado em `15'h0000`:
```
crc_clear: crc_reg <= 0
crc_shift: crc_reg <= (crc_reg >> 1) ^ ((bit_in ^ crc_reg[0]) ? CRC_POLY : 0)
crc_out = crc_reg
check_strobe: crc_match <= (rx_crc == crc_reg); crc_error <= (rx_crc != crc_reg)
```
- O `bit_in` vem do `can_bsp` (bit não-stuffed) — o CRC é calculado sobre o stream **destuffed** (SOF até fim de DATA).
- `crc_shift` é gerado pelo FSM alinhado a `sample_tick`, apenas para bits dentro da janela SOF..DATA.
- Na TX, o FSM lê `crc_out` no fim de DATA e o serializa (com stuffing aplicado pelo BSP a partir dali? — não: o CRC field também é stuffed; o BSP aplica stuffing sobre os bits de CRC também até o CRC delimiter).

## 5. Conexões
- FSM → (`crc_clear`, `crc_shift`, `bit_in`, `rx_crc`, `check_strobe`)
- CRC → (`crc_out`, `crc_match`, `crc_error`) → FSM

## 6. Features para verificação (UVM)
| ID | Feature |
|---|---|
| CRC-01 | `crc_out` correto para sequências conhecidas (vetor de teste ISO) |
| CRC-02 | `crc_match=1` quando frame íntegro |
| CRC-03 | `crc_error=1` para CRC corrompido |
| CRC-04 | `crc_clear` zera o LFSR |
| CRC-05 | cálculo bit-a-bit alinhado a `crc_shift` |
| CRC-06 | polinômio 0x4599 |

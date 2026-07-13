# 17 — Spec: can_acceptance (4 filtros, 11/29-bit)

## 1. Função
Decide se uma mensagem recebida (ID + IDE) deve ser aceita (push no Rx FIFO). Implementa **4 filtros** independentes (código + máscara), cada um configurável para 11 e 29 bits. Mensagem aceita se **qualquer** filtro casar (OR).

## 2. Interface
```systemverilog
module can_acceptance #(
    parameter int NUM_FILTERS = 4
)(
    input  logic             clk,
    input  logic             rst_n,

    // mensagem recebida (do FSM, no fim do frame)
    input  logic [28:0]      id,
    input  logic             ide,

    // configuração (do reg_file)
    input  logic [29:0]      filt_code [NUM_FILTERS],  // {ide, id[28:0]}
    input  logic [29:0]      filt_mask [NUM_FILTERS],
    input  logic [NUM_FILTERS-1:0] filt_en,

    // strobe de avaliação
    input  logic             check_strobe,   // FSM: avalia id no fim do frame
    output logic             accept,         // 1 se algum filtro habilitado casa
    output logic             reject
);
```

## 3. Regra de casamento
Para cada filtro `i` habilitado:
```
masked_id   = id   & ~filt_mask[i][28:0]
masked_code = filt_code[i][28:0] & ~filt_mask[i][28:0]
id_match = (masked_id == masked_code)
ide_match = (filt_mask[i][29]) ? 1'b1 : (filt_code[i][29] == ide)   // se máscara IDE=1, IDE é don't-care
match_i = filt_en[i] && id_match && ide_match
accept = |match_i   (OR sobre os 4 filtros)
```
- bit de máscara em **1** = don't-care; bit em **0** = deve casar.
- Todos os filtros iniciam **desabilitados** em reset (`filt_en=0`), portanto nada é aceito até o software habilitar.

## 4. Comportamento
- Avaliação combinacional quando `check_strobe` (registrada em `accept` no ciclo seguinte para evitar glitch e dar tempo ao FSM).
- Filtros são avaliados em paralelo.

## 5. Conexões
- FSM → (`id`, `ide`, `check_strobe`).
- reg_file → (`filt_code`, `filt_mask`, `filt_en`):
  - `filt_code[]`/`filt_mask[]` vêm de `CAN_FILTn_CODE`/`CAN_FILTn_MASK` (bits [29:0]).
  - `filt_en[3:0]` vem do registrador **`CAN_FILT_EN[3:0]`** (offset 0x60).
- Saída `accept` → FSM decide push no Rx FIFO.

## 6. Política de aceitação (confirmada)
- **Restritiva:** em reset, `CAN_FILT_EN=0` → nenhum filtro habilitado → **nenhuma mensagem aceita**.
- Uma mensagem é aceita se **algum** filtro habilitado casar (OR dos filtros habilitados).
- Filtro desabilitado nunca aceita (não participa do OR).

## 7. Features para verificação (UVM)
| ID | Feature |
|---|---|
| FLT-01 | filtro com máscara 0 (casa só código exato) |
| FLT-02 | máscara all-1 (don't-care total → casa qualquer ID) |
| FLT-03 | OR: aceita se qualquer filtro casar |
| FLT-04 | filtro desabilitado não aceita |
| FLT-05 | distinção 11-bit vs 29-bit via IDE (máscara IDE) |
| FLT-06 | 4 filtros simultâneos, combinações |

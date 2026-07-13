# 14 — Spec: can_arbitration (comparador bitwise)

## 1. Função
Durante o campo de Arbitration, compara bit a bit o bit transmitido (`tx_bit`) com o bit amostrado no barramento (`rx_bit`). Detecta perda de arbitragem: se o nó transmitiu recessivo (1) e o barramento está dominante (0), o nó perdeu e deve passar a receptor. **Não drive o barramento** — isso é papel do BSP.

## 2. Interface
```systemverilog
module can_arbitration (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        sample_tick,   // 1 pulso por bit (do BTU/FSM)
    input  logic        arb_en,        // 1 durante o campo de Arbitration (do FSM)
    input  logic        tx_bit,        // bit que estamos transmitindo (do FSM)
    input  logic        rx_bit,        // bit amostrado no bus (do BSP)

    output logic        arb_lost,      // 1 = perdemos a arbitragem
    output logic        arb_active,    // 1 = ainda competindo
    output logic [5:0]  arb_lost_bit   // índice do bit em que perdemos
);
```

## 3. Comportamento
Avaliação **uma vez por bit**, em `sample_tick`, quando `arb_en`:
- Conta bits (incrementa em cada `sample_tick` com `arb_en && !lost`); zera quando `!arb_en`.
- Em `sample_tick && arb_en && !lost`: se `tx_bit==1 (recessivo) && rx_bit==0 (dominante)` → `arb_lost=1`, `arb_lost_bit=índice atual`.
- `arb_active = arb_en && !arb_lost`.
- Após perder, fica inativo até `arb_en` descer (reinicia para a próxima arbitragem).

## 4. Conexões
- FSM → (`arb_en`, `tx_bit`, `rx_bit`); `rx_bit` vem do BSP, `tx_bit` do FSM.
- Arb → (`arb_lost`, `arb_active`, `arb_lost_bit`) → FSM e EML.

## 5. Observação CAN 2.0B
A arbitragem cobre: frame padrão → 11 bits de ID + RTR + IDE(=0) + r0; frame estendido → 11 bits + SRR + IDE(=1) + 18 bits + RTR + r1 + r0. O `arb_en` permanece alto por toda essa extensão, definida pelo FSM conforme `ide`.

## 6. Features para verificação (UVM)
| ID | Feature |
|---|---|
| ARB-01 | ganha quando ID tem bits dominantes onde concorrente tem recessivos |
| ARB-02 | perde ao transmitir recessivo com bus dominante |
| ARB-03 | após perder, `arb_active=0` e não drive o bus |
| ARB-04 | `arb_en=0` mantém saídas em 0 |
| ARB-05 | empate (IDs iguais) — RTR desempata (data > remote) |
| ARB-06 | `arb_lost_bit` correto |

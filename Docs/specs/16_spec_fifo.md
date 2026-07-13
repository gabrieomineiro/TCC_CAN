# 16 — Spec: can_fifo_tx / can_fifo_rx (FIFO message-based)

## 1. Função
FIFOs síncronos de mensagens (descritor de `MSG_WIDTH=99` bits), profundidade configurável (default 8). Parametrizável e reutilizável para Tx e Rx.

## 2. Interface
```systemverilog
module can_fifo #(
    parameter int MSG_W  = 99,
    parameter int DEPTH  = 8
)(
    input  logic             clk,
    input  logic             rst_n,

    // porta de escrita
    input  logic             push,
    input  logic [MSG_W-1:0] wdata,
    output logic             full,

    // porta de leitura
    input  logic             pop,        // avança o ponteiro
    output logic [MSG_W-1:0] rdata,      // dado no topo (válido quando !empty)
    output logic             empty,
    output logic             rdata_valid, // pulso quando um dado novo está disponível no topo após pop

    // status
    output logic [clog2(DEPTH):0] count
);
```
Instanciar como `can_fifo_tx` e `can_fifo_rx` (mesmo módulo, renomeado por clareza, ou via parâmetro).

## 3. Parâmetros
| | Tx | Rx |
|---|---|---|
| `DEPTH` | 8 | 8 |
| `MSG_W` | 99 | 99 |

## 4. Comportamento
- Memória interna `mem[DEPTH][MSG_W]`, ponteiros `wr_ptr`/`rd_ptr` (`clog2(DEPTH)` bits), contador `count`.
- `push` quando `!full`: `mem[wr_ptr] <= wdata; wr_ptr++; count++;`
- `pop` quando `!empty`: `rd_ptr++; count--;` e `rdata_valid` pulsa no ciclo seguinte.
- `rdata = mem[rd_ptr]` (combinacional, sempre o topo).
- `full = (count == DEPTH)`; `empty = (count == 0)`.
- Reset: ponteiros e count em 0.
- `push`+`pop` simultâneos quando cheio: o `push` é descartado (overflow ignorado; para Rx, sinalizar overflow via flag separada opcional).

## 5. Conexões
- **Tx FIFO:** escrita pelo `can_reg_file` (em `TXREQ`); leitura pelo FSM (pop após ACK com sucesso).
- **Rx FIFO:** escrita pelo FSM (após EOF + aceito pelo filtro); leitura pelo `can_reg_file` (em `RELEASE`).
- `count` do Rx → `CAN_RCTRL.RX_CNT`; `empty`/`full` → `CAN_STAT`.

## 6. Features para verificação (UVM)
| ID | Feature |
|---|---|
| FIFO-01 | push/pop funcionam em ordem FIFO |
| FIFO-02 | `full`/`empty` corretos nos extremos |
| FIFO-03 | count correto após sequências |
| FIFO-04 | push em cheio não corrompe (overflow) |
| FIFO-05 | pop em vazio não avança |
| FIFO-06 | reset zera ponteiros/count |
| FIFO-07 | push e pop simultâneos (um ciclo) |
| FIFO-08 | profundidade máxima percorrida (encher até DEPTH, esvaziar) |

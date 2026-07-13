# 18 — Spec: can_interrupt (controlador de interrupções)

## 1. Função
Agrega 8 fontes de interrupção, aplica máscara, mantém flags "sticky" (write-1-to-clear) e gera `irq`.

## 2. Interface
```systemverilog
module can_interrupt (
    input  logic        clk,
    input  logic        rst_n,

    // fontes (level/pulse — treated as events, set the flag)
    input  logic        src_tx_done,       // TX concluída com ACK
    input  logic        src_rx_avail,      // Rx FIFO não-vazio (após push)
    input  logic        src_err_warn,      // TEC/REC >= 96
    input  logic        src_err_passive,   // entrou em Error Passive
    input  logic        src_bus_off,       // entrou em Bus Off
    input  logic        src_arb_lost,      // perdeu arbitragem
    input  logic        src_stuff_err,     // erro de stuffing
    input  logic        src_crc_err,       // erro de CRC

    input  logic [7:0]  ien,               // máscara de habilita (de CAN_IEN)
    input  logic [7:0]  iclear,            // write-1-to-clear (de escrita em CAN_IFG)

    output logic [7:0]  ifg,               // flags (espelha CAN_IFG)
    output logic        irq                // = |(ifg & ien)
);
```

## 3. Mapeamento de bits (consistente com `01_mapa_registradores`)
| Bit | Fonte |
|---|---|
| 0 | TX_DONE |
| 1 | RX_AVAIL |
| 2 | ERR_WARN |
| 3 | ERR_PASSIVE |
| 4 | BUS_OFF |
| 5 | ARB_LOST |
| 6 | STUFF_ERR |
| 7 | CRC_ERR |

## 4. Comportamento
```
always @(posedge clk or negedge rst_n):
  if !rst_n: ifg <= 0
  else:
    if (src_tx_done)      ifg[0] <= 1
    if (src_rx_avail)     ifg[1] <= 1
    ... (cada fonte seta seu bit)
    ifg <= ifg & ~iclear   // clear por escrita W1C em CAN_IFG
irq = |(ifg & ien)
```
- Flags são **sticky**: uma vez setadas, só caem com `iclear`.
- `irq` é combinacional sobre `ifg & ien`.

## 5. Conexões
- Fontes: FSM (tx_done, arb_lost, stuff_err, crc_err), Rx FIFO (rx_avail), EML (err_warn, err_passive, bus_off).
- `ien` do reg_file (`CAN_IEN`); `iclear` = bits escritos em `CAN_IFG`.
- Saídas `ifg` → reg_file (leitura `CAN_IFG`); `irq` → pino do topo.

## 6. Features para verificação (UVM)
| ID | Feature |
|---|---|
| INT-01 | fonte ativa seta flag correspondente |
| INT-02 | irq=1 só se flag setada E habilitada |
| INT-03 | máscara bloqueia irq mas não impede set do flag |
| INT-04 | clear W1C apaga apenas bits escritos |
| INT-05 | reset limpa todos os flags |
| INT-06 | flag sticky permanece até clear explícito |

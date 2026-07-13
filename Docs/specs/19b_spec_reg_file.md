# 19b — Spec: can_reg_file (Host Interface APB)

## 1. Função
Interface entre o barramento **APB** (host/CPU) e o controlador. Decodifica endereços, armazena os registradores, **monta** mensagens Tx (a partir dos registradores TX) e faz push no Tx FIFO em `TXREQ`, **desmonta** mensagens Rx (do topo do Rx FIFO) nos registradores RX (e pop em `RELEASE`), distribui a configuração (bit timing, filtros, máscaras) aos blocos e coleta status.

## 2. Interface
```systemverilog
module can_reg_file (
    input  logic        clk, rst_n,

    // ---- APB slave ----
    input  logic [31:0] paddr,
    input  logic        psel, penable, pwrite,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready, pslverr,

    // ---- config distribuída ----
    output logic [7:0]  btr_prescaler,
    output logic [2:0]  btr_prop, btr_seg1, btr_seg2,
    output logic [1:0]  btr_sjw,

    // ---- modo ----
    output logic        can_en, sft_rst,

    // ---- Tx (montagem) ----
    output logic        tx_push,
    output logic [98:0] tx_msg,
    input  logic        tx_full, tx_empty,

    // ---- Rx (desmontagem) ----
    output logic        rx_pop,
    input  logic [98:0] rx_msg,
    input  logic        rx_empty,
    input  logic [3:0]  rx_count,

    // ---- filtros ----
    output logic [29:0] filt_code [3:0],
    output logic [29:0] filt_mask [3:0],
    output logic [3:0]  filt_en,             // de CAN_FILT_EN[3:0]

    // ---- status/interrupt ----
    input  logic        stat_bus_off, stat_err_pass, stat_tx_busy,
    input  logic        stat_rx_avail, stat_tx_full,
    input  logic [7:0]  tec, rec,
    output logic [7:0]  ien,
    output logic [7:0]  ifg_clear,
    input  logic [7:0]  ifg_flags,
    output logic        irq
);
```

## 3. Decodificação APB
- Seleção por `paddr[7:2]` (registrador word). `paddr[1:0]` ignorado.
- Escrita: amostrada em `penable` (fase access). Registradores RW gravados; RO ignorados; W1T (`TXREQ`/`ABORT`/`RELEASE`) disparam ações de 1 pulso; W1C (`CAN_IFG`) gera `ifg_clear`.
- Leitura: `prdata` multiplexado por registrador. Registradores RX espelham o topo do Rx FIFO (sem pop).
- `pready=1` sempre (1 wait-state), exceto leitura RX enquanto Rx FIFO em atualização (opcional).
- `pslverr=1` em offset reservado; `prdata=0`.

## 4. Montagem TX (TXREQ)
Registradores shadow: `tid, tdlc, tda, tdb` (gravados pelo host). Em escrita com `TXREQ`:
```
tx_msg = { tid[30], tid[29], tid[28:0], tdlc[3:0], tdb, tda };  // {RTR,IDE,ID,DLC,DATA}
tx_push = 1 (1 pulso) se !tx_full
```
`TXREQ` sempre lê 0. Se `tx_full`, `tx_push` inibido (status `TX_FULL`).

## 5. Desmontagem RX
Registradores shadow `rid, rdlc, rda, rdb` carregados do `rx_msg` (topo do Rx FIFO) quando uma nova msg chega ao topo (após push do FSM ou após um pop). Em escrita com `RELEASE`:
```
rx_pop = 1 (1 pulso) se !rx_empty   // após o pop, os regs RX carregam a próxima msg
```
Leitura de `CAN_RID/RDLC/RDA/RDB` retorna os shadow regs (não causa pop).

## 6. Distribuição de config
- `CAN_BTR` → `btr_prescaler, btr_prop, btr_seg1, btr_seg2, btr_sjw` (campos conforme `01_mapa_registradores`).
- `CAN_FILTn_CODE/MASK` → `filt_code[]/filt_mask[]` (bits [29:0]).
- `CAN_FILT_EN[3:0]` → `filt_en[3:0]`.
- `CAN_MOD`: `CAN_EN`→`can_en`, `SFT_RST`→`sft_rst` (pulso, auto-limpa).

## 7. Status / Interrupt
- `CAN_STAT`/`CAN_ERR` montados dos sinais de status (`stat_*`, `tec`, `rec`).
- `CAN_IEN` armazenado → `ien`.
- `CAN_IFG`: escrita W1C → `ifg_clear = pwdata[7:0]` (pulso); leitura → `ifg_flags` (do `can_interrupt`).
- `irq = |(ifg_flags & ien)` (pode vir do `can_interrupt`).

## 8. Reset
`rst_n=0` ou `sft_rst` zera registradores de controle/status (MOD, TCTRL, IFG, IEN); mantém BTR/filtros? Decisão: `sft_rst` reinicia FSM/FIFOs/EML (via sinais) mas preserva config (BTR, filtros). `rst_n` zera tudo.

## 9. Conexões no topo
- APB ↔ (pinos). Config → BTU, filtros → acceptance. Tx/Rx FIFOs. Status ← EML/FSM/FIFOs. Interrupt ↔ can_interrupt.

## 10. Features para verificação (UVM)
| ID | Feature |
|---|---|
| REG-01 | leitura/escrita de cada registrador |
| REG-02 | TXREQ monta msg e faz push |
| REG-03 | RELEASE faz pop e carrega próxima msg |
| REG-04 | registradores RX espelham topo sem pop |
| REG-05 | W1C limpa flags corretas |
| REG-06 | RO ignora escrita |
| REG-07 | offset reservado → pslverr |
| REG-08 | distribuição BTR → BTU |
| REG-09 | distribuição filtros → acceptance |
| REG-10 | pready/pslverr conformidade APB |
| REG-11 | SFT_RST reinicia FSM/FIFOs mantendo config |

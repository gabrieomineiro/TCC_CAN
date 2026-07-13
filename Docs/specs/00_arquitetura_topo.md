# 00 — Arquitetura de Topo do Controlador CAN

| | |
|---|---|
| **Projeto** | TCC_CAN — Controlador CAN em SystemVerilog |
| **Autor** | Gabriel de Lima Pessoa |
| **Padrão** | CAN 2.0B (ISO 11898-1:2003) |
| **Modos** | Apenas modo normal (TX/RX no barramento) |
| **Interface de host** | APB (AMBA Peripheral Bus), 32 bits |
| **Documento** | Fundacional — os demais specs dependem deste |

---

## 1. Visão geral

Controlador CAN 2.0B que suporta frames padrão (ID 11 bits) e estendidos (ID 29 bits), com payload de 0–8 bytes, acessível por um barramento APB como um conjunto de registradores mapeados em memória. O controlador implementa temporização de bit, serialização/destuffing, arbitragem bitwise, CRC-15, tratamento de erros (TEC/REC) com estados Error Active / Error Passive / Bus Off, filtragem de aceitação e FIFOs de Tx e Rx.

O bloco **Bit Timing Unit (BTU)** já existe e está validado; os demais blocos são especificados nesta família de documentos e depois integrados no topo.

## 2. Diagrama de blocos

```
                      +---------------------------------------------------+
APB ------------------------------------------------> | can_reg_file      |
  paddr/psel/penable/pwrite/pwdata/prdata/            | (decode APB,      |
  pready/pslverr                                       |  monta/desmonta   |
                       +------------------------------+ |  mensagem,        |
                       | config: prescaler,segs,sjw   | |  distribui config |
                       v                              | |  coleta status)  |
                 +-----------+   bit_tick,sample_tick,+-------------------+
                 |  can_btu  |----tx_tick,sample_point-----------------+
                 +-----------+                                           |
                       |                                                 |
                       v                                                 v
                 +-----------+   tx_bit,tx_valid,stuff_en    +-----------+
                 | can_fsm   |<------------------------------| can_bsp   |<---> can_tx/can_rx
  pop Tx FIFO -->| (Frame    |----> crc_en,crc_clear,bit_in  | (serial/  |
                 |  Sequencer|<---- crc_out,crc_match        |  stuffing|
                 |           |<---- stuff_error,rx_bit       |  /destuf)|
                 |           |<---- arb_lost                 +-----------+
                 |           |                                    |
                 |           |   tx_bit,rx_bit,arb_en             |
                 |           +---> can_arbitration (compara)       |
                 |           |<---- arb_lost_bit                   |
                 |           |                                      v
                 |           |----> push Rx FIFO  <--- can_acceptance (4 filtros)
                 |           |                                      ^
                 |           |----> error events  --> can_error (TEC/REC) --> bus_off,err_passive
                 |           |----> int sources   --> can_interrupt --------> irq
                 +-----------+
                       |  ^
                  Tx FIFO | | Rx FIFO  (message-based, profundidade 8)
                       v  |
                   (pop p/ TX)        (push na recepção aceita)
```

## 3. Parâmetros do controlador

| Parâmetro | Valor | Observação |
|---|---|---|
| `CLK_FREQ_HZ` | 50 000 000 | Clock do sistema |
| `BAUD_RATE` (default) | 500 000 | Configurável via `CAN_BTR` (125k/250k/500k/1M típicos) |
| `FIFO_TX_DEPTH` | 8 | Mensagens |
| `FIFO_RX_DEPTH` | 8 | Mensagens |
| `NUM_FILTERS` | 4 | Filtros de aceitação |
| `ID_WIDTH` | 29 | Suporta 11 e 29 bits |
| `DATA_WIDTH` | 64 | 8 bytes |
| `MSG_WIDTH` | 99 | Largura do descritor de mensagem (ver `02_formato_mensagem`) |
| Modos | Normal | (sem loopback/listen-only) |

## 4. Fluxo de dados — Transmissão (TX)

1. CPU escreve `CAN_TID` (ID+IDE+RTR), `CAN_TDLC`, `CAN_TDA`, `CAN_TDB` via APB.
2. CPU aciona `CAN_TCTRL.TXREQ`.
3. `can_reg_file` monta o descritor de mensagem (99 bits) e faz **push** no **Tx FIFO**.
4. Quando o barramento está ocioso (≥11 bits recessivos) e não há erro dominante, `can_fsm` inicia a transmissão:
   - Faz **pop** do Tx FIFO, monta o frame: SOF → Arbitration → Control → DATA → CRC → ACK → EOF → Intermission.
   - Para cada bit de protocolo, fornece `tx_bit` ao `can_bsp`, que aplica **bit stuffing** (NRZ, 5 iguais → insere oposto) entre SOF e fim de DATA, e drive `can_tx`.
   - `can_crc` calcula CRC-15 **bit a bit** sobre os bits *não-stuffed* (SOF..DATA), habilitado pelo FSM.
5. Durante o campo de Arbitration, `can_arbitration` compara `tx_bit` (recessivo) com `rx_bit` (dominante): se divergir, `arb_lost=1` e o FSM passa a receptor imediatamente (retenta após Intermission).
6. No campo ACK, se um outro nó responder dominante → sucesso; senão → `ack_error`.
7. Sucesso: `tx_done` → `can_interrupt` sinaliza TX_DONE; o slot do Tx FIFO é confirmado.
8. Erro: `can_error` incrementa TEC segundo as regras ISO; em erro ativo, envia Error Flag.

## 5. Fluxo de dados — Recepção (RX)

1. `can_bsp` amostra `can_rx` em cada `sample_tick` (ponto de amostragem do BTU), aplica **destuffing** e entrega `rx_bit` ao `can_fsm`.
2. `can_fsm` sincroniza no SOF (hard sync via BTU), decodifica Arbitration/Control/DATA, acumula CRC.
3. No campo CRC, compara o calculado com o recebido → `crc_match`/`crc_error`.
4. No ACK, o FSM drive o bit dominante (se a mensagem foi recebida corretamente).
5. Após EOF, se aceito: o ID vai a `can_acceptance` (4 filtros); se algum filtro casar → **push** do descritor no **Rx FIFO**.
6. CPU é notificada (interrupção RX_AVAILABLE); lê `CAN_RID/RDLC/RDA/RDB` e aciona `CAN_RCTRL.RELEASE` para liberar o slot.
7. Erros (stuff/CRC/form/ACK) → `can_error` incrementa REC.

## 6. Formato de frame CAN 2.0B (resumo)

**Frame padrão (11-bit):**
```
SOF(1) | ID11(11) | RTR(1) | IDE(=0)(1) | r0(1) | DLC(4) | DATA(0..64) | CRC(15) | CRCdel(1) | ACK(1) | ACKdel(1) | EOF(7) | Intermission(3)
```
**Frame estendido (29-bit):**
```
SOF(1) | ID11(11) | SRR(=1)(1) | IDE(=1)(1) | ID18(18) | RTR(1) | r1(1) | r0(1) | DLC(4) | DATA(0..64) | CRC(15) | CRCdel(1) | ACK(1) | ACKdel(1) | EOF(7) | Intermission(3)
```
- Bit stuffing ativo entre SOF e fim do DATA (inclusive). Inativo em CRC delimiter, ACK, EOF, Intermission.
- CRC-15, polinômio `0x4599`, calculado sobre os bits *não-stuffed* (SOF..DATA).

## 7. Estratégia de clock e reset

- **Clock único:** todos os blocos operam no `clk` do sistema (50 MHz). O BTU deriva os ticks (TQ/sample/tx) por prescaler. Não há domínio de clock separado; `can_rx` é amostrado de forma síncrona no BTU.
- **Reset assíncrono, liberação síncrona:** `rst_n` ativo-baixo, assíncrono na declaração dos flip-flops (`always_ff @(posedge clk or negedge rst_n)`). Há também `CAN_MOD.SFT_RST` (reset por software, síncrono).

## 8. Lista de módulos e responsabilidades

| Módulo | Função | Spec |
|---|---|---|
| `can_btu` | Bit Timing Unit — prescaler, TQ, sample point, hard/soft sync | `19_spec_btu` (já existe/consolidado) |
| `can_bsp` | Bit Stream Processor — serializa/destuffing, drive/amostra do bus | `11_spec_bsp` |
| `can_crc` | CRC-15 bit-serial (poly 0x4599) | `12_spec_crc` |
| `can_fsm` | Frame Sequencer — FSM TX/RX, orquestra campos do frame | `13_spec_fsm` |
| `can_arbitration` | Comparador bitwise (campo de arbitragem) | `14_spec_arbitration` |
| `can_error` | Error Management Logic — TEC/REC, estados | `15_spec_error` |
| `can_fifo_tx`/`can_fifo_rx` | FIFOs message-based (profundidade 8) | `16_spec_fifo` |
| `can_acceptance` | 4 filtros de aceitação, 11/29-bit | `17_spec_acceptance` |
| `can_interrupt` | Controlador de interrupções | `18_spec_interrupt` |
| `can_reg_file` | Host interface APB — decode regs, monta/desmonta msg | `19_spec_reg_file` |
| `can_top` | Integração (module `can_top`) | (descrito neste doc) |

## 9. Hierarquia de instância no topo

```
can_top
├── can_reg_file         u_reg_file     (rst_n = rst_n; preserva config)
├── can_btu              u_btu          ┐
├── can_bsp              u_bsp          │
├── can_crc              u_crc          │
├── can_fsm              u_fsm          │ rst_n = rst_core_n
├── can_arbitration      u_arb          │ = rst_n & ~sft_rst  (reset parcial)
├── can_error            u_err          │
├── can_fifo #(.MSG_W(99),.DEPTH(8)) u_tx_fifo │
├── can_fifo #(.MSG_W(99),.DEPTH(8)) u_rx_fifo │
├── can_acceptance #(.NUM_FILTERS(4))  u_filter│
└── can_interrupt        u_int          ┘
```
`bit_to_crc` (BSP→CRC) é encaminhado no topo; o FSM gera `crc_shift`.

## 10. Referências

- ISO 11898-1:2003 — Controller area network (CAN), data link layer and physical signalling.
- CAN 2.0B specification (Robert Bosch GmbH, 1991).
- Especificação técnica do BTU (`gabriel_pessoa_spec_Entrega1.pdf`).

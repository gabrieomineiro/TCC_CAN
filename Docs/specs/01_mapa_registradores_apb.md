# 01 — Mapa de Registradores APB

Barramento de dados **APB 32 bits**. Endereçamento por palavra (word-aligned),little-endian. Reset de todos os registradores em `rst_n=0` (e em `CAN_MOD.SFT_RST`).

| Sinal APB | Direção | Descrição |
|---|---|---|
| `paddr[31:0]` | I | Endereço (usa `paddr[7:2]` para selecionar o registrador; `paddr[1:0]`=0) |
| `psel` | I | Seleção |
| `penable` | I | Habilita (2ª fase do handshake APB) |
| `pwrite` | I | 1=escrita, 0=leitura |
| `pwdata[31:0]` | I | Dados de escrita |
| `prdata[31:0]` | O | Dados de leitura |
| `pready` | O | Pronto (sempre 1, acesso de 1 ciclo; 0 apenas se Rx FIFO sendo atualizado) |
| `pslverr` | O | Erro de slave (acesso a endereço reservado) |

## 1. Tabela de registradores

| Offset | Nome | Acesso | Reset | Descrição |
|---|---|---|---|---|
| 0x00 | `CAN_MOD` | RW | 0x00 | Modo de operação |
| 0x04 | `CAN_BTR` | RW | ver §3 | Bit timing |
| 0x08 | `CAN_TCTRL` | RW | 0x00 | Controle de transmissão |
| 0x0C | `CAN_TID` | RW | 0x00 | TX ID + IDE + RTR |
| 0x10 | `CAN_TDLC` | RW | 0x00 | TX DLC |
| 0x14 | `CAN_TDA` | RW | 0x00 | TX data bytes 0–3 |
| 0x18 | `CAN_TDB` | RW | 0x00 | TX data bytes 4–7 |
| 0x1C | `CAN_RCTRL` | RW/RO | 0x00 | RX controle (RELEASE) + contagem |
| 0x20 | `CAN_RID` | RO | 0x00 | RX ID + IDE + RTR |
| 0x24 | `CAN_RDLC` | RO | 0x00 | RX DLC |
| 0x28 | `CAN_RDA` | RO | 0x00 | RX data bytes 0–3 |
| 0x2C | `CAN_RDB` | RO | 0x00 | RX data bytes 4–7 |
| 0x30 | `CAN_STAT` | RO | 0x00 | Status |
| 0x34 | `CAN_ERR` | RO | 0x00 | Contadores de erro |
| 0x38 | `CAN_IEN` | RW | 0x00 | Interrupção — habilita |
| 0x3C | `CAN_IFG` | RC | 0x00 | Interrupção — flags (W1C) |
| 0x40 | `CAN_FILT0_CODE` | RW | 0x00000000 | Filtro 0 — código |
| 0x44 | `CAN_FILT0_MASK` | RW | 0x00000000 | Filtro 0 — máscara |
| 0x48 | `CAN_FILT1_CODE` | RW | 0x00000000 | Filtro 1 — código |
| 0x4C | `CAN_FILT1_MASK` | RW | 0x00000000 | Filtro 1 — máscara |
| 0x50 | `CAN_FILT2_CODE` | RW | 0x00000000 | Filtro 2 — código |
| 0x54 | `CAN_FILT2_MASK` | RW | 0x00000000 | Filtro 2 — máscara |
| 0x58 | `CAN_FILT3_CODE` | RW | 0x00000000 | Filtro 3 — código |
| 0x5C | `CAN_FILT3_MASK` | RW | 0x00000000 | Filtro 3 — máscara |
| 0x60 | `CAN_FILT_EN` | RW | 0x00 | Habilita dos filtros: `[3:0]` = `FILT_EN_n` (1=habilitado) |

Endereços fora desta tabela → `pslverr=1`, `prdata=0`.

## 2. Detalhamento dos campos

### 0x00 — `CAN_MOD` (modo)
| Bit | Nome | Desc |
|---|---|---|
| 0 | `CAN_EN` | 1 = controlador habilitado (participa do bus). 0 = inativo (não TX, não RX) |
| 1 | `SFT_RST` | 1 = reset por software (auto-limpa). Reinicia FSM/FIFOs/EML, não os registradores de config |
| outros | reservado | 0 |

### 0x04 — `CAN_BTR` (bit timing)
| Bits | Nome | Desc |
|---|---|---|
| [7:0] | `BRP` | Baud rate prescaler (1–255; 0 tratado como 1). Repassa ao `can_btu.prescaler` |
| [10:8] | `PROP` | Propagation segment (repassa `prop_seg`) |
| [14:12] | `SEG1` | Phase segment 1 (repassa `phase_seg1`) |
| [18:16] | `SEG2` | Phase segment 2 (repassa `phase_seg2`) |
| [21:20] | `SJW` | Sync jump width (repassa `sjw`) |
| outros | reservado | 0 |

Reset default: configuração para 500 kbps @ 50 MHz (ver §3).

### 0x08 — `CAN_TCTRL` (controle TX)
| Bit | Nome | Desc |
|---|---|---|
| 0 | `TXREQ` | W1: solicita transmissão (monta msg dos regs TX_* e faz push no Tx FIFO). Sempre lê 0 |
| 1 | `ABORT` | W1: aborta transmissão em andamento (se ainda em arbitragem) |
| outros | reservado | |

### 0x0C — `CAN_TID` (TX ID)
| Bits | Nome |
|---|---|
| [28:0] | ID |
| [29] | IDE |
| [30] | RTR |
| [31] | reservado |

### 0x10 — `CAN_TDLC`
| [3:0] | DLC |

### 0x1C — `CAN_RCTRL`
| Bit/Campo | Nome | Desc |
|---|---|---|
| [0] | `RELEASE` | W1: libera (pop) mensagem corrente do Rx FIFO |
| [15:8] | `RX_CNT` | RO: número de mensagens no Rx FIFO |

### 0x20 — `CAN_RID`, 0x24 — `CAN_RDLC`, 0x28 — `CAN_RDA`, 0x2C — `CAN_RDB`
Mesma codificação de TX (ID/IDE/RTR, DLC, data). Refletem o **topo do Rx FIFO**. Só avançam com `RELEASE`.

### 0x30 — `CAN_STAT`
| Bit | Nome | Desc |
|---|---|---|
| 0 | `BUS_OFF` | EML em Bus Off |
| 1 | `ERR_PASS` | EML em Error Passive |
| 2 | `TX_BUSY` | FSM em transmissão |
| 3 | `RX_AVAIL` | Rx FIFO não vazio |
| 4 | `TX_FULL` | Tx FIFO cheio |
| 5 | `TX_EMPTY` | Tx FIFO vazio |
| outros | reservado | |

### 0x34 — `CAN_ERR`
| Bits | Nome |
|---|---|
| [7:0] | TEC |
| [15:8] | REC |

### 0x38 — `CAN_IEN` (habilita, 8 fontes)
### 0x3C — `CAN_IFG` (flags, write-1-to-clear)
Bits das 8 fontes (mesma posição em IEN e IFG):

| Bit | Fonte |
|---|---|
| 0 | `TX_DONE` — transmissão concluída com ACK |
| 1 | `RX_AVAIL` — mensagem recebida e aceita |
| 2 | `ERR_WARN` — TEC ou REC ≥ 96 |
| 3 | `ERR_PASS` — entrou em Error Passive |
| 4 | `BUS_OFF` — entrou em Bus Off |
| 5 | `ARB_LOST` — perdeu arbitragem |
| 6 | `STUFF_ERR` — erro de stuffing detectado |
| 7 | `CRC_ERR` — erro de CRC detectado |

`irq = |(IFG & IEN)`.

### 0x60 — `CAN_FILT_EN`
| Bits | Nome | Desc |
|---|---|---|
| [3:0] | `FILT_EN_n` | bit n = 1 habilita o filtro n (0..3) |
| [31:4] | reservado | 0 |

### 0x40–0x5C — `CAN_FILTn_CODE`/`MASK` (n=0..3)
| Bits | Nome |
|---|---|
| [28:0] | code/mask do ID |
| [29] | code/mask do IDE (bit relevante p/ distinguir padrão/estendido) |
| [30:31] | reservado |

Regra do filtro (só avaliado se `CAN_FILT_EN[n]=1`): `accept = (id & ~mask) == (code & ~mask)` bit-a-bit (incluindo bit de IDE). Ver `17_spec_acceptance`.

## 3. Configuração default de bit timing (500 kbps @ 50 MHz)

Para obter 500 kbps: período de bit = 2 µs = 100 ciclos de 50 MHz → `prescaler × total_tq = 100`. Encoding **direto** (segmento = nº de TQ; prescaler = ciclos por TQ). Configuração escolhida:

| Campo | Valor | Bits | Observação |
|---|---|---|---|
| `BRP` | 10 | [7:0]=0x0A | 10 ciclos por TQ |
| `PROP` | 2 | [10:8]=010 | |
| `SEG1` | 5 | [14:12]=101 | |
| `SEG2` | 2 | [18:16]=010 | |
| `SJW` | 2 | [21:20]=10 | |

- `total_tq = 1+2+5+2 = 10`; `sample_tq = 1+2+5 = 8` → **ponto de amostragem = 8/10 = 80%** (dentro do recomendado ISO 62,5–87,5%).
- `bit_cycles = 10 × 10 = 100` ciclos = 2 µs @ 50 MHz → **500 kbps**.

Reset de `CAN_BTR` = `0x0022520A` (codificação dos campos acima).

## 4. Reset dos filtros (comportamento restritivo)

Em reset: `CODE=0`, `MASK=0`, **`CAN_FILT_EN=0` (todos desabilitados)**.

Política **restritiva**: com nenhum filtro habilitado, **nenhuma mensagem é aceita** (Rx FIFO permanece vazio). O software deve:
1. programar `CAN_FILTn_CODE`/`MASK` dos filtros desejados;
2. habilitá-los setando os bits em `CAN_FILT_EN`.

A partir daí, uma mensagem é aceita se **qualquer** filtro habilitado casar (OR). (Ver `17_spec_acceptance`.)

## 5. Notas APB

- Handshake APB padrão (PSEL → PENABLE → PREADY). Acessos de 1 wait-state (`pready=1`).
- Leituras dos registradores RX "espelham" o topo do Rx FIFO; não causam pop (apenas `RELEASE` faz pop).
- `TXREQ`, `ABORT`, `RELEASE` são "write-1-to-trigger" e sempre leem 0.
- Escritas em registradores RO são ignoradas.
- `pslverr=1` apenas em offset reservado.

# 02 — Formato de Mensagem (Descritor do FIFO)

Descritor interno usado pelas entradas do Tx FIFO e Rx FIFO, e pelo `can_reg_file` para montar/desmontar mensagens a partir dos registradores APB.

## 1. Largura

`MSG_WIDTH = 99 bits`.

## 2. Layout do bit

```
 98  97      96:68        67:64         63:0
+---+---+--------------+--------+---------------------+
|RTR|IDE|     ID[28:0] | DLC[3:0]|      DATA[63:0]     |
+---+---+--------------+--------+---------------------+
 MSB                                                    LSB
```

| Campo | Bits | Descrição |
|---|---|---|
| `rtr` | [98] | 0 = data frame; 1 = remote frame |
| `ide` | [97] | 0 = frame padrão (ID 11 bits); 1 = frame estendido (ID 29 bits) |
| `id` | [96:68] | Identificador. Estendido: 29 bits completos. Padrão: `id[28:18]` = ID de 11 bits, `id[17:0]` = 0 |
| `dlc` | [67:64] | Data Length Code (0–8). Para remote frame, indica o DLC solicitado |
| `data` | [63:0] | Payload de 0–8 bytes. Byte 0 em `data[7:0]`, byte 7 em `data[63:56]`. Bytes além de DLC são ignorados |

## 3. Mapeamento ID — padrão vs estendido

```
Frame padrão (IDE=0):   id = {11'b_ID11, 18'b0}     -> id[28:18] relevante
Frame estendido (IDE=1):id = ID29                   -> todos os 29 bits relevantes
```

## 4. Mapeamento registrador APB → descritor (montagem TX)

O `can_reg_file` monta o descritor a partir de:

| Registrador | Bits usados | Vão para |
|---|---|---|
| `CAN_TID[28:0]` | ID | `desc.id` |
| `CAN_TID[29]` | IDE | `desc.ide` |
| `CAN_TID[30]` | RTR | `desc.rtr` |
| `CAN_TDLC[3:0]` | DLC | `desc.dlc` |
| `CAN_TDA` | bytes 0–3 | `desc.data[31:0]` |
| `CAN_TDB` | bytes 4–7 | `desc.data[63:32]` |

Equivalente:
```
desc = { CAN_TID[30],            // rtr  [98]
         CAN_TID[29],            // ide  [97]
         CAN_TID[28:0],          // id   [96:68]
         CAN_TDLC[3:0],          // dlc  [67:64]
         CAN_TDB, CAN_TDA };     // data [63:0]
```

## 5. Mapeamento descritor → registrador APB (desmontagem RX)

Ao ler a mensagem do topo do Rx FIFO, o `can_reg_file` expõe:

```
CAN_RID[28:0] = desc.id;     CAN_RID[29] = desc.ide;  CAN_RID[30] = desc.rtr;
CAN_RDLC[3:0] = desc.dlc;
CAN_RDA       = desc.data[31:0];
CAN_RDB       = desc.data[63:32];
```

Os registradores `CAN_RID/RDLC/RDA/RDB` ficam "congelados" no topo do Rx FIFO até `CAN_RCTRL.RELEASE` (pop).

## 6. DLC ↔ número de bytes

| DLC | Bytes | Bits válidos em `data` |
|---|---|---|
| 0 | 0 | nenhum |
| 1 | 1 | `data[7:0]` |
| ... | ... | ... |
| 8 | 8 | `data[63:0]` |

DLC > 8 são reservados pela ISO e tratados como 8 bytes pelo hardware.

## 7. Notas de verificação

- Toda mensagem Tx/RX deve ser representável no descritor de 99 bits sem perda.
- Casos de cobertura (UVM): frames padrão/estendidos, DLC 0 e 8, data frame e remote frame, ID nos extremos (0x000/0x7FF padrão; 0x00000000/0x1FFFFFFF estendido).

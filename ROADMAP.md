# ROADMAP — TCC_CAN (Controlador CAN 2.0B em SystemVerilog + UVM)

> **Fonte da verdade do estado do projeto.** Mantenha este arquivo sincronizado com o
> código. Regras de manutenção em `AGENTS.md` → seção "Manutenção da documentação".

| | |
|---|---|
| **Projeto** | TCC — Controlador CAN 2.0B (ISO 11898-1) em SystemVerilog, verificação UVM |
| **Autor** | Gabriel de Lima Pessoa — Instituto Hardware BR (Pós-graduação) |
| **Repositório** | `github.com/gabrieomineiro/TCC_CAN` |
| **Backup inicial** | `versão 0.00/` (snapshot pré-Fase 0) |

---

## Decisões técnicas travadas (não mudar sem confirmar com o autor)

| Decisão | Valor |
|---|---|
| Padrão CAN | **2.0B** (frames padrão 11-bit + estendidos 29-bit) |
| Modos | **Só modo normal** (sem loopback/listen-only) |
| Interface de host | **APB** 32-bit |
| Simulador | **Xcelium (xrun)** — Cadence |
| Síntese | Cadence **Genus**, alvo **GPDK045** (45 nm) |
| FIFOs Tx/Rx | profundidade **8** cada, message-based (`MSG_W=99` bits) |
| Filtros de aceitação | **4** filtros, 11/29-bit, política **restritiva** |
| Encoding bit-timing | **Direto**: segmento = nº de TQ (1..7); prescaler = ciclos/TQ; sjw 1..3 |
| Default 500 kbps @50 MHz | `presc=10, prop=2, seg1=5, seg2=2, sjw=2` → sample 80%; `CAN_BTR=0x0022520A` |
| Habilita dos filtros | Registrador separado `CAN_FILT_EN[3:0]` em 0x60 |
| `SFT_RST` | Reset **parcial** (FSM/FIFOs/EML/IFG; preserva BTR/filtros/IEN) |

## Decisões de implementação RTL (Fase 3)

| Decisão | Detalhe |
|---|---|
| Handshake de stuffing | FSM avança por **bit de protocolo**: `tx_bit_done` (BSP→FSM) em TX, `rx_valid` em RX. Contadores de stuffing **contínuos**; `stuff_en` só habilita descarte/erro |
| Reset parcial no topo | `rst_core_n = rst_n & ~sft_rst` no núcleo (FSM/FIFOs/EML/BTU/BSP/CRC/arb/filter/int); `reg_file` fica em `rst_n` (preserva config) |
| Nome do topo | `module can_top` (`rtl/can_top.sv`) — integra os 11 módulos |
| CRC no CAN | LFSR iniciado em 0 (`crc_clear` no SOF); `crc_shift` em ARB..DATA (SOF dominante não altera LFSR zerado) |
| Campo DATA | Byte0 transmitido primeiro, MSB-first → byte-swap ao carregar/latchar `data_sr`/`rx_data_cap` |
| Subset BSP/FSM | Só **data frame padrão 11-bit** (TX+RX), Error Frame **active only**. Extensões marcadas `// TODO (fase extensão)` |

---

## Status por fase

### ✅ Fase 0 — Estabilizar o BTU
- `endmodule` do `can_btu.sv` corrigido (`can_btu`, sem `_top`); TB simula **RTL** (não netlist).
- Paths dos `.f` corrigidos; `uvm_analysis_imp_decl(_monitor)` movido para o **package**;
  classes UVM em `package can_btu_pkg` (não `include` no TB); `run_test()` por `+UVM_TESTNAME`.
- Runner Xcelium: `script/run_btu.sh`.

### ✅ Fase 1 — Verificação significativa do BTU
- **Scoreboard por propriedades/invariantes ISO + medições** (não espelha a FSM de sync do RTL).
- `seq_item` = cenário bit-a-bit; driver segura config por `num_bits × bit_cycles` ciclos.
- 8 propriedades (P1–P8); cobertura com bins **alcançáveis**; sequências random + 6 dirigidas;
  testes base + 7 derivados via `+UVM_TESTNAME`.
- **Pendente:** rodar no Xcelium (validação final do usuário).

### ✅ Fase 2 — Especificações (`Docs/specs/`)
13 documentos: `00_arquitetura_topo` · `01_mapa_registradores_apb` · `02_formato_mensagem` ·
`11_spec_bsp` · `12_spec_crc` · `13_spec_fsm` · `14_spec_arbitration` · `15_spec_error` ·
`16_spec_fifo` · `17_spec_acceptance` · `18_spec_interrupt` · `19_spec_btu` · `19b_spec_reg_file`.

### ✅ Fase 3 — RTL (realinhamento + implementação)
**11 módulos prontos e integrados em `can_top`** (elaboram juntos, Icarus `-g2012` exit 0):

| Módulo | Arquivo | Observação |
|---|---|---|
| defines | `rtl/can_defines.svh` | defaults 500 kbps + params de mensagem |
| FIFO | `rtl/can_fifo.sv` | genérico FWFT (unifica Tx/Rx) |
| CRC-15 | `rtl/can_crc.sv` | bit-serial, poly 0x4599 |
| Arbitration | `rtl/can_arbitration.sv` | comparador c/ sample_tick |
| Acceptance | `rtl/can_acceptance.sv` | 4 filtros, política restritiva |
| Interrupt | `rtl/can_interrupt.sv` | 8 fontes, máscara, W1C |
| Error (EML) | `rtl/can_error.sv` | TEC/REC ISO, Error Active/Passive/Bus Off |
| RegFile | `rtl/can_reg_file.sv` | host APB, monta/desmonta descritor 99b |
| BSP | `rtl/can_bsp.sv` | stuffing/destuffing + drive/sample; emite `tx_bit_done` |
| FSM | `rtl/can_fsm.sv` | frame sequencer (subset padrão 11-bit) |
| Top | `rtl/can_top.sv` | integração; reset parcial `rst_core_n` |

**Pendente (validação):** rodar no **Xcelium** (elaboração + TB de sistema). O Icarus aqui é
apenas syntax-check; a validação funcional real é no Xcelium.

### ⏳ Pendências (Fase 3 — verificação e extensão)
- **TBs simples por módulo** — 9 smoke tests self-checking criados em
  `uvm/testbench/tb_can_<module>.sv` (todos PASS no Icarus como sanity-check;
  validação final no Xcelium pendente). Cobre: FIFO, CRC, Arbitration,
  Acceptance, Interrupt, Error (EML), RegFile, BSP, FSM. Script runner:
  `script/run_module_tbs.sh`. **Bug do RTL corrigido:** readback de
  `CAN_MOD` devolvia `CAN_EN` no bit errado (`can_reg_file.sv`).
- **TB de sistema do `can_top`** — existe um TB mínimo (smoke test, não-UVM) em
  `uvm/testbench/tb_can_top.sv` (TX 11-bit c/ ACK respondido por modelo de bus).
  Syntax-check Icarus OK; **falta rodar no Xcelium** e confirmar o subset TX.
  Diretório `uvm/CAN_TOP/` segue vazio (futuro env UVM de integração).
- **UVM envs por módulo** (`uvm/<MODULO>/`, template `uvm/BTU/`) — só existe o do BTU.
  Diretórios `uvm/ARBITRATION/`, `uvm/FSM/`, `uvm/CAN_TOP/` já criados (vazios).
- **Validação Xcelium** de tudo (BTU + top + módulos + TBs simples).
- **Extensão do subset** BSP/FSM: frames estendidos, remote (RTR), overload, error-frame completo.
- **Documentar o template UVM** em `uvm/README.md` ao criar o segundo env.
- **Limpeza:** remover/regenerar `rtl/can_btu.v` (netlist stale, `module can_btu_top`).

---

## Estrutura de diretórios

```
TCC_CAN/
├── rtl/                 # RTL (can_<module>.sv + can_defines.svh)
├── uvm/
│   ├── BTU/             # UVM do BTU (template canônico, 12 arquivos)
│   ├── testbench/       # TB mínimo não-UVM do can_top (tb_can_top.sv)
│   ├── ARBITRATION/ FSM/ CAN_TOP/   # vazios (futuros envs)
├── Docs/
│   ├── specs/           # 13 specs Markdown
│   └── *.pdf            # ISO 11898, CAN 2.0B, spec/vplan Entrega1
├── script/              # simlist.f (BTU), simlist_can.f (top), cellist.f, synth.f, setup_1.tcl, run_btu.sh
├── constraints/         # can_btu.sdc / .sdf
├── testbench/           # (vazio — TB mínimo do topo vai aqui ou em uvm/CAN_TOP/)
├── img/ rpt/ Relatórios/
├── versão 0.00/         # backup pré-Fase 0
├── ROADMAP.md  AGENTS.md  HANDS_ON.md
```

## Como rodar
```bash
# Elaborar o topo (Xcelium, a partir da raiz):
xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f

# TB mínimo de sistema do can_top (smoke test, não-UVM):
xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
     uvm/testbench/tb_can_top.sv

# Rodar o UVM do BTU:
xrun -uvm -sv -access +rwc -timescale 1ns/1ps -f script/simlist.f +UVM_TESTNAME=can_btu_full_test
# ou:  ./script/run_btu.sh can_btu_full_test

# Rodar todos os TBs simples dos módulos (Xcelium):
./script/run_module_tbs.sh
# ou UM TB por vez (menu interativo; logs em rpt/tb_runs/, arquivos do xrun em genus/):
./script/run_tb.sh
# ou um específico:
xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f uvm/testbench/tb_can_crc.sv
```
**Syntax-check rápido (local, Windows + Icarus — NÃO é o simulador-alvo):**
```powershell
iverilog -g2012 -t null -I rtl rtl\<modulo>.sv                          # módulo isolado
iverilog -g2012 -t null -I rtl rtl\can_btu.sv rtl\can_bsp.sv ... rtl\can_top.sv   # top
```

## Próximos passos hands-on
→ ver `HANDS_ON.md`

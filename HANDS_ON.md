# HANDS_ON — O que falta fazer (próximos passos práticos)

> Leia junto com `ROADMAP.md` (estado) e `AGENTS.md` (convenções + padrões).
> Atualize este arquivo sempre que um item for concluído ou a ordem mudar.

## Estado resumido
- ✅ Fase 0/1 — BTU estabilizado + UVM significativo (`uvm/BTU/`). **Falta rodar no Xcelium.**
- ✅ Fase 2 — 13 specs em `Docs/specs/`.
- ✅ Fase 3 RTL — **11 módulos prontos e integrados em `can_top`** (elaboram no Icarus
  `-g2012`; validação funcional real no Xcelium **pendente**).
- ✅ **TBs simples por módulo** — 9 smoke tests em `uvm/testbench/tb_can_<mod>.sv`
  (FIFO, CRC, Arbitration, Acceptance, Interrupt, Error, RegFile, BSP, FSM).
  Todos PASS no Icarus. **Bug corrigido:** readback de `CAN_MOD` (bit errado).
- 🚧 Fase 3 verificação — **UVM envs por módulo** (só existe `uvm/BTU/`) + extensão do subset.

---

## 🎯 PRÓXIMO TRABALHO (em ordem)

### Passo 1 — Rodar TBs simples no Xcelium (validação funcional preliminar)
Cada módulo tem um smoke test self-checking que imprime `SMOKE TEST PASS`/`FAIL`.
Rodar todos de uma vez:
```bash
./script/run_module_tbs.sh
# ou individualmente:
xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f uvm/testbench/tb_can_crc.sv
```
- Os TBs já passaram no Icarus (sanity-check). Aqui o objetivo é confirmar no
  simulador-alvo e coletar logs em `rpt/tb_<mod>.log`.
- Bugs novos (se houver) vão aparecer como `FAIL` — investigar via waveform (VCD).

### Passo 2 — Elaborar `can_top` + TB de sistema no Xcelium
```bash
xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f              # só elaborar
xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
     uvm/testbench/tb_can_top.sv                                              # TB de sistema
```
- Confirmar SOF → ARB → CTRL → DATA → CRC → ACK → EOF → Intermission no log.
- Investigar bugs que aparecerem (suspeita: off-by-one na amostragem do ACK em
  `can_fsm` TX_ACK). Ajustar o RTL até o smoke test PASS.

### Passo 3 — UVM envs por módulo (verificação formal)

### Passo 4 — Extensão do subset BSP/FSM
- Adicionar (hoje marcados no código com `// TODO (fase extensão)`):
  frames estendidos (29-bit, SRR/IDE/ID18), remote frames (RTR), overload frame,
  error-frame completo (passive/echo), bit-error detection.
- Atualizar specs (`11_bsp`, `13_fsm`) e `ROADMAP.md` conforme avança.

---

## ✅ Validação final (Xcelium) — checklist
1. Rodar TBs simples dos módulos: `./script/run_module_tbs.sh` — confirmar PASS.
2. Rodar BTU: `./script/run_btu.sh can_btu_full_test` — confirmar PASS + cobertura.
3. Rodar TB mínimo do `can_top` (Passo 2).
4. Rodar cada env de módulo (Passo 3).
5. Rodar `uvm/CAN_TOP/` (integração) — quando existir.
6. Gate-level (opcional): regerar netlist via Genus + `cellist.f` + SDF.

## 🧹 Itens de limpeza pendentes
- `rtl/can_btu.v` (netlist stale, `module can_btu_top`) — remover ou regenerar na próxima
  síntese Genus (o `setup_1.tcl` já está com `HDL_NAME=can_btu`).
- `can_defines.svh` já atualizado (defaults 500 kbps). ✓

---

## 📜 Concluído (histórico)
- **Fase 0/1** — BTU estabilizado + UVM refeito (propriedades + cobertura por bit).
- **Fase 2** — 13 specs em `Docs/specs/`.
- **Fase 3 RTL** — `can_reg_file` (novo), `can_bsp`/`can_fsm`/`can_top` reescritos
  (subset data frame padrão 11-bit); handshake de stuffing `tx_bit_done`; contadores de
  stuffing contínuos; byte-swap do campo DATA; reset parcial `rst_core_n = rst_n & ~sft_rst`;
  `script/simlist_can.f`; specs `00`/`11`/`13` + `ROADMAP`/`AGENTS` atualizados.
- **TB mínimo do `can_top`** — `uvm/testbench/tb_can_top.sv` (smoke test TX 11-bit
  não-UVM, com modelo de bus reflexão + ACK responder). Icarus syntax-check OK.
- **TBs simples por módulo** — 9 smoke tests em `uvm/testbench/tb_can_<mod>.sv`
  (FIFO, CRC, Arbitration, Acceptance, Interrupt, Error, RegFile, BSP, FSM).
  Todos PASS no Icarus. **Bug do RTL corrigido:** readback de `CAN_MOD` devolvia
  `CAN_EN` no bit 1 em vez do bit 0 (`can_reg_file.sv`). Script runner
  `script/run_module_tbs.sh`.

---
**Como retomar:** abra `ROADMAP.md` → veja a fase → siga os Passos acima.
Atualize `ROADMAP.md`/`HANDS_ON.md` a cada item concluído.

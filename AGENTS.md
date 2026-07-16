# AGENTS.md — Guia para agentes (e para o autor) no projeto TCC_CAN

> Este arquivo orienta qualquer agente (IA ou humano) que for trabalhar no projeto.
> **Leia antes de começar** — em especial a seção "8. Manutenção da documentação".

## 1. Contexto do projeto
Controlador **CAN 2.0B** em **SystemVerilog** com verificação **UVM**. TCC de
pós-graduação (Instituto Hardware BR). Apenas **modo normal**. Host via **APB**.
Simulador-alvo: **Xcelium (xrun)**. Síntese: **Genus / GPDK045**.

**Fonte da verdade do estado:** `ROADMAP.md`. **Próximos passos:** `HANDS_ON.md`.
**Specs:** `Docs/specs/`. **Sempre consulte esses arquivos antes de mexer em RTL/UVM.**

## 2. Decisões travadas (NÃO mudar sem confirmar com o autor)
- CAN 2.0B (11 e 29 bit), modo normal only, APB 32-bit.
- FIFOs Tx/Rx profundidade 8, message-based (`MSG_W=99`). 4 filtros, política restritiva.
- Encoding bit-timing **direto** (segmento = nº de TQ; prescaler = ciclos/TQ).
- Default 500 kbps @50 MHz: `presc=10/prop=2/seg1=5/seg2=2/sjw=2`.
- `CAN_FILT_EN[3:0]` em 0x60; `SFT_RST` = reset parcial.
- Topo: `module can_top`; reset parcial `rst_core_n = rst_n & ~sft_rst`.
- Subset atual BSP/FSM: só **data frame padrão 11-bit**, error frame **active only**.

## 3. Convenções de código
- **RTL:** um arquivo por módulo em `rtl/`, nome `can_<module>.sv`, `module can_<module>`.
- **Linguagem dos docs/specs:** português (BR). **Comentários de código: mínimos**
  (só cabeçalho de arquivo e onde o "porquê" não é óbvio). **Sem emojis.**
- **Reset:** assíncrono ativo-baixo (`always_ff @(posedge clk or negedge rst_n)`),
  liberação síncrona. Sinais `*_n` = ativo-baixo.
- **CAN lógico:** `CAN_DOMINANT=1'b0`, `CAN_RECESSIVE=1'b1`.
- **Larguras padrão:** ver `rtl/can_defines.svh` (`CAN_MSG_WIDTH=99`, `CAN_ID_WIDTH=29`, …).
- Não criar arquivos de doc além dos de manutenção obrigatória
  (ROADMAP/AGENTS/HANDS_ON/specs) sem solicitação explícita.
- Ao marcar algo fora do subset, use `// TODO (fase extensão): <item>`.

## 4. Convenções UVM (template canônico = `uvm/BTU/`)
Cada módulo tem seu env em `uvm/<MODULE>/` seguindo **exatamente** a estrutura do BTU:
```
uvm/<MODULO>/
├── can_<modulo>_pkg.sv       # package: uvm_analysis_imp_decl + includes ordenados
├── can_<modulo>_if.sv        # interface (drv_cb / mon_cb)
├── can_<modulo>_seq_item.sv  # transação (cenário + observado)
├── can_<modulo>_sequence.sv  # base + aleatória + dirigidas
├── can_<modulo>_driver.sv    # estímulo controlado/estável via drv_cb
├── can_<modulo>_monitor.sv   # amostra por ciclo via mon_cb
├── can_<modulo>_agent.sv     # driver + monitor + sequencer + agent_ap
├── can_<modulo>_scoreboard.sv# propriedades/invariantes + medições
├── can_<modulo>_coverage.sv  # covergroups (bins ALCANÇÁVEIS)
├── can_<modulo>_env.sv       # agent + scoreboard + coverage
├── can_<modulo>_test.sv      # base + derivados (+UVM_TESTNAME)
└── tb_can_<modulo>.sv        # top: clk, if, DUT, config_db, run_test
```
Ao criar um novo env, **copie a estrutura do BTU** e adapte nomes/spec.

## 5. Padrões aprendidos (evitar os erros já cometidos)

### UVM / SystemVerilog geral
- **`uvm_analysis_imp_decl(<suffix>)` em ESCOPO DE PACKAGE**, nunca dentro de classe.
- **Classes UVM em `package can_<module>_pkg`**, não como `include` direto no `module tb`.
- **TB importa o package** e instancia a interface **antes** do package na filelist.
- **O driver controla o reset** (`apply_reset` antes do loop `get_next_item`); o TB não tem
  bloco de reset próprio; a interface só inicializa `rst_n=0` em time 0.
- **`run_test()` sem arg**, seleção por `+UVM_TESTNAME`.
- **Scoreboard por propriedades**, não por modelo-espelho da FSM (baixo falso-negativo).
- **Sequências em nível de bit:** driver segura a config por `num_bits × bit_cycles` ciclos.
- **Coverage:** bins **alcançáveis**; nunca `coverpoint 0` placeholder.
- **Conexão analysis port:** `mon.mon_ap.connect(agent_ap);`.
- **`randomize()` sempre checado:** `if (!it.randomize() with {...}) \`uvm_error(...)`.

### BSP / FSM / integração (aprendidos na Fase 3)
- **Handshake de stuffing (BSP↔FSM):** o FSM avança por **bit de protocolo**, não por bit de
  barramento. Em TX usa o strobe `tx_bit_done` do BSP (1 por bit consumido; **0** no bit-time
  em que se insere um stuff-bit); em RX usa `rx_valid` (1 por bit destuffed; stuff-bits são
  descartados). Assim os contadores de campo do FSM contam bits de protocolo e o CRC é
  alimentado nessa cadência.
- **Contadores de stuffing contínuos:** os contadores de bits consecutivos do BSP correm a
  cada `bit_tick`/`sample_tick`; `stuff_en` apenas **habilita** descarte/erro. O SOF
  (dominante após recessivos do intermission) reinicia a corrida por mudança de valor —
  **sem reset explícito entre frames**.
- **CRC no CAN:** LFSR iniciado em **0** (não 0x7FFF); `crc_clear` no SOF; `crc_shift` em
  ARB..DATA. O SOF (dominante 0) não altera o LFSR zerado, então começar o shift em ARB é
  equivalente a incluir o SOF — aproveite isso para não precisar de shift+clear no mesmo ciclo.
- **Campo DATA — byte-swap:** CAN transmite **byte0 primeiro, MSB-first**; o descritor guarda
  byte0 em `data[7:0]`. Logo: TX carrega `data_sr = {tx_msg[7:0], tx_msg[15:8], …,
  tx_msg[63:56]}` e shifta MSB-first; RX captura MSB-first e monta `rx_msg` com o byte-swap
  **inverso**. Mantenha TX e RX simétricos ou o CRC/loopback quebra.
- **Off-by-one em latches RX:** ao latchar campos (`rx_id`, `rx_dlc`, `rx_crc`) no ciclo da
  transição, o último bit ainda **não** entrou no shift register (non-blocking). Use o
  `rx_bit` corrente como último bit — ex. no 12º `rx_valid` do ARB:
  `rx_id <= rx_arb_cap[10:0]; rx_rtr <= rx_bit;` (e não `rx_arb_cap[11:1]`).
- **Reset parcial no topo:** `rst_core_n = rst_n & ~sft_rst` alimenta o `rst_n` de **todo o
  núcleo** (BTU/BSP/CRC/FSM/arb/error/FIFOs/filter/int); o `reg_file` fica apenas em `rst_n`
  para **preservar config** (BTR/filtros/IEN). `sft_rst` é pulso combinacional do reg_file.
- **Saídas "espelho" evitam múltiplos drivers:** o FSM **reemite** `sync_en` (saída) =
  `can_en` (entrada). No topo, `btu.sync_en` vem do **FSM**, não do `reg_file.can_en`. Nunca
  conecte uma mesma net a duas saídas (ex.: não ligue `.tx_msg` do reg_file e o `.rdata` do
  FIFO na mesma net — use nets separadas para wdata vs rdata).
- **Consistência write/read em registradores RW:** o readback de `prdata` deve usar o
  MESMO bit que a escrita. Bug encontrado: `CAN_MOD` era escrito por `can_en_r <= pwdata[0]`
  mas lido como `prdata = {30'b0, can_en_r, 1'b0}` (can_en_r no bit 1). Sempre confira
  readback vs escrita vs spec ao implementar/alterar o reg_file.
- **Subset-first:** implemente o caminho feliz (TX/RX de data frame padrão) + erros básicos
  antes de estender. Isole o que falta com `// TODO (fase extensão):`.

### Tooling
- **Icarus NÃO é o simulador-alvo:** só syntax-check (`iverilog -g2012 -t null`). Aviso
  conhecido e **não-fatal**: "constant selects in always_* processes" (comparações/índices
  constantes em always). A validação real é no **Xcelium**.
- **TBs simples por módulo** (smoke tests não-UVM em `uvm/testbench/tb_can_<mod>.sv`):
  rodam no Icarus como sanity-check (`vvp`) e no Xcelium como validação. Use o script
  `script/run_module_tbs.sh` para rodar todos de uma vez (logs em `rpt/`).
- **Race condition em TBs com always_ff:** ao final de uma task APB write/read, NÃO limpe
  `pwdata`/`paddr` no MESMO posedge em que o `always_ff` do DUT amostra — o simulador pode
  processar o stimulus antes do DUT e ele ver os sinais já zerados. Faça o cleanup no
  **negedge** seguinte (`@(negedge clk); psel=0; ...`). Idem para checagens de saídas
  combinacionais do DUT (`pslverr`, `ifg_clear`, `sft_rst`): só são válidas **durante** o
  access phase; capture-as dentro da task ou amostra com `#1` após o posedge.
- **Arrays em portas no Icarus:** o Icarus pode retornar `X` para portas de array
  conectadas via `generate assign` (ex.: `filt_code[0]` em `can_reg_file`). O registrador
  interno (`filt_code_r[0]`) está correto. Em TBs, checar via referência hierárquica
  (`DUT.filt_code_r[0]`) quando validar no Icarus; o Xcelium lida com a porta corretamente.

## 6. Toolchain
- **Simulação (alvo):** Xcelium — `xrun -sv -access +rwc -timescale 1ns/1ps -f <filelist>`
  (UVM: adicionar `-uvm` e `+UVM_TESTNAME=<test>`).
- **Syntax-check local:** `iverilog -g2012 -t null -I rtl rtl\<modulo>.sv`.
- **Síntese:** Genus via `script/setup_1.tcl` (alvo gpdk045).
- **Filelists:** `script/simlist.f` (BTU), `script/simlist_can.f` (top), `script/cellist.f`
  (gate-level), `script/synth.f` (síntese), `script/run_btu.sh` (runner BTU).
- **Runners de simulação:**
  - `script/run_btu.sh [test]` — BTU (UVM, `+UVM_TESTNAME`).
  - `script/run_module_tbs.sh` — roda TODOS os TBs simples dos módulos em sequência.
  - `script/run_tb.sh` — roda UM TB simples por vez (menu interativo); só o TB escolhido
    é compilado (demais ficam comentados, sem conflito de `module tb`). Logs em
    `rpt/tb_runs/`; arquivos gerados pelo xrun (INCA_lib/waves/snapshots) em `genus/`
    via `genus/cds.lib` + `-tmpdir genus/tmp`.

## 7. Mapa de registradores e formato de mensagem
- Registradores APB: `Docs/specs/01_mapa_registradores_apb.md`.
- Descritor de mensagem (FIFO, 99 bits): `Docs/specs/02_formato_mensagem.md`.
- Interface de cada módulo: spec correspondente em `Docs/specs/`.

---

## 8. ⭐ Manutenção da documentação (OBRIGATÓRIO — sempre, a cada alteração)

**O código e a documentação devem contar a mesma história.** Toda vez que você (agente)
fizer uma alteração que mude o estado do projeto, **atualize a doc na mesma operação**.
Nunca deixe a doc desatualizada — sessões podem ser retomadas a qualquer momento
(inclusive após interrupção por limite de tokens), e a doc é a única forma de retomar
com segurança.

**Arquivos-canônico a manter sincronizados:**
- `ROADMAP.md` — estado do projeto (fases, módulos, decisões).
- `HANDS_ON.md` — o que falta fazer agora (próximos passos práticos).
- `AGENTS.md` — este guia (convenções + padrões aprendidos).
- `Docs/specs/<NN>_spec_<module>.md` — interface/comportamento de cada módulo.

**Regras (o que dispara atualização):**
1. **Concluir/avançar fase ou módulo** → atualize `ROADMAP.md` (status por fase + tabela
   de módulos) e risque/conclua o item em `HANDS_ON.md`.
2. **Implementar/alterar um módulo RTL** → se a interface mudou, atualize a spec
   correspondente para bater com os portas do RTL; atualize `ROADMAP.md`.
3. **Mudar uma decisão técnica** → atualize "Decisões travadas"/"Decisões de implementação"
   no `ROADMAP.md` e na spec relevante; registre o porquê.
4. **Criar um novo env UVM** → registre em `ROADMAP.md`; documente o passo-a-passo e mantenha
   `uvm/README.md` quando existir.
5. **O "próximo trabalho" mudar** → reescreva `HANDS_ON.md` para refletir a nova ordem.
6. **Aprender um novo padrão/gotcha** → adicione à seção 5 deste `AGENTS.md`.
7. **Mudar como rodar/toolchain** → atualize seção 6 do `AGENTS.md` e o "Como rodar" do `ROADMAP.md`.

**Regra de ouro:** se duvidar se precisa atualizar, **atualize**. Antes de começar qualquer
tarefa, leia `ROADMAP.md` → `HANDS_ON.md` → `AGENTS.md` seções 2 e 5 → a spec do módulo-alvo.

## 9. Ordem de leitura sugerida para uma nova sessão
1. `ROADMAP.md` (estado atual)
2. `HANDS_ON.md` (o que fazer agora)
3. `AGENTS.md` seções 2, 5 e 8 (decisões + padrões + manutenção da doc)
4. A spec do módulo que vai tocar (`Docs/specs/`)

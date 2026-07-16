#!/usr/bin/env bash
# =============================================================================
# run_tb.sh — Roda UM testbench (smoke test, não-UVM) por vez no Xcelium (xrun).
#
#   Uso (a partir da raiz do projeto):
#     ./script/run_tb.sh
#
#   - Menu interativo: escolhe qual TB rodar.
#   - SÓ o TB escolhido é compilado/executado. Os comandos dos demais TBs estão
#     listados mais abaixo como ALTERNATIVAS COMENTADAS (basta copiar/descomentar
#     a linha desejada para rodar direto, sem o menu). Assim nunca há conflito
#     de múltiplos 'module tb' compilados juntos.
#   - Logs de cada execução em:  rpt/tb_runs/tb_<nome>_<datahora>.log
#   - Arquivos gerados pelo xrun (INCA_lib/snapshot/.vcd/.shm/misc) em:  genus/
#
#   Pré-requisito: Xcelium (xrun) no PATH.
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJ_DIR"

# ---- Diretórios de saída -----------------------------------------------------
GENUS_DIR="genus"          # arquivos gerados pelo xrun (INCA_lib/waves/snapshots)
LOG_DIR="rpt/tb_runs"      # logs de cada execução
mkdir -p "$GENUS_DIR" "$GENUS_DIR/tmp" "$LOG_DIR"

# ---- cds.lib para o xrun compilar DENTRO de genus/ (mantém a raiz limpa) ------
# A biblioteca 'work' aponta para genus/work, então o INCA_lib vai para genus/
# (em vez de poluir a raiz do projeto) e fica reutilizável entre execuções
# (compilação incremental).
GENUS_ABS="$(cd "$GENUS_DIR" && pwd)"
cat > "$GENUS_DIR/cds.lib" <<EOF
# Auto-gerado por script/run_tb.sh -- nao editar a mao.
# Biblioteca de trabalho dentro de genus/ -> INCA_lib fica aqui.
softinclude \$CDS_INST_DIR/tools/inca/files/cds.lib
DEFINE work ${GENUS_ABS}/work
EOF

# ---- Testbenches disponíveis (smoke tests dos módulos) -----------------------
TBS=(fifo crc arbitration acceptance interrupt error reg_file bsp fsm top)

echo "=========================================================="
echo " Runner de testbench (Xcelium/xrun) -- TCC_CAN"
echo "=========================================================="
echo
echo "Qual testbench rodar?"
for i in "${!TBS[@]}"; do
    printf "  %2d) tb_can_%s\n" "$((i+1))" "${TBS[$i]}"
done
echo
read -rp "Digite o numero [1-${#TBS[@]}] (ou Enter = top): " CHOICE

if [ -z "$CHOICE" ]; then CHOICE="${#TBS[@]}"; fi
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#TBS[@]}" ]; then
    echo "[ERRO] Escolha invalida: '$CHOICE'"
    exit 1
fi
NAME="${TBS[$((CHOICE-1))]}"
TB="uvm/testbench/tb_can_${NAME}.sv"

if [ ! -f "$TB" ]; then
    echo "[ERRO] $TB nao existe"
    exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="${LOG_DIR}/tb_${NAME}_${STAMP}.log"

echo
echo ">>> TB       : $TB"
echo ">>> Log      : $LOG"
echo ">>> Workspace: ${GENUS_DIR}/  (INCA_lib + arquivos gerados)"
echo

# =============================================================================
# Execucao. SÓ UM testbench por vez ($TB) -> sem conflito de 'module tb'.
# Alternativas comentadas (rodar direto, sem o menu):
# -----------------------------------------------------------------------------
# xrun -sv -access +rwc -timescale 1ns/1ps -cdslib genus/cds.lib -tmpdir genus/tmp -f script/simlist_can.f uvm/testbench/tb_can_fifo.sv         -l rpt/tb_runs/tb_fifo.log
# xrun -sv -access +rwc -timescale 1ns/1ps -cdslib genus/cds.lib -tmpdir genus/tmp -f script/simlist_can.f uvm/testbench/tb_can_crc.sv          -l rpt/tb_runs/tb_crc.log
# xrun -sv -access +rwc -timescale 1ns/1ps -cdslib genus/cds.lib -tmpdir genus/tmp -f script/simlist_can.f uvm/testbench/tb_can_arbitration.sv  -l rpt/tb_runs/tb_arbitration.log
# xrun -sv -access +rwc -timescale 1ns/1ps -cdslib genus/cds.lib -tmpdir genus/tmp -f script/simlist_can.f uvm/testbench/tb_can_acceptance.sv   -l rpt/tb_runs/tb_acceptance.log
# xrun -sv -access +rwc -timescale 1ns/1ps -cdslib genus/cds.lib -tmpdir genus/tmp -f script/simlist_can.f uvm/testbench/tb_can_interrupt.sv    -l rpt/tb_runs/tb_interrupt.log
# xrun -sv -access +rwc -timescale 1ns/1ps -cdslib genus/cds.lib -tmpdir genus/tmp -f script/simlist_can.f uvm/testbench/tb_can_error.sv        -l rpt/tb_runs/tb_error.log
# xrun -sv -access +rwc -timescale 1ns/1ps -cdslib genus/cds.lib -tmpdir genus/tmp -f script/simlist_can.f uvm/testbench/tb_can_reg_file.sv     -l rpt/tb_runs/tb_reg_file.log
# xrun -sv -access +rwc -timescale 1ns/1ps -cdslib genus/cds.lib -tmpdir genus/tmp -f script/simlist_can.f uvm/testbench/tb_can_bsp.sv          -l rpt/tb_runs/tb_bsp.log
# xrun -sv -access +rwc -timescale 1ns/1ps -cdslib genus/cds.lib -tmpdir genus/tmp -f script/simlist_can.f uvm/testbench/tb_can_fsm.sv          -l rpt/tb_runs/tb_fsm.log
# xrun -sv -access +rwc -timescale 1ns/1ps -cdslib genus/cds.lib -tmpdir genus/tmp -f script/simlist_can.f uvm/testbench/tb_can_top.sv          -l rpt/tb_runs/tb_top.log
# =============================================================================

set +e
xrun -sv -access +rwc -timescale 1ns/1ps \
     -cdslib "$GENUS_DIR/cds.lib" \
     -tmpdir "$GENUS_DIR/tmp" \
     -f script/simlist_can.f \
     "$TB" \
     -l "$LOG"
RC=$?
set -e

# ---- Reloca arquivos esparsos do xrun (que caem na raiz) para genus/ --------
for f in ncsim.key bde.log crash.log; do
    [ -f "$f" ] && mv -f "$f" "$GENUS_DIR/" 2>/dev/null || true
done
shopt -s nullglob
for f in *.vcd *.vcd.gz *.shm; do
    [ -e "$f" ] && mv -f "$f" "$GENUS_DIR/" 2>/dev/null || true
done
shopt -u nullglob

# ---- Resumo ------------------------------------------------------------------
echo
echo "=========================================================="
echo " Fim da execucao (codigo de saida do xrun: $RC)"
echo " Log      : $LOG"
echo " Arquivos : ${GENUS_DIR}/"
if   grep -q "SMOKE TEST PASS" "$LOG" 2>/dev/null; then
    echo " Resultado: [PASS] SMOKE TEST PASS"
elif grep -q "SMOKE TEST FAIL" "$LOG" 2>/dev/null; then
    echo " Resultado: [FAIL] SMOKE TEST FAIL  -- confira o log"
    RC=1
else
    echo " Resultado: [?] sem banner SMOKE TEST -- confira o log"
fi
echo "=========================================================="
exit $RC

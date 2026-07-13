#!/usr/bin/env bash
# =============================================================================
# run_module_tbs.sh — Roda todos os TBs SIMPLES (smoke tests, não-UVM) dos
# módulos do CAN, um de cada vez, no Xcelium (xrun).
#
# Uso (a partir da raiz do projeto):
#   ./script/run_module_tbs.sh           # roda todos
#   ./script/run_module_tbs.sh fifo crc  # roda só os listados
#
# Cada TB é self-checking e imprime "SMOKE TEST PASS" ou "SMOKE TEST FAIL".
# Os logs completos vão para rpt/tb_<module>.log.
#
# Pré-requisito: Xcelium (xrun) no PATH.
# =============================================================================
set -e

RPT_DIR="rpt"
mkdir -p "$RPT_DIR"

# módulos e seus arquivos RTL mínimos (o simlist_can.f cobre todos; o xrun
# elabora só o que o top do TB instancia)
ALL_MODS=( fifo crc arbitration acceptance interrupt error reg_file bsp fsm top )

# se args, usa eles; senão usa todos
if [ $# -gt 0 ]; then
    MODS=("$@")
else
    MODS=("${ALL_MODS[@]}")
fi

PASS=0
FAIL=0
FAILED_MODS=()

for m in "${MODS[@]}"; do
    TB="uvm/testbench/tb_can_${m}.sv"
    LOG="${RPT_DIR}/tb_${m}.log"

    if [ ! -f "$TB" ]; then
        echo "[SKIP] $TB não existe"
        continue
    fi

    echo "=========================================================="
    echo "Rodando TB: $m  (log: $LOG)"
    echo "=========================================================="

    # top compila com simlist_can.f; o xrun elabora só o módulo top do TB
    if xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
            "$TB" -l "$LOG"; then
        if grep -q "SMOKE TEST PASS" "$LOG"; then
            echo "[PASS] $m"
            PASS=$((PASS+1))
        elif grep -q "SMOKE TEST FAIL" "$LOG"; then
            echo "[FAIL] $m (SMOKE TEST FAIL — veja $LOG)"
            FAIL=$((FAIL+1))
            FAILED_MODS+=("$m")
        else
            echo "[?] $m (sem banner PASS/FAIL — veja $LOG)"
            FAIL=$((FAIL+1))
            FAILED_MODS+=("$m")
        fi
    else
        echo "[FAIL] $m (erro de compilação/execução — veja $LOG)"
        FAIL=$((FAIL+1))
        FAILED_MODS+=("$m")
    fi
done

echo "=========================================================="
echo "Resumo: $PASS PASS, $FAIL FAIL"
if [ $FAIL -gt 0 ]; then
    echo "Módulos com falha: ${FAILED_MODS[*]}"
    exit 1
fi
echo "=========================================================="

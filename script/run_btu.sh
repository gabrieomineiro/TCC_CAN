#!/bin/bash
# =============================================================================
# Runner de simulação RTL do CAN BTU no Xcelium (xrun)
#   Uso:  ./script/run_btu.sh [TESTNAME] [VERBOSITY]
#   Default TESTNAME=can_btu_test, VERBOSITY=UVM_MEDIUM
#
#   Testes disponíveis (+UVM_TESTNAME):
#     can_btu_test          - smoke (aleatório curto)
#     can_btu_full_test     - regressão completa (todas as sequências)
#     can_btu_hard_sync_test / can_btu_soft_sync_test
#     can_btu_sjw_sat_test  / can_btu_baud_test
#     can_btu_boundary_test / can_btu_reset_test
# =============================================================================
set -e

TEST=${1:-can_btu_test}
VERB=${2:-UVM_MEDIUM}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJ_DIR"

echo ">>> Simulando BTU (RTL) no Xcelium"
echo ">>> TEST=$TEST  VERBOSITY=$VERB"
echo ">>> PROJ_DIR=$PROJ_DIR"

xrun \
    -uvm \
    -sv \
    -access +rwc \
    -timescale 1ns/1ps \
    -f script/simlist.f \
    +UVM_TESTNAME=$TEST \
    +UVM_VERBOSITY=$VERB

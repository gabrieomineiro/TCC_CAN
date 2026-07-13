// =============================================================================
// Filelist para simulação RTL do CAN BTU (Xcelium / xrun)
//
//   Uso (a partir da raiz do projeto):
//     xrun -uvm -sv -access +rwc -timescale 1ns/1ps \
//          -f script/simlist.f +UVM_TESTNAME=can_btu_test
//
//   Ou via script: ./script/run_btu.sh [nome_do_teste]
// =============================================================================
-incdir rtl
-incdir uvm/BTU

// RTL (DUT) - simulação em nível RTL
rtl/can_btu.sv

// Interface antes do package: o tipo `virtual can_btu_if` precisa estar visível
uvm/BTU/can_btu_if.sv
uvm/BTU/can_btu_pkg.sv

// Testbench top
uvm/BTU/tb_can_btu.sv

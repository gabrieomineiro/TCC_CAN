// =============================================================================
// Filelist para simulação/elaboração RTL do CAN top (Xcelium / xrun)
//
//   Uso (a partir da raiz do projeto):
//     xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f
//
//   Syntax-check rápido (Icarus, Windows):
//     iverilog -g2012 -t null -f script/simlist_can.f
// =============================================================================
-incdir rtl

// RTL (ordem: folhas primeiro; o elaborador resolve a hierarquia)
rtl/can_btu.sv
rtl/can_bsp.sv
rtl/can_crc.sv
rtl/can_arbitration.sv
rtl/can_error.sv
rtl/can_fifo.sv
rtl/can_acceptance.sv
rtl/can_interrupt.sv
rtl/can_reg_file.sv
rtl/can_fsm.sv
rtl/can_top.sv

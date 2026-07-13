// =============================================================================
// Filelist para simulação GATE-LEVEL do CAN BTU (Xcelium / xrun)
// Requer regeneração do netlist (rtl/can_btu.v) por Genus após a renomeação do
// módulo para can_btu. Para back-annotation, adicione:
//   +sdf_verbose +sdf_cmd_file=...  ou  -sdf_cmd_file constraints/can_btu.sdf
// =============================================================================
-incdir uvm/BTU

uvm/BTU/can_btu_if.sv
uvm/BTU/can_btu_pkg.sv
rtl/can_btu.v
uvm/BTU/tb_can_btu.sv
/pdk/gpdk045/gsclib045_all_v4.7/gsclib045/verilog/fast_vdd1v0_basicCells.v

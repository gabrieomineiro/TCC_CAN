//-----------------------------------------------------------------------------
// Package: can_btu_pkg
// Agrupa todas as classes UVM do ambiente de verificação do BTU.
// A macro `uvm_analysis_imp_decl(_monitor)` fica em escopo de package, como
// exigido pelo SystemVerilog (não pode ser expandida dentro do corpo de classe).
//-----------------------------------------------------------------------------
`ifndef CAN_BTU_PKG_SV
`define CAN_BTU_PKG_SV

package can_btu_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Tipo de analysis port para o scoreboard (precisa ser declarado antes da
    // classe que o utiliza).
    `uvm_analysis_imp_decl(_monitor)

    // --- Transação ---
    `include "can_btu_seq_item.sv"
    // --- Sequências ---
    `include "can_btu_sequence.sv"
    // --- Cobertura ---
    `include "can_btu_coverage.sv"
    // --- Driver / Monitor ---
    `include "can_btu_driver.sv"
    `include "can_btu_monitor.sv"
    // --- Agent ---
    `include "can_btu_agent.sv"
    // --- Scoreboard (utiliza uvm_analysis_imp_monitor) ---
    `include "can_btu_scoreboard.sv"
    // --- Environment ---
    `include "can_btu_env.sv"
    // --- Tests ---
    `include "can_btu_test.sv"

endpackage

`endif

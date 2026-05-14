//-----------------------------------------------------------------------------
// Módulo: can_btu_defines.svh
// Descrição: Definições comuns para a CAN Bit Timing Unit(BTU) 
// Autor: Gabriel de Lima Pessoa
// Versão: 1.0
//-----------------------------------------------------------------------------

`ifndef CAN_BTU_DEFINES_SVH
`define CAN_BTU_DEFINES_SVH

//-----------------------------------------------------------------------------
// Parâmetros de Temporização de Bit
//-----------------------------------------------------------------------------

// Larguras dos segmentos de temporização
localparam int CAN_PRESC_WIDTH   = 8;   // Largura do prescaler
localparam int CAN_PROP_WIDTH    = 3;   // Largura do segmento de propagação
localparam int CAN_PHASE_WIDTH   = 3;   // Largura do segmento de fase
localparam int CAN_SJW_WIDTH     = 2;   // Largura do Salto de Sincronização (SJW)

// Valores padrão de temporização (para 500 kbps @ clock de 50 MHz)
localparam bit [7:0]  DEFAULT_PRESCALER = 8'd4;   // Prescaler padrão
localparam bit [2:0]  DEFAULT_PROP_SEG  = 3'd2;   // Segmento de propagação padrão
localparam bit [2:0]  DEFAULT_PHASE_SEG1 = 3'd4;  // Segmento de fase 1 padrão
localparam bit [2:0]  DEFAULT_PHASE_SEG2 = 3'd4;  // Segmento de fase 2 padrão
localparam bit [1:0]  DEFAULT_SJW       = 2'd2;   // SJW padrão

//-----------------------------------------------------------------------------
// Macros
//-----------------------------------------------------------------------------

// Valores de bits dominante e recessivo
`define CAN_DOMINANT 1'b0   // Dominante
`define CAN_RECESSIVE 1'b1  // Recessivo

`endif // CAN_BTU_DEFINES_SVH
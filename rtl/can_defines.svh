//-----------------------------------------------------------------------------
// Módulo: can_defines.svh
// Descrição: Definições comuns para o controlador CAN
// Autor: Gabriel de Lima Pessoa
// Versão: 1.0
//-----------------------------------------------------------------------------

`ifndef CAN_DEFINES_SVH
`define CAN_DEFINES_SVH

//-----------------------------------------------------------------------------
// Parâmetros de Temporização de Bit
//-----------------------------------------------------------------------------

// Larguras dos segmentos de temporização
localparam int CAN_PRESC_WIDTH   = 8;   // Largura do prescaler
localparam int CAN_PROP_WIDTH    = 3;   // Largura do segmento de propagação
localparam int CAN_PHASE_WIDTH   = 3;   // Largura do segmento de fase
localparam int CAN_SJW_WIDTH     = 2;   // Largura do Salto de Sincronização (SJW)

// Valores padrão de temporização (para 500 kbps @ clock de 50 MHz)
localparam bit [7:0]  DEFAULT_PRESCALER    = 8'd4;   // Prescaler padrão
localparam bit [2:0]  DEFAULT_PROP_SEG     = 3'd2;   // Segmento de propagação padrão
localparam bit [2:0]  DEFAULT_PHASE_SEG1   = 3'd4;   // Segmento de fase 1 padrão
localparam bit [2:0]  DEFAULT_PHASE_SEG2   = 3'd4;   // Segmento de fase 2 padrão
localparam bit [1:0]  DEFAULT_SJW          = 2'd2;   // SJW padrão

//-----------------------------------------------------------------------------
// Macros
//-----------------------------------------------------------------------------

// Valores de bits dominante e recessivo
`define CAN_DOMINANT  1'b0   // Dominante (0V)
`define CAN_RECESSIVE 1'b1   // Recessivo (5V via resistor)

//-----------------------------------------------------------------------------
// Estados da FSM principal
//-----------------------------------------------------------------------------

typedef enum logic [3:0] {
    IDLE,           // Estado ocioso
    TX_SETUP,       // Preparação para transmissão
    TX_SOF,         // Start of Frame
    TX_ID,          // Identificador padrão (11 bits)
    TX_EXT_ID,      // Identificador estendido (18 bits)
    TX_RTR,         // Remote Transmission Request
    TX_CTRL,        // Controle (DLC)
    TX_DATA,        // Dados (0-8 bytes)
    TX_CRC,         // CRC sequencial
    TX_ACK,         // Acknowledge
    TX_EOF,         // End of Frame
    INTERMISSION,   // Intermission delay
    RX_IDLE,        // Ocioso para recepção
    RX_SOF,         // Detectando SOF
    RX_ID,          // Recebendo ID
    RX_EXT_ID,      // Recebendo ID estendido
    RX_RTR,         // Recebendo RTR
    RX_CTRL,        // Recebendo controle
    RX_DATA,        // Recebendo dados
    RX_CRC,         // Recebendo CRC
    RX_ACK,         // Enviando ACK
    ERROR_FLAG,     // Transmissão de erro
    ERROR_WAIT      // Espera após erro
} fsm_state_t;

//-----------------------------------------------------------------------------
// Estados do BTU (Bit Timing Unit)
//-----------------------------------------------------------------------------

typedef enum logic [1:0] {
    SYNC_IDLE,
    SYNC_WAIT_EDGE,
    SYNC_ADJUSTING,
    SYNC_COMPLETE
} btu_sync_state_t;

//-----------------------------------------------------------------------------
// Tamanhos de campo
//-----------------------------------------------------------------------------

localparam ID_STD_WIDTH     = 10;    // Standard ID: 11 bits (exclui bit de estendido)
localparam ID_EXT_WIDTH     = 18;    // Extended ID: 29 bits (exclui bits de estendido)
localparam MAX_DATA_BYTES   = 8;
localparam DATA_WIDTH       = 64;     // 8 bytes * 8 bits
localparam CRC_WIDTH        = 15;
localparam DLC_WIDTH        = 4;

`endif // CAN_DEFINES_SVH
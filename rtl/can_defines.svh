//-----------------------------------------------------------------------------
// can_defines.svh
// Definições comuns do controlador CAN 2.0B.
// Codificação DIRETA: segmento = nº de TQ; prescaler = ciclos por TQ.
//-----------------------------------------------------------------------------
`ifndef CAN_DEFINES_SVH
`define CAN_DEFINES_SVH

// --- Larguras dos campos de bit timing ---
localparam int CAN_PRESC_WIDTH = 8;
localparam int CAN_PROP_WIDTH  = 3;
localparam int CAN_PHASE_WIDTH = 3;
localparam int CAN_SJW_WIDTH   = 2;

// --- Defaults de bit timing: 500 kbps @ 50 MHz, sample point 80% ---
// prescaler=10, prop=2, seg1=5, seg2=2 -> total_tq=10, sample_tq=8
localparam bit [7:0] DEFAULT_PRESCALER   = 8'd10;
localparam bit [2:0] DEFAULT_PROP_SEG    = 3'd2;
localparam bit [2:0] DEFAULT_PHASE_SEG1  = 3'd5;
localparam bit [2:0] DEFAULT_PHASE_SEG2  = 3'd2;
localparam bit [1:0] DEFAULT_SJW         = 2'd2;

// --- Formato de mensagem (descritor do FIFO) ---
// msg[98:0] = { RTR[98], IDE[97], ID[96:68], DLC[67:64], DATA[63:0] }
localparam int CAN_ID_WIDTH   = 29;
localparam int CAN_DLC_WIDTH  = 4;
localparam int CAN_DATA_WIDTH = 64;
localparam int CAN_MSG_WIDTH  = 1 + 1 + CAN_ID_WIDTH + CAN_DLC_WIDTH + CAN_DATA_WIDTH; // 99

// --- Profundidades FIFO e filtros ---
localparam int CAN_FIFO_TX_DEPTH = 8;
localparam int CAN_FIFO_RX_DEPTH = 8;
localparam int CAN_NUM_FILTERS   = 4;

// --- Valores lógicos do barramento CAN ---
`define CAN_DOMINANT  1'b0   // dominante  (0)
`define CAN_RECESSIVE 1'b1   // recessivo  (1)

// --- CRC-15 ---
localparam bit [14:0] CAN_CRC_POLY = 15'h4599;

`endif // CAN_DEFINES_SVH

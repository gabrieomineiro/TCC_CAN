module can_error (
    input  logic        clk,
    input  logic        rst_n,
    
    // Entradas de erro
    input  logic        crc_error,
    input  logic        stuff_error,
    input  logic        ack_error,
    input  logic        form_error,
    input  logic        arbitration_lost,
    
    // Controle
    input  logic        error_reset,
    input  logic        increment_tec,
    input  logic        increment_rec,
    input  logic        decrement_rec,
    
    // Contadores
    output logic [7:0]  tec_counter,   // Transmit Error Counter
    output logic [7:0]  rec_counter,   // Receive Error Counter
    
    // Status
    output logic        error_active,  // < 128 TEC e REC
    output logic        error_passive, // >= 128 TEC ou REC
    output logic        bus_off        // >= 256 TEC
);

    // Internal variables
    logic [8:0] tec;
    logic [7:0] rec;
    logic        error_occurred;
    logic [2:0] error_state;
endmodule
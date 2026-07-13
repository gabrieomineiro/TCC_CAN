module can_controller_top #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 500_000
)(
    // Clock e Reset
    input  logic        clk,
    input  logic        rst_n,
    
    // APB/AXI Interface (para Register_File)
    input  logic [31:0] paddr,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,
    
    // CAN Bus Interface
    input  logic        can_rx,
    output logic        can_tx,
    
    // Interrupt
    output logic        interrupt
);

    // Internal variables
    logic [7:0]  prescaler;
    logic [2:0]  prop_seg, phase_seg1, phase_seg2;
    logic [1:0]  sjw;
    logic        sync_en, hard_sync;
    logic        bit_tick, sample_tick, tx_tick;
    logic        sample_point;
    logic        tx_start, tx_data, tx_ack, tx_eof;
    logic        rx_data, rx_ack, rx_eof;
    logic [31:0] tx_fifo_data, rx_fifo_data;
    logic        tx_fifo_wr, tx_fifo_full, tx_fifo_empty;
    logic        rx_fifo_wr, rx_fifo_full, rx_fifo_empty;
    logic        rx_fifo_rd, rx_fifo_rd_data_valid;
    logic [10:0] can_id;
    logic [3:0]  dlc;
    logic [63:0] can_data;
    logic        arbitration_lost;
    logic        crc_error, stuff_error, ack_error, form_error;
    logic        tec_counter, rec_counter;
    logic        error_active, error_passive, bus_off;
    logic [15:0] error_code;
    logic [31:0] reg_rd_data;
    logic        reg_wr_en, reg_rd_en;
    logic [3:0]  reg_addr;
    logic        rx_available, tx_ready, error_occurred;
endmodule
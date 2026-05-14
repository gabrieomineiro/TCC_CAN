module can_rx #(
    parameter DEPTH = 8,
    parameter WIDTH = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Interface de escrita (Protocol_FSM)
    input  logic                    wr_en,
    input  logic [WIDTH-1:0]       wr_data,
    output logic                    full,
    
    // Interface de leitura (CPU)
    input  logic                    rd_en,
    output logic [WIDTH-1:0]        rd_data,
    output logic                    empty,
    output logic                    rd_data_valid,
    
    // Status
    output logic [3:0]              fifo_count
);

    // Internal variables
    logic [WIDTH-1:0] mem [DEPTH-1:0];
    logic [3:0] wr_ptr, rd_ptr;
    logic [3:0] count;
endmodule
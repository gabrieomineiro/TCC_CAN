//-----------------------------------------------------------------------------
// Módulo: can_rx_fifo
// Descrição: FIFO de recepção para armazenar mensagens recebidas
//-----------------------------------------------------------------------------

module can_rx #(
    parameter DEPTH = 8,
    parameter WIDTH = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Interface de escrita (Protocol_FSM)
    input  logic                    wr_en,
    input  logic [WIDTH-1:0]        wr_data,
    output logic                    full,
    
    // Interface de leitura (CPU)
    input  logic                    rd_en,
    output logic [WIDTH-1:0]        rd_data,
    output logic                    empty,
    output logic                    rd_data_valid,
    
    // Status
    output logic [3:0]              fifo_count
);

    // Memory array
    logic [WIDTH-1:0] mem [DEPTH-1:0];
    
    // Pointers
    logic [2:0] wr_ptr, rd_ptr;
    logic [3:0] count;
    
    // Full condition
    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    assign fifo_count = count;
    assign rd_data_valid = !empty;
    
    // Write pointer logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 3'd0;
        end else if (wr_en && !full) begin
            wr_ptr <= wr_ptr + 3'd1;
        end
    end
    
    // Read pointer logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 3'd0;
        end else if (rd_en && !empty) begin
            rd_ptr <= rd_ptr + 3'd1;
        end
    end
    
    // Memory write
    always_ff @(posedge clk) begin
        if (wr_en && !full) begin
            mem[wr_ptr] <= wr_data;
        end
    end
    
    // Memory read
    assign rd_data = mem[rd_ptr];
    
    // Count logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 4'd0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: count <= count + 4'd1;  // Write only
                2'b01: count <= count - 4'd1;  // Read only
                default: count <= count;       // No change or simultaneous
            endcase
        end
    end

endmodule
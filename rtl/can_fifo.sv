//-----------------------------------------------------------------------------
// can_fifo
// FIFO síncrono genérico (message-based), usado para Tx e Rx.
// Semântica FWFT (first-word-fall-through): rdata sempre mostra o topo
// quando !empty; pop avança o ponteiro (síncrono).
//-----------------------------------------------------------------------------
module can_fifo #(
    parameter int MSG_W = 99,
    parameter int DEPTH  = 8,
    localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
)(
    input  logic             clk,
    input  logic             rst_n,

    // porta de escrita
    input  logic             push,
    input  logic [MSG_W-1:0] wdata,
    output logic             full,

    // porta de leitura
    input  logic             pop,
    output logic [MSG_W-1:0] rdata,
    output logic             empty,
    output logic             rdata_valid,   // = !empty (topo válido)

    // status
    output logic [PTR_W:0]   count
);

    logic [MSG_W-1:0] mem [DEPTH];
    logic [PTR_W-1:0] wr_ptr, rd_ptr;
    logic [PTR_W:0]   count_r;

    assign full        = (count_r == DEPTH);
    assign empty       = (count_r == 0);
    assign rdata       = mem[rd_ptr];
    assign rdata_valid = !empty;
    assign count       = count_r;

    wire do_push = push && !full;
    wire do_pop  = pop  && !empty;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= '0;
            rd_ptr  <= '0;
            count_r <= '0;
        end else begin
            if (do_push) begin
                mem[wr_ptr] <= wdata;
                wr_ptr      <= (wr_ptr == DEPTH-1) ? '0 : (wr_ptr + 1'b1);
            end
            if (do_pop) begin
                rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : (rd_ptr + 1'b1);
            end
            case ({do_push, do_pop})
                2'b10:   count_r <= count_r + 1'b1;
                2'b01:   count_r <= count_r - 1'b1;
                default: count_r <= count_r;
            endcase
        end
    end

endmodule

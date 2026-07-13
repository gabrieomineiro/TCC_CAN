//-----------------------------------------------------------------------------
// can_interrupt
// Agrega 8 fontes, aplica máscara (ien), mantém flags sticky (ifg) com clear
// write-1-to-clear (iclear). irq = |(ifg & ien).
// Bit map (consistente com CAN_IFG/CAN_IEN):
//   0 TX_DONE | 1 RX_AVAIL | 2 ERR_WARN | 3 ERR_PASSIVE
//   4 BUS_OFF | 5 ARB_LOST | 6 STUFF_ERR | 7 CRC_ERR
//-----------------------------------------------------------------------------
module can_interrupt (
    input  logic        clk,
    input  logic        rst_n,

    // fontes
    input  logic        src_tx_done,
    input  logic        src_rx_avail,
    input  logic        src_err_warn,
    input  logic        src_err_passive,
    input  logic        src_bus_off,
    input  logic        src_arb_lost,
    input  logic        src_stuff_err,
    input  logic        src_crc_err,

    input  logic [7:0]  ien,
    input  logic [7:0]  iclear,

    output logic [7:0]  ifg,
    output logic        irq
);

    logic [7:0] ifg_r;

    // vetor de fontes alinhado ao bit map
    wire [7:0] src_vec = {src_crc_err, src_stuff_err, src_arb_lost, src_bus_off,
                          src_err_passive, src_err_warn, src_rx_avail, src_tx_done};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)        ifg_r <= 8'h00;
        else               ifg_r <= (ifg_r | src_vec) & ~iclear;
    end

    assign ifg = ifg_r;
    assign irq = |(ifg_r & ien);

endmodule

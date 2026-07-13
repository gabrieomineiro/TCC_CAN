//-----------------------------------------------------------------------------
// can_arbitration
// Comparador bitwise do campo de Arbitration. NÃO drive o barramento.
// Em cada sample_tick (com arb_en): se transmitimos recessivo (1) e o bus
// está dominante (0), perdemos a arbitragem. Conta o bit em que ocorreu.
//-----------------------------------------------------------------------------
module can_arbitration (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        sample_tick,   // 1 pulso por bit (do BTU/FSM)
    input  logic        arb_en,        // 1 durante o campo de Arbitration
    input  logic        tx_bit,        // bit que transmitimos (do FSM)
    input  logic        rx_bit,        // bit amostrado no bus (do BSP)

    output logic        arb_lost,      // 1 = perdemos a arbitragem
    output logic        arb_active,    // 1 = ainda competindo
    output logic [5:0]  arb_lost_bit   // índice do bit em que perdemos
);

    logic       lost_r;
    logic [5:0] bit_cnt;
    logic [5:0] lost_bit_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lost_r     <= 1'b0;
            bit_cnt    <= 6'd0;
            lost_bit_r <= 6'd0;
        end else if (!arb_en) begin
            // fora do campo de arbitragem: reinicia
            lost_r     <= 1'b0;
            bit_cnt    <= 6'd0;
            lost_bit_r <= 6'd0;
        end else if (sample_tick && !lost_r) begin
            if (tx_bit && !rx_bit) begin   // tx recessivo (1), bus dominante (0)
                lost_r     <= 1'b1;
                lost_bit_r <= bit_cnt;
            end
            bit_cnt <= bit_cnt + 6'd1;
        end
    end

    assign arb_lost     = lost_r;
    assign arb_active   = arb_en && !lost_r;
    assign arb_lost_bit = lost_bit_r;

endmodule

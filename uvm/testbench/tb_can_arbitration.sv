//-----------------------------------------------------------------------------
// tb_can_arbitration — Testbench SIMPLES (smoke test, self-checking, nao-UVM)
// do can_arbitration.
//
// Cobre:
//   - Pós-reset: arb_lost=0, arb_active=0 (arb_en=0).
//   - Sem perda quando tx_bit sempre dominante (== rx_bit).
//   - Perda quando tx recessivo (1) e bus dominante (0) -> arb_lost=1 em
//     arb_lost_bit correto.
//   - arb_active cai quando lost.
//   - Reinicio quando arb_en volta a 0.
//
// Rodar (Xcelium):
//   xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
//        uvm/testbench/tb_can_arbitration.sv
// Icarus:
//   iverilog -g2012 -t null -f script/simlist_can.f uvm/testbench/tb_can_arbitration.sv
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_can_arbitration;

    logic        clk = 1'b0;
    logic        rst_n;
    logic        sample_tick, arb_en, tx_bit, rx_bit;
    logic        arb_lost, arb_active;
    logic [5:0]  arb_lost_bit;

    can_arbitration DUT (
        .clk(clk), .rst_n(rst_n),
        .sample_tick(sample_tick), .arb_en(arb_en),
        .tx_bit(tx_bit), .rx_bit(rx_bit),
        .arb_lost(arb_lost), .arb_active(arb_active), .arb_lost_bit(arb_lost_bit)
    );

    always #10 clk = ~clk;

    integer errors;

    task chk(input bit cond, input string msg);
        begin
            if (!cond) begin errors = errors + 1; $display("[TB] FAIL: %s", msg); end
            else         $display("[TB] OK:   %s", msg);
        end
    endtask

    // strobe: pulsa sample_tick por 1 ciclo
    task sample;
        begin
            @(negedge clk); sample_tick = 1'b1;
            @(negedge clk); sample_tick = 1'b0;
        end
    endtask

    initial begin
        $timeformat(-9, 3, " ns", 12);
        errors = 0;
        sample_tick = 1'b0; arb_en = 1'b0; tx_bit = 1'b0; rx_bit = 1'b0;

        $dumpfile("tb_can_arbitration.vcd");
        $dumpvars(0, tb_can_arbitration);

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("==========================================================");
        $display("[TB] tb_can_arbitration — smoke test");
        $display("==========================================================");

        // 1) Pós-reset com arb_en=0
        chk(arb_lost === 1'b0,       "arb_lost=0 pos-reset");
        chk(arb_active === 1'b0,     "arb_active=0 pos-reset (arb_en=0)");
        chk(arb_lost_bit === 6'd0,   "arb_lost_bit=0 pos-reset");

        // 2) arb_en=1, todo dominante e bus dominante -> não perde em 12 bits
        arb_en = 1'b1;
        tx_bit = 1'b0; rx_bit = 1'b0;
        for (int i = 0; i < 12; i++) begin
            sample;
            if (arb_lost !== 1'b0) begin
                errors = errors + 1;
                $display("[TB] FAIL: arb_lost=1 inesperado no bit %0d", i);
                i = 12;
            end
        end
        if (errors == 0)
            $display("[TB] OK:   12 bits dominantes -> sem perda");
        chk(arb_active === 1'b1,     "arb_active=1 enquanto competindo");

        // 3) Reinicia com arb_en=0 (checa no negedge p/ evitar race c/ always_ff)
        arb_en = 1'b0;
        @(negedge clk);
        chk(arb_lost === 1'b0,       "arb_lost reinicia quando arb_en=0");

        // 4) Perda: tx recessivo (1), bus dominante (0) no bit 5 (6º bit)
        arb_en = 1'b1;
        tx_bit = 1'b0; rx_bit = 1'b0;   // bits 0..4 dominantes (ganha)
        for (int i = 0; i < 5; i++) sample;
        chk(arb_lost === 1'b0,       "5 bits dominantes iniciais: sem perda");
        tx_bit = 1'b1; rx_bit = 1'b0;   // bit 5: perde
        sample;
        chk(arb_lost === 1'b1,       "bit 5 tx=1/rx=0 -> arb_lost=1");
        chk(arb_lost_bit === 6'd5,   "arb_lost_bit=5");
        chk(arb_active === 1'b0,     "arb_active=0 apos perda");
        // Continua competindo (perdeu) e o lost_bit não muda
        sample; sample;
        chk(arb_lost_bit === 6'd5,   "arb_lost_bit sticky (=5)");

        // 5) arb_en=0 reinicia lost_r (checa no negedge p/ evitar race)
        arb_en = 1'b0;
        @(negedge clk);
        chk(arb_lost === 1'b0,       "arb_lost reinicia quando arb_en desliga");

        $display("----------------------------------------------------------");
        if (errors == 0) $display("[TB] ===== SMOKE TEST PASS =====");
        else             $display("[TB] ===== SMOKE TEST FAIL (%0d erros) =====", errors);
        $display("----------------------------------------------------------");
        $finish;
    end

    initial begin
        #1ms;
        $display("[TB] TIMEOUT global (1 ms). Abortando.");
        $finish;
    end

endmodule

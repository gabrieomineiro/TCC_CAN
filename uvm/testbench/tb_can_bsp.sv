//-----------------------------------------------------------------------------
// tb_can_bsp — Testbench SIMPLES (smoke test, self-checking, nao-UVM) do
// can_bsp (Bit Stream Processor).
//
// O TB atua como BTU+FSM: gera bit_tick (início do bit) e sample_tick (ponto
// de amostragem), e fornece tx_bit/tx_valid/stuff_en. As capturas de can_tx
// e strobes são feitas no NEGEDGE após o posedge que processa o pulso, para
// evitar race com o always_ff (região NBA).
//
// Cobre:
//   - TX sem stuffing (bits alternados): can_tx segue tx_bit; 1 strobe
//     tx_bit_done por bit consumido.
//   - TX COM stuffing: 5 bits dominantes consecutivos -> no 6º bit-time o BSP
//     insere stuff-bit recessivo; tx_bit_done NÃO pulsa nesse bit-time.
//   - RX destuffing: stuff-bit válido descartado (sem rx_valid); 6 idênticos
//     em região stuffed -> stuff_error.
//   - OE libera quando tx_valid=0.
//
// Rodar (Xcelium):
//   xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
//        uvm/testbench/tb_can_bsp.sv
// Icarus:
//   iverilog -g2012 -t null -I rtl rtl/can_bsp.sv uvm/testbench/tb_can_bsp.sv
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_can_bsp;

    logic clk = 1'b0;
    logic rst_n;
    logic bit_tick, sample_tick;
    logic tx_bit, tx_valid, stuff_en;
    logic can_rx;
    logic can_tx, can_tx_oe;
    logic rx_bit, rx_valid, tx_bit_done;
    logic bit_to_crc, crc_bit_valid;
    logic stuff_error, bsp_busy;

    can_bsp DUT (
        .clk(clk), .rst_n(rst_n),
        .bit_tick(bit_tick), .sample_tick(sample_tick),
        .tx_bit(tx_bit), .tx_valid(tx_valid), .stuff_en(stuff_en),
        .can_rx(can_rx), .can_tx(can_tx), .can_tx_oe(can_tx_oe),
        .rx_bit(rx_bit), .rx_valid(rx_valid), .tx_bit_done(tx_bit_done),
        .bit_to_crc(bit_to_crc), .crc_bit_valid(crc_bit_valid),
        .stuff_error(stuff_error), .bsp_busy(bsp_busy)
    );

    always #10 clk = ~clk;

    integer errors;

    task chk(input bit cond, input string msg);
        begin
            if (!cond) begin errors = errors + 1; $display("[TB] FAIL: %s", msg); end
            else         $display("[TB] OK:   %s", msg);
        end
    endtask

    //---- TX bit-time: transmite 1 bit de protocolo (tx_valid=1) ----
    // Estrutura (cada '-' é meio ciclo):
    //   neg(bit_tick=1) | pos[always_ff processa] | neg(bit_tick=0, captura)
    //   depois alguns ciclos + sample_tick opcional
    task tx_bit_time(input logic b, input logic stuff_on,
                     output logic seen_tx, output logic seen_done);
        begin
            tx_bit = b; tx_valid = 1'b1; stuff_en = stuff_on;
            @(negedge clk); bit_tick = 1'b1;
            @(posedge clk);              // always_ff vê bit_tick=1
            @(negedge clk); bit_tick = 1'b0;
            // NBA já resolveu: oe_r/tx_out_r/tx_bit_done_r estão atualizados
            seen_tx   = can_tx;
            seen_done = tx_bit_done;
            // completa o bit-time (sample_tick no meio p/ completar TQs)
            repeat (2) @(posedge clk);
            @(negedge clk); sample_tick = 1'b1;
            @(posedge clk);
            @(negedge clk); sample_tick = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    //---- RX bit-time: o TB provê can_rx; o BSP amostra em sample_tick ----
    task rx_bit_time(input logic buslvl, input logic stuff_on,
                     output logic seen_rxbit, output logic seen_rxvalid,
                     output logic seen_stufferr);
        begin
            tx_valid = 1'b0; stuff_en = stuff_on; can_rx = buslvl;
            @(negedge clk); bit_tick = 1'b1;
            @(posedge clk);
            @(negedge clk); bit_tick = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk); sample_tick = 1'b1;
            @(posedge clk);              // always_ff vê sample_tick=1
            @(negedge clk); sample_tick = 1'b0;
            // NBA resolveu: rx_bit_r/rx_valid_r/stuff_error_r atualizados
            seen_rxbit    = rx_bit;
            seen_rxvalid  = rx_valid;
            seen_stufferr = stuff_error;
            repeat (2) @(posedge clk);
        end
    endtask

    logic seen_tx, seen_done, seen_rxb, seen_rxv, seen_se;

    initial begin
        $timeformat(-9, 3, " ns", 12);
        errors = 0;
        bit_tick = 1'b0; sample_tick = 1'b0;
        tx_bit = 1'b1; tx_valid = 1'b0; stuff_en = 1'b0;
        can_rx = 1'b1;

        $dumpfile("tb_can_bsp.vcd");
        $dumpvars(0, tb_can_bsp);

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("==========================================================");
        $display("[TB] tb_can_bsp — smoke test");
        $display("==========================================================");

        // 1) Pós-reset: ocioso, bus recessivo, OE=0
        chk(can_tx === 1'b1,    "can_tx recessivo pos-reset");
        chk(can_tx_oe === 1'b0, "can_tx_oe=0 pos-reset");
        chk(bsp_busy === 1'b0,  "bsp_busy=0 pos-reset");

        // 2) TX sem stuffing: seq 0,1,0,1 (alternada) -> não insere stuff-bit,
        //    1 tx_bit_done por bit. stuff_en=0 para garantir.
        $display("[TB] -- TX sem stuffing (alternado) --");
        for (int i = 0; i < 4; i++) begin
            logic b = i[0];   // 0,1,0,1
            tx_bit_time(b, 1'b0, seen_tx, seen_done);
            chk(seen_done === 1'b1, $sformatf("TX bit %0d: tx_bit_done pulsa", i));
            chk(seen_tx   === b,    $sformatf("TX bit %0d: can_tx == %b", i, b));
        end

        // 3) TX COM stuffing: 5 dominantes consecutivos com stuff_en=1
        //    -> no 6º bit-time, é esperado um stuff-bit (recessivo, oposto)
        //    inserido; nesse bit-time tx_bit_done NÃO pulsa.
        $display("[TB] -- TX com stuffing (5x dominante) --");
        // Reinicia a corrida com 1 recessivo para garantir contagem limpa:
        tx_bit_time(1'b1, 1'b0, seen_tx, seen_done);  // 1 recessivo (sem stuff)
        chk(seen_done === 1'b1, "1 recessivo inicial consumido");
        // Agora 5 dominantes com stuff_en=1
        for (int i = 0; i < 5; i++) begin
            tx_bit_time(1'b0, 1'b1, seen_tx, seen_done);
            chk(seen_tx   === 1'b0, $sformatf("TX dom %0d: can_tx dominante", i));
            chk(seen_done === 1'b1, $sformatf("TX dom %0d: tx_bit_done (bit consumido)", i));
        end
        // 6º bit-time: stuff-bit deve ser inserido (recessivo), sem consumir.
        // Próximo tx_bit continua dominante -> após stuff, drive dominante
        // novamente no bit seguinte.
        tx_bit = 1'b0; tx_valid = 1'b1; stuff_en = 1'b1;
        @(negedge clk); bit_tick = 1'b1;
        @(posedge clk);              // always_ff decide: consec==5, insere stuff
        @(negedge clk); bit_tick = 1'b0;
        chk(can_tx === 1'b1,     "TX: 6o bit-time insere stuff-bit recessivo");
        chk(tx_bit_done === 1'b0, "TX: stuff-bit NAO consome (tx_bit_done=0)");
        repeat (4) @(posedge clk);
        tx_valid = 1'b0;

        // 4) RX destuffing: stuff-bit válido é descartado (sem rx_valid).
        $display("[TB] -- RX destuffing --");
        // limpa estado: alguns recessivos (não conta para stuff em região stuff)
        for (int i = 0; i < 3; i++) rx_bit_time(1'b1, 1'b1, seen_rxb, seen_rxv, seen_se);
        // Agora 5 dominantes em região stuff -> no 6º bit-time entra stuff-bit
        for (int i = 0; i < 5; i++) begin
            rx_bit_time(1'b0, 1'b1, seen_rxb, seen_rxv, seen_se);
            chk(seen_rxv === 1'b1, $sformatf("RX dom %0d: rx_valid (bit normal)", i));
            chk(seen_rxb === 1'b0, $sformatf("RX dom %0d: rx_bit dominante", i));
        end
        // 6º bit: stuff-bit (recessivo) esperado -> descartado, sem rx_valid
        rx_bit_time(1'b1, 1'b1, seen_rxb, seen_rxv, seen_se);
        chk(seen_rxv === 1'b0, "RX stuff-bit recessivo: descartado (rx_valid=0)");
        chk(seen_se === 1'b0,  "RX stuff-bit valido: sem stuff_error");

        // 5) RX stuff error: 6 idênticos consecutivos em região stuffed
        $display("[TB] -- RX stuff error (6x dominante) --");
        for (int i = 0; i < 3; i++) rx_bit_time(1'b1, 1'b1, seen_rxb, seen_rxv, seen_se);
        // 5 dominantes normais + 1 extra = 6º -> stuff_error
        for (int i = 0; i < 5; i++)
            rx_bit_time(1'b0, 1'b1, seen_rxb, seen_rxv, seen_se);
        rx_bit_time(1'b0, 1'b1, seen_rxb, seen_rxv, seen_se);
        chk(seen_se === 1'b1, "RX 6 idênticos -> stuff_error");
        chk(seen_rxv === 1'b1, "RX stuff error ainda emite rx_valid");

        // 6) OE libera quando tx_valid=0
        tx_valid = 1'b0;
        @(negedge clk); bit_tick = 1'b1;
        @(posedge clk);
        @(negedge clk); bit_tick = 1'b0;
        chk(can_tx_oe === 1'b0, "tx_valid=0 em bit_tick -> OE=0 (libera bus)");
        repeat (4) @(posedge clk);

        $display("----------------------------------------------------------");
        if (errors == 0) $display("[TB] ===== SMOKE TEST PASS =====");
        else             $display("[TB] ===== SMOKE TEST FAIL (%0d erros) =====", errors);
        $display("----------------------------------------------------------");
        $finish;
    end

    initial begin
        #5ms;
        $display("[TB] TIMEOUT global (5 ms). Abortando.");
        $finish;
    end

endmodule

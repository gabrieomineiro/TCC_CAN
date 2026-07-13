//-----------------------------------------------------------------------------
// tb_can_interrupt — Testbench SIMPLES (smoke test, self-checking, nao-UVM)
// do can_interrupt (8 fontes, ien, sticky W1C).
//
// Bit map: 0 TX_DONE | 1 RX_AVAIL | 2 ERR_WARN | 3 ERR_PASSIVE
//          4 BUS_OFF | 5 ARB_LOST | 6 STUFF_ERR | 7 CRC_ERR
//
// Cobre:
//   - Pulsar cada fonte -> ifg correspondente.
//   - ien mascara irq (irq = |(ifg & ien)).
//   - W1C: iclear limpa apenas os bits escritos.
//   - Sticky: ifg mantém entre ciclos sem iclear.
//
// Rodar (Xcelium):
//   xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
//        uvm/testbench/tb_can_interrupt.sv
// Icarus:
//   iverilog -g2012 -t null -f script/simlist_can.f uvm/testbench/tb_can_interrupt.sv
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_can_interrupt;

    logic        clk = 1'b0;
    logic        rst_n;
    logic        src_tx_done, src_rx_avail, src_err_warn, src_err_passive;
    logic        src_bus_off, src_arb_lost, src_stuff_err, src_crc_err;
    logic [7:0]  ien;
    logic [7:0]  iclear;
    logic [7:0]  ifg;
    logic        irq;

    can_interrupt DUT (
        .clk(clk), .rst_n(rst_n),
        .src_tx_done(src_tx_done), .src_rx_avail(src_rx_avail),
        .src_err_warn(src_err_warn), .src_err_passive(src_err_passive),
        .src_bus_off(src_bus_off), .src_arb_lost(src_arb_lost),
        .src_stuff_err(src_stuff_err), .src_crc_err(src_crc_err),
        .ien(ien), .iclear(iclear),
        .ifg(ifg), .irq(irq)
    );

    always #10 clk = ~clk;

    integer errors;

    task chk(input bit cond, input string msg);
        begin
            if (!cond) begin errors = errors + 1; $display("[TB] FAIL: %s", msg); end
            else         $display("[TB] OK:   %s", msg);
        end
    endtask

    // 1 ciclo com uma fonte pulsada
    task pulse_tx_done;
        begin @(negedge clk); src_tx_done = 1'b1; @(negedge clk); src_tx_done = 1'b0; end
    endtask
    task pulse_src(input int b);
        begin
            @(negedge clk);
            case (b)
                0: src_tx_done     = 1'b1;
                1: src_rx_avail    = 1'b1;
                2: src_err_warn    = 1'b1;
                3: src_err_passive = 1'b1;
                4: src_bus_off     = 1'b1;
                5: src_arb_lost    = 1'b1;
                6: src_stuff_err   = 1'b1;
                7: src_crc_err     = 1'b1;
            endcase
            @(negedge clk);
            src_tx_done = 1'b0; src_rx_avail = 1'b0; src_err_warn = 1'b0;
            src_err_passive = 1'b0; src_bus_off = 1'b0; src_arb_lost = 1'b0;
            src_stuff_err = 1'b0; src_crc_err = 1'b0;
        end
    endtask

    task clear_bits(input logic [7:0] mask);
        begin
            @(negedge clk); iclear = mask;
            @(negedge clk); iclear = 8'h00;
        end
    endtask

    initial begin
        $timeformat(-9, 3, " ns", 12);
        errors = 0;
        src_tx_done = 1'b0; src_rx_avail = 1'b0; src_err_warn = 1'b0;
        src_err_passive = 1'b0; src_bus_off = 1'b0; src_arb_lost = 1'b0;
        src_stuff_err = 1'b0; src_crc_err = 1'b0;
        ien = 8'h00; iclear = 8'h00;

        $dumpfile("tb_can_interrupt.vcd");
        $dumpvars(0, tb_can_interrupt);

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("==========================================================");
        $display("[TB] tb_can_interrupt — smoke test");
        $display("==========================================================");

        // 1) Pós-reset: ifg=0, irq=0
        chk(ifg === 8'h00, "ifg=0 pos-reset");
        chk(irq === 1'b0,  "irq=0 pos-reset");

        // 2) Pulsar cada fonte isoladamente -> seta bit esperado
        for (int b = 0; b < 8; b++) begin
            clear_bits(8'hFF);          // garante ifg limpo
            pulse_src(b);
            @(posedge clk);
            chk(ifg[b] === 1'b1, $sformatf("fonte %0d seta ifg[%0d]", b, b));
            chk(ifg === (8'h01 << b),   $sformatf("ifg == (1<<%0d) isolado", b));
        end

        // 3) ien mascara irq
        clear_bits(8'hFF);
        pulse_tx_done;
        @(posedge clk);
        chk(ifg[0] === 1'b1, "ifg[0]=1 apos TX_DONE");
        chk(irq  === 1'b0,   "irq=0 com ien=0 (mascarado)");
        ien = 8'h01;
        @(posedge clk);
        chk(irq === 1'b1,    "irq=1 apos ien[0]=1");
        ien = 8'h00;
        @(posedge clk);
        chk(irq === 1'b0,    "irq=0 apos ien=0");

        // 4) W1C: limpa só bit escrito
        // Acumula TX_DONE (bit0) e CRC_ERR (bit7)
        clear_bits(8'hFF);
        pulse_src(0);   // TX_DONE
        pulse_src(7);   // CRC_ERR
        @(posedge clk);
        chk(ifg === 8'h81, "ifg == 0x81 (bits 0 e 7)");
        clear_bits(8'h01);   // limpa só bit 0
        @(posedge clk);
        chk(ifg === 8'h80, "W1C: ifg == 0x80 apos limpar bit 0");

        // 5) Sticky: mantém sem iclear
        @(posedge clk); @(posedge clk);
        chk(ifg === 8'h80, "ifg sticky mantido (0x80)");

        // 6) Limpa tudo
        clear_bits(8'hFF);
        @(posedge clk);
        chk(ifg === 8'h00, "ifg=0 apos clear 0xFF");

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

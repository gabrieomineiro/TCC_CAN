//-----------------------------------------------------------------------------
// tb_can_error — Testbench SIMPLES (smoke test, self-checking, nao-UVM) do
// can_error (EML: TEC/REC ISO, Error Active/Passive/Bus Off).
//
// Regras do RTL:
//   - erro TX (tx_context=1):    TEC += 8 (sat 256)
//   - erro RX (tx_context=0):    REC += 1 (sat 0xFF)
//   - frame_tx_ok:               TEC -= 1 (se 0 < TEC < 256)
//   - frame_rx_ok:               REC -= 1 (se REC > 0)
//   - err_reset:                 TEC=REC=0
//   - bus_off:                   TEC >= 256
//   - error_passive:             TEC >= 128 || REC >= 128
//
// Cobre:
//   - Incrementos TEC/REC, decrementos, saturações.
//   - Transições de estado Active -> Passive -> Bus Off.
//   - err_reset zera.
//
// Rodar (Xcelium):
//   xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
//        uvm/testbench/tb_can_error.sv
// Icarus:
//   iverilog -g2012 -t null -f script/simlist_can.f uvm/testbench/tb_can_error.sv
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_can_error;

    logic        clk = 1'b0;
    logic        rst_n;
    logic        bit_error, stuff_error, crc_error, ack_error, form_error;
    logic        tx_context, arb_lost;
    logic        frame_tx_ok, frame_rx_ok;
    logic        err_reset;
    logic [7:0]  tec, rec;
    logic        error_active, error_passive, bus_off, error_flag_req;

    can_error DUT (
        .clk(clk), .rst_n(rst_n),
        .bit_error(bit_error), .stuff_error(stuff_error), .crc_error(crc_error),
        .ack_error(ack_error), .form_error(form_error),
        .tx_context(tx_context), .arb_lost(arb_lost),
        .frame_tx_ok(frame_tx_ok), .frame_rx_ok(frame_rx_ok),
        .err_reset(err_reset),
        .tec(tec), .rec(rec),
        .error_active(error_active), .error_passive(error_passive),
        .bus_off(bus_off), .error_flag_req(error_flag_req)
    );

    always #10 clk = ~clk;

    integer errors;

    task chk(input bit cond, input string msg);
        begin
            if (!cond) begin errors = errors + 1; $display("[TB] FAIL: %s", msg); end
            else         $display("[TB] OK:   %s", msg);
        end
    endtask

    // Aplica um pulso de 1 ciclo de um erro TX (default bit_error)
    task tx_err_pulse;
        begin
            @(negedge clk);
            tx_context = 1'b1; bit_error = 1'b1;
            @(negedge clk);
            tx_context = 1'b0; bit_error = 1'b0;
        end
    endtask

    task rx_err_pulse;
        begin
            @(negedge clk);
            tx_context = 1'b0; crc_error = 1'b1;   // qualquer erro em RX
            @(negedge clk);
            crc_error = 1'b0;
        end
    endtask

    task tx_ok_pulse;
        begin
            @(negedge clk); frame_tx_ok = 1'b1;
            @(negedge clk); frame_tx_ok = 1'b0;
        end
    endtask

    task rx_ok_pulse;
        begin
            @(negedge clk); frame_rx_ok = 1'b1;
            @(negedge clk); frame_rx_ok = 1'b0;
        end
    endtask

    initial begin
        $timeformat(-9, 3, " ns", 12);
        errors = 0;
        bit_error = 1'b0; stuff_error = 1'b0; crc_error = 1'b0;
        ack_error = 1'b0; form_error = 1'b0;
        tx_context = 1'b0; arb_lost = 1'b0;
        frame_tx_ok = 1'b0; frame_rx_ok = 1'b0;
        err_reset = 1'b0;

        $dumpfile("tb_can_error.vcd");
        $dumpvars(0, tb_can_error);

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("==========================================================");
        $display("[TB] tb_can_error — smoke test");
        $display("==========================================================");

        // 1) Pós-reset: TEC=0, REC=0, Error Active
        chk(tec === 8'd0,            "tec=0 pos-reset");
        chk(rec === 8'd0,            "rec=0 pos-reset");
        chk(error_active === 1'b1,   "error_active=1 pos-reset");
        chk(error_passive === 1'b0,  "error_passive=0 pos-reset");
        chk(bus_off === 1'b0,        "bus_off=0 pos-reset");

        // 2) Erro TX: TEC += 8
        tx_err_pulse;
        @(posedge clk);
        chk(tec === 8'd8,            "1 erro TX -> TEC=8");
        tx_err_pulse; @(posedge clk);
        chk(tec === 8'd16,           "2 erros TX -> TEC=16");

        // 3) frame_tx_ok: TEC -= 1
        tx_ok_pulse; @(posedge clk);
        chk(tec === 8'd15,           "frame_tx_ok -> TEC=15");

        // 4) Erro RX: REC += 1
        rx_err_pulse; @(posedge clk);
        chk(rec === 8'd1,            "1 erro RX -> REC=1");
        rx_err_pulse; @(posedge clk);
        chk(rec === 8'd2,            "2 erros RX -> REC=2");

        // 5) frame_rx_ok: REC -= 1
        rx_ok_pulse; @(posedge clk);
        chk(rec === 8'd1,            "frame_rx_ok -> REC=1");

        // 6) error_flag_req acompanha any_err
        @(negedge clk); bit_error = 1'b1;
        @(posedge clk);
        #1;
        chk(error_flag_req === 1'b1, "error_flag_req=1 com bit_error");
        @(negedge clk); bit_error = 1'b0;
        @(posedge clk);
        #1;
        chk(error_flag_req === 1'b0, "error_flag_req=0 sem erros");

        // 7) err_reset zera TEC/REC
        @(negedge clk); err_reset = 1'b1;
        @(negedge clk); err_reset = 1'b0;
        @(posedge clk);
        chk(tec === 8'd0,            "err_reset -> TEC=0");
        chk(rec === 8'd0,            "err_reset -> REC=0");
        chk(error_active === 1'b1,   "err_reset -> Error Active");

        // 8) Error Passive: TEC >= 128 (16 erros TX * 8 = 128)
        for (int i = 0; i < 16; i++) tx_err_pulse;
        @(posedge clk);
        chk(tec === 8'd128,          "16 erros TX -> TEC=128");
        chk(error_passive === 1'b1,  "TEC>=128 -> Error Passive");
        chk(error_active === 1'b0,   "Error Active caiu");
        chk(bus_off === 1'b0,        "ainda nao Bus Off");

        // 9) Bus Off: TEC >= 256 (mais 16 erros TX -> 256)
        for (int i = 0; i < 16; i++) tx_err_pulse;
        @(posedge clk);
        chk(bus_off === 1'b1,         "TEC>=256 -> Bus Off");
        chk(error_passive === 1'b1,  "Bus Off -> Passive=1 (precedência)");
        chk(error_active === 1'b0,   "Bus Off -> Active=0");

        // 10) Saturação em 256 (não passa)
        tx_err_pulse; @(posedge clk);
        chk(tec === 8'd0,            "TEC sat 256 interno (output [7:0]=0)");
        chk(bus_off === 1'b1,        "Permanece Bus Off");

        // 11) REC saturação em 0xFF
        @(negedge clk); err_reset = 1'b1;
        @(negedge clk); err_reset = 1'b0; tx_context = 1'b0;
        @(posedge clk);
        for (int i = 0; i < 300; i++) rx_err_pulse;
        @(posedge clk);
        chk(rec === 8'hFF,           "REC satura em 0xFF");
        chk(error_passive === 1'b1,  "REC>=128 -> Passive");

        // 12) err_reset final
        @(negedge clk); err_reset = 1'b1;
        @(negedge clk); err_reset = 1'b0;
        @(posedge clk);
        chk(tec === 8'd0 && rec === 8'd0, "err_reset final zera tudo");
        chk(error_active === 1'b1,        "volta a Error Active");

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

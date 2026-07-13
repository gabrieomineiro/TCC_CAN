//-----------------------------------------------------------------------------
// tb_can_crc — Testbench SIMPLES (smoke test, self-checking, nao-UVM) do
// can_crc (CRC-15 bit-serial, poly 0x4599, LFSR init=0).
//
// Cobre:
//   - LFSR contra MODELO DE REFERENCIA bitwise (function) em SV, sobre
//     varias sequencias (todas 0, todas 1, padrao 0x123, aleatorio-rep).
//   - crc_clear zera o LFSR.
//   - check_strobe: rx_crc==crc_out -> crc_match=1; != -> crc_error=1
//     (sinais sticky mantidos apos o strobe).
//
// Rodar (Xcelium):
//   xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
//        uvm/testbench/tb_can_crc.sv
// Icarus:
//   iverilog -g2012 -t null -f script/simlist_can.f uvm/testbench/tb_can_crc.sv
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_can_crc;

    logic        clk = 1'b0;
    logic        rst_n;
    logic        crc_clear, crc_shift, bit_in;
    logic [14:0] crc_out;
    logic [14:0] rx_crc;
    logic        check_strobe;
    logic        crc_match, crc_error;

    can_crc DUT (
        .clk(clk), .rst_n(rst_n),
        .crc_clear(crc_clear), .crc_shift(crc_shift), .bit_in(bit_in),
        .crc_out(crc_out),
        .rx_crc(rx_crc), .check_strobe(check_strobe),
        .crc_match(crc_match), .crc_error(crc_error)
    );

    always #10 clk = ~clk;

    integer errors;

    // ---- Modelo de referência CRC-15 (poly 0x4599, init=0) ----
    function automatic bit [14:0] crc15_step(input bit [14:0] crc_in,
                                             input bit b);
        bit [14:0] crc = crc_in;
        if ((crc[0] ^ b) != 1'b0)
            crc = (crc >> 1) ^ 15'h4599;
        else
            crc = (crc >> 1);
        return crc;
    endfunction

    task chk(input bit cond, input string msg);
        begin
            if (!cond) begin errors = errors + 1; $display("[TB] FAIL: %s", msg); end
            else         $display("[TB] OK:   %s", msg);
        end
    endtask

    // Aplica uma sequência de bits e compara crc_out com o modelo.
    // seq_len = nº de bits; stream é empacotado MSB-first (bit mais
    // significativo é o primeiro transmitido).
    task run_stream(input int seq_len, input logic [63:0] stream);
        bit [14:0] crc_ref;     // modelo: init=0
        bit        mismatch;
        integer    i;
        bit        b;
        begin
            crc_ref  = 15'h0;
            mismatch = 1'b0;
            @(negedge clk);
            crc_clear = 1'b1;          // zera LFSR e modelo
            @(negedge clk);
            crc_clear = 1'b0;
            // processa seq_len bits MSB-first
            for (i = 0; i < seq_len; i = i + 1) begin
                b = stream[63 - (i % 64)];   // repete padrão se i>=64
                @(negedge clk);
                bit_in = b; crc_shift = 1'b1;
                crc_ref = crc15_step(crc_ref, b);
                @(negedge clk);
                crc_shift = 1'b0;
                // neste momento crc_out já reflete o passo (registrado)
                if (crc_out !== crc_ref && !mismatch) begin
                    mismatch = 1'b1;
                    errors = errors + 1;
                    $display("[TB] FAIL: CRC mismatch no bit %0d (DUT=%h REF=%h)",
                             i, crc_out, crc_ref);
                end
            end
            if (!mismatch)
                $display("[TB] OK:   CRC bateu em %0d bits (final=%h)",
                         seq_len, crc_out);
        end
    endtask

    initial begin
        $timeformat(-9, 3, " ns", 12);
        errors = 0;
        crc_clear = 1'b0; crc_shift = 1'b0; bit_in = 1'b0;
        rx_crc = 15'h0; check_strobe = 1'b0;

        $dumpfile("tb_can_crc.vcd");
        $dumpvars(0, tb_can_crc);

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("==========================================================");
        $display("[TB] tb_can_crc — smoke test");
        $display("==========================================================");

        // 1) Pós-reset: LFSR=0
        chk(crc_out === 15'h0, "crc_out=0 pos-reset");

        // 2) Sequências variadas contra modelo de referência
        run_stream(19, {64'h0});                 // ARB 11-bit + CTRL 6 + DATA0 2 (ex.)
        run_stream(64, 64'hFFFFFFFFFFFFFFFF);    // tudo recessivo
        run_stream(64, 64'h0123456789ABCDEF);
        run_stream(47, 64'hA5A5A5A5A5A5A5A5);    // SOF+ARB+CTRL+DATA(3 bytes) approx
        run_stream(16, 64'h00000000000000FF);

        // 3) crc_clear zera no meio de uma corrida
        @(negedge clk);
        crc_clear = 1'b1; bit_in = 1'b0; crc_shift = 1'b0;
        @(negedge clk);
        crc_clear = 1'b0;
        @(posedge clk);
        chk(crc_out === 15'h0, "crc_clear zera o LFSR");

        // 4) check_strobe -> crc_match / crc_error (sticky)
        // Prepara: após uma sequência conhecida, strobe com rx_crc igual e != .
        run_stream(16, 64'hFACEFACEFACEFACE);    // deixa crc_out num valor X
        @(negedge clk);
        rx_crc = crc_out;                         // deve casar
        check_strobe = 1'b1;
        @(negedge clk);
        check_strobe = 1'b0;
        @(posedge clk);
        chk(crc_match === 1'b1,  "check_strobe rx_crc==crc_out -> crc_match=1");
        chk(crc_error === 1'b0,  "...                            crc_error=0");

        @(negedge clk);
        rx_crc = ~crc_out;                        // não casa
        check_strobe = 1'b1;
        @(negedge clk);
        check_strobe = 1'b0;
        @(posedge clk);
        chk(crc_match === 1'b0,  "check_strobe rx_crc!=crc_out -> crc_match=0");
        chk(crc_error === 1'b1,  "...                            crc_error=1");

        // 5) Sticky: sem strobe, mantém
        @(negedge clk);
        @(posedge clk);
        chk(crc_error === 1'b1,  "crc_error sticky mantido sem novo strobe");

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

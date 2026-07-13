//-----------------------------------------------------------------------------
// tb_can_top  — Testbench de sistema SIMPLES (smoke test) do can_top.
//
// Subset coberto (HANDS_ON.md, Passo 2): data frame padrão 11-bit em TX, com
// ACK devolvido por um modelo de bus mínimo. Não-UVM por ora — o objetivo é
// ganhar confiança do subset TX/RX e EXPOR bugs de temporização/protocolo antes
// de investir no env UVM. Simulador-alvo: Xcelium (xrun).
//
// Modelo de bus:
//   - Reflexão TX->RX: can_rx segue can_tx quando can_tx_oe ativo (wired-AND:
//     dominante=0 vence). Necessário para arbitragem e bit-error detection.
//   - ACK responder "state-aware" (TB de fumaça): drive dominante durante o
//     bit-time em que o FSM interno está em TX_ACK. Um env UVM usaria um
//     receptor autônomo completo (re-implementando BTU/destuffing).
//
// Notas:
//   - Acessa sinais internos do DUT via referência hierárquica
//     (DUT.u_fsm.state). Requer xrun com -access +rwc (já no simlist_can.f).
//   - Bugs do RTL (ex.: off-by-one na amostragem do ACK) vão aparecer como
//     TX nunca concluída / TEC subindo / IFG.TX_DONE não setado.
//
// Rodar (Xcelium, a partir da raiz do projeto):
//   xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
//        uvm/testbench/tb_can_top.sv
//
// Syntax-check rápido (Icarus, Windows — NÃO é o simulador-alvo):
//   iverilog -g2012 -t null -f script/simlist_can.f uvm/testbench/tb_can_top.sv
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_can_top;

    //==========================================================================
    // Clock & reset
    //==========================================================================
    logic clk;
    logic rst_n;
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;   // 50 MHz (período 20 ns)
    end

    //==========================================================================
    // Sinais APB + CAN bus
    //==========================================================================
    logic [31:0] paddr, pwdata, prdata;
    logic        psel, penable, pwrite, pready, pslverr;
    logic        can_rx, can_tx, can_tx_oe, irq;

    //==========================================================================
    // DUT
    //==========================================================================
    can_top #(
        .CLK_FREQ_HZ(50_000_000),
        .BAUD_RATE  (500_000)
    ) DUT (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
        .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .can_rx(can_rx), .can_tx(can_tx), .can_tx_oe(can_tx_oe), .irq(irq)
    );

    //==========================================================================
    // Modelo de bus: reflexão TX->RX + ACK responder state-aware
    //==========================================================================
    localparam logic DOM = 1'b0;   // dominante (CAN é wired-AND)
    localparam logic REC = 1'b1;   // recessivo

    // Estado do FSM interno (TB de fumaça state-aware). IDs em can_fsm.sv:
    // TX_CRCDEL=6'd6, TX_ACK=6'd7. A janela cobre o bit-time esperado do ACK.
    wire [5:0] fsm_st = DUT.u_fsm.state;

    // ACK responder: drive dominante durante TX_ACK (e TX_CRCDEL por margem,
    // já que o transmissor não se auto-verifica no CRCdel).
    logic ack_drv;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) ack_drv <= 1'b0;
        else        ack_drv <= (fsm_st == 6'd6) || (fsm_st == 6'd7);
    end

    // Bus físico wired-AND: DUT drive via can_tx_oe; ACK responder sobrepõe.
    wire bus_from_dut = can_tx_oe ? can_tx : REC;
    assign can_rx = ack_drv ? DOM : bus_from_dut;

    //==========================================================================
    // Mapa de registradores (offsets — ver Docs/specs/01)
    //==========================================================================
    localparam logic [31:0] A_MOD      = 32'h00;
    localparam logic [31:0] A_BTR      = 32'h04;
    localparam logic [31:0] A_TCTRL    = 32'h08;
    localparam logic [31:0] A_TID      = 32'h0C;
    localparam logic [31:0] A_TDLC     = 32'h10;
    localparam logic [31:0] A_TDA      = 32'h14;
    localparam logic [31:0] A_TDB      = 32'h18;
    localparam logic [31:0] A_RCTRL    = 32'h1C;
    localparam logic [31:0] A_STAT     = 32'h30;
    localparam logic [31:0] A_ERR      = 32'h34;
    localparam logic [31:0] A_IEN      = 32'h38;
    localparam logic [31:0] A_IFG      = 32'h3C;
    localparam logic [31:0] A_FILT0C   = 32'h40;
    localparam logic [31:0] A_FILT0M   = 32'h44;
    localparam logic [31:0] A_FILT_EN  = 32'h60;
    localparam logic [31:0] A_RESERVED = 32'h64;   // acima de 0x60 -> pslverr

    //==========================================================================
    // Tarefas APB (handshake PSEL->PENABLE->PREADY, 1 wait-state)
    //==========================================================================
    task apb_write(input logic [31:0] a, input logic [31:0] d);
        begin
            @(posedge clk);
            paddr  = a;  pwdata = d;  psel = 1'b1;  penable = 1'b0;  pwrite = 1'b1;
            @(posedge clk);
            penable = 1'b1;
            @(posedge clk);                          // pready=1
            psel = 1'b0;  penable = 1'b0;  pwrite = 1'b0;  paddr = '0;  pwdata = '0;
            @(posedge clk);
        end
    endtask

    task apb_read(input logic [31:0] a, output logic [31:0] d);
        begin
            @(posedge clk);
            paddr = a;  psel = 1'b1;  penable = 1'b0;  pwrite = 1'b0;
            @(posedge clk);
            penable = 1'b1;
            @(posedge clk);
            d = prdata;
            psel = 1'b0;  penable = 1'b0;  paddr = '0;
            @(posedge clk);
        end
    endtask

    //==========================================================================
    // Monitor de transições do FSM (debug — confirma SOF->ARB->...->EOF)
    //==========================================================================
    logic [5:0] fsm_st_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_st_prev <= 6'd0;
        end else if (fsm_st != fsm_st_prev) begin
            $display("[@%0t] FSM %0d -> %0d", $time, fsm_st_prev, fsm_st);
            fsm_st_prev <= fsm_st;
        end
    end

    //==========================================================================
    // Espera o FSM atingir um estado-alvo, com timeout. Retorna ok=1 se ok.
    //==========================================================================
    task wait_fsm(input logic [5:0] target, input integer timeout_cycles,
                  output bit ok);
        integer i;
        begin
            ok = 1'b0;
            for (i = 0; i < timeout_cycles; i = i + 1) begin
                @(posedge clk);
                if (fsm_st == target) begin ok = 1'b1; i = timeout_cycles; end
            end
        end
    endtask

    //==========================================================================
    // Test sequence
    //==========================================================================
    logic [31:0] rdata;
    integer      errors;
    bit          ok;

    initial begin
        $timeformat(-9, 3, " ns", 12);
        errors = 0;
        psel = 1'b0; penable = 1'b0; pwrite = 1'b0; paddr = '0; pwdata = '0;

        $dumpfile("tb_can_top.vcd");
        $dumpvars(0, tb_can_top);

        // ---- Reset ----
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("==========================================================");
        $display("[TB] tb_can_top — smoke test (subset 11-bit TX)");
        $display("==========================================================");

        // ---- 1) Readback pós-reset (checa APB read path) ----
        apb_read(A_BTR, rdata);
        $display("[TB] BTR      (reset) = 0x%08x (esperado 0x0022520A)", rdata);
        if (rdata !== 32'h0022520A) begin
            errors = errors + 1;
            $display("[TB]   FAIL: readback BTR pos-reset");
        end
        apb_read(A_FILT_EN, rdata);
        $display("[TB] FILT_EN (reset) = 0x%08x (esperado 0x00000000)", rdata);
        if (rdata !== 32'h00000000) begin
            errors = errors + 1;
            $display("[TB]   FAIL: readback FILT_EN pos-reset");
        end

        // ---- 2) pslverr em endereço reservado ----
        apb_read(A_RESERVED, rdata);
        $display("[TB] RD 0x64 -> prdata=0x%08x pslverr=%0d (esperado pslverr=1)",
                 rdata, pslverr);
        if (pslverr !== 1'b1) begin
            errors = errors + 1;
            $display("[TB]   FAIL: pslverr nao asserted em endereco reservado");
        end

        // ---- 3) Configura controlador ----
        $display("[TB] Configurando controlador...");
        apb_write(A_BTR,     32'h0022520A);   // default 500 kbps @50 MHz
        apb_write(A_FILT0C,  32'h00000000);   // filtro 0: code ID=0, IDE=0
        apb_write(A_FILT0M,  32'h00000000);   // filtro 0: mask=0 (casa tudo)
        apb_write(A_FILT_EN, 32'h00000001);   // habilita filtro 0
        apb_write(A_IEN,     32'h00000001);   // habilita IRQ TX_DONE
        apb_write(A_MOD,     32'h00000001);   // CAN_EN = 1

        apb_read(A_MOD, rdata);
        $display("[TB] MOD (CAN_EN) = 0x%08x (esperado 0x00000001)", rdata);
        if (rdata[0] !== 1'b1) begin
            errors = errors + 1;
            $display("[TB]   FAIL: CAN_EN nao setado");
        end

        // ---- 4) Programa TX: ID=0x123, DLC=1, byte0=0xA5 ----
        apb_write(A_TID,   32'h00000123);     // ID=0x123, IDE=0, RTR=0
        apb_write(A_TDLC,  32'h00000001);     // DLC=1
        apb_write(A_TDA,   32'h000000A5);     // byte0 = 0xA5
        apb_write(A_TDB,   32'h00000000);
        apb_write(A_TCTRL, 32'h00000001);     // TXREQ -> push Tx FIFO
        $display("[TB] TX programada: ID=0x123 DLC=1 DATA[0]=0xA5");

        // ---- 5) Espera TX iniciar (FSM sai de IDLE) ----
        // IDLE precisa de >=11 bits recessivos (~1100 ciclos) antes de TX.
        begin : wait_start
            integer i; bit started;
            started = 1'b0;
            for (i = 0; i < 8000; i = i + 1) begin
                @(posedge clk);
                if (fsm_st != 6'd0) begin
                    started = 1'b1;
                    $display("[TB] TX iniciou (FSM saiu de IDLE) @%0t", $time);
                    i = 8000;
                end
            end
            if (!started) begin
                errors = errors + 1;
                $display("[TB] FAIL: TX nunca iniciou (timeout).");
            end
        end

        // ---- 6) Espera TX concluir (FSM volta a IDLE) ----
        // Frame ~47 bits * 100 ciclos + overhead; 60000 ciclos cobre com folga.
        begin : wait_end
            integer i; bit done_f;
            done_f = 1'b0;
            for (i = 0; i < 60000; i = i + 1) begin
                @(posedge clk);
                if (fsm_st == 6'd0) begin
                    done_f = 1'b1;
                    $display("[TB] FSM voltou a IDLE @%0t", $time);
                    i = 60000;
                end
            end
            if (!done_f) begin
                errors = errors + 1;
                $display("[TB] FAIL: TX nao concluiu (timeout).");
            end
        end

        // ---- 7) Leitura final de status ----
        apb_read(A_STAT, rdata);
        $display("[TB] STAT (pos-TX) = 0x%08x", rdata);
        apb_read(A_IFG, rdata);
        $display("[TB] IFG  (pos-TX) = 0x%08x (bit0 = TX_DONE)", rdata);
        apb_read(A_ERR, rdata);
        $display("[TB] ERR  (pos-TX) = TEC=%0d REC=%0d", rdata[7:0], rdata[15:8]);

        // ---- 8) Checagens ----
        apb_read(A_IFG, rdata);
        if (rdata[0] !== 1'b1) begin
            errors = errors + 1;
            $display("[TB] FAIL: TX_DONE (IFG[0]) nao setado.");
        end else begin
            $display("[TB] OK: TX_DONE setado.");
        end

        apb_read(A_ERR, rdata);
        if (rdata[7:0] !== 8'd0) begin
            $display("[TB] WARN: TEC=%0d apos TX (esperado 0 se ACK OK).",
                     rdata[7:0]);
        end

        // --------------------------------------------------
        $display("----------------------------------------------------------");
        if (errors == 0) $display("[TB] ===== SMOKE TEST PASS =====");
        else             $display("[TB] ===== SMOKE TEST FAIL (%0d erros) =====", errors);
        $display("----------------------------------------------------------");
        $finish;
    end

    //==========================================================================
    // Watchdog global
    //==========================================================================
    initial begin
        #50ms;
        $display("[TB] TIMEOUT global (50 ms). Abortando.");
        $finish;
    end

endmodule

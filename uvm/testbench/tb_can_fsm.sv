//-----------------------------------------------------------------------------
// tb_can_fsm — Testbench SIMPLES (smoke test, self-checking, nao-UVM) do
// can_fsm (Frame Sequencer, subset data frame padrão 11-bit).
//
// Estratégia: o TB atua como BTU+BSP, fornecendo bit_tick/sample_tick e os
// strobes por bit de protocolo (tx_bit_done em TX, rx_valid em RX). Um
// "driver" reativo ao estado do FSM (lido via referência hierárquica) gera
// o estímulo correto por estado. Objetivo: exercitar o fluxo TX 11-bit
// (IDLE->SOF->ARB->CTRL->DATA->CRCSEQ->CRCDEL->ACK->ACKDEL->EOF->INTERMISSION
// ->IDLE) e confirmar int_tx_done/tx_pop.
//
// Cobre:
//   - Inicia TX após >=11 recessivos em IDLE (bus livre).
//   - Avança por tx_bit_done em TX_SOF/ARB/CTRL/DATA/CRCSEQ/CRCDEL/ACKDEL/
//     EOF/INTERMISSION.
//   - Em TX_ACK: sample_tick captura ACK dominante (rx_bit=0) -> sem erro.
//   - frame_tx_ok + int_tx_done + tx_pop ao final de TX_INTERMISSION.
//
// NÃO cobre (subset): RX, error frame, frames estendidos, RTR.
//
// Rodar (Xcelium, com -access +rwc para acessar DUT.state):
//   xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
//        uvm/testbench/tb_can_fsm.sv
// Icarus:
//   iverilog -g2012 -t null -f script/simlist_can.f uvm/testbench/tb_can_fsm.sv
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_can_fsm;

    //==================================================================
    // Clock / reset
    //==================================================================
    logic clk = 1'b0;
    logic rst_n;
    always #10 clk = ~clk;

    //==================================================================
    // Sinais do DUT
    //==================================================================
    logic        can_en;
    logic        fsm_busy;

    // BTU (mock)
    logic        bit_tick, sample_tick, tx_tick;
    logic        sync_locked;
    logic        sync_en, hard_sync;

    // BSP (mock strobes)
    logic        bsp_tx_bit, bsp_tx_valid, stuff_en;
    logic        rx_bit, rx_valid, stuff_error;
    logic        tx_bit_done;

    // CRC
    logic        crc_clear, crc_shift;
    logic [14:0] crc_out;
    wire  [14:0] rx_crc;          // SAÍDA do FSM (gerada em RX_CRCSEQ); não drive
    logic        crc_match, crc_error;
    logic        check_strobe;

    // Arbitration
    logic        arb_en, arb_lost;
    logic [5:0]  arb_lost_bit;

    // Tx FIFO
    logic        tx_pop;
    logic [98:0] tx_msg;
    logic        tx_empty;

    // Rx FIFO
    logic        rx_push;
    logic [98:0] rx_msg;
    logic        rx_full;

    // Acceptance
    logic [28:0] flt_id;
    logic        flt_ide, flt_check, flt_accept;

    // EML
    logic        e_bit_err, e_stuff_err, e_crc_err, e_ack_err, e_form_err;
    logic        tx_context, frame_tx_ok, frame_rx_ok;
    logic        error_active, error_passive, bus_off, error_flag_req;

    // Interrupt
    logic        int_tx_done, int_rx_avail, int_arb_lost, int_stuff_err, int_crc_err;

    logic [5:0]  fsm_state;

    can_fsm DUT (
        .clk(clk), .rst_n(rst_n),
        .can_en(can_en), .fsm_busy(fsm_busy),
        .bit_tick(bit_tick), .sample_tick(sample_tick), .tx_tick(tx_tick),
        .sync_locked(sync_locked), .sync_en(sync_en), .hard_sync(hard_sync),
        .bsp_tx_bit(bsp_tx_bit), .bsp_tx_valid(bsp_tx_valid), .stuff_en(stuff_en),
        .rx_bit(rx_bit), .rx_valid(rx_valid), .stuff_error(stuff_error),
        .tx_bit_done(tx_bit_done),
        .crc_clear(crc_clear), .crc_shift(crc_shift),
        .crc_out(crc_out), .crc_match(crc_match), .crc_error(crc_error),
        .rx_crc(rx_crc), .check_strobe(check_strobe),
        .arb_en(arb_en), .arb_lost(arb_lost), .arb_lost_bit(arb_lost_bit),
        .tx_pop(tx_pop), .tx_msg(tx_msg), .tx_empty(tx_empty),
        .rx_push(rx_push), .rx_msg(rx_msg), .rx_full(rx_full),
        .flt_id(flt_id), .flt_ide(flt_ide), .flt_check(flt_check), .flt_accept(flt_accept),
        .e_bit_err(e_bit_err), .e_stuff_err(e_stuff_err), .e_crc_err(e_crc_err),
        .e_ack_err(e_ack_err), .e_form_err(e_form_err),
        .tx_context(tx_context), .frame_tx_ok(frame_tx_ok), .frame_rx_ok(frame_rx_ok),
        .error_active(error_active), .error_passive(error_passive),
        .bus_off(bus_off), .error_flag_req(error_flag_req),
        .int_tx_done(int_tx_done), .int_rx_avail(int_rx_avail),
        .int_arb_lost(int_arb_lost), .int_stuff_err(int_stuff_err),
        .int_crc_err(int_crc_err),
        .fsm_state(fsm_state)
    );

    //==================================================================
    // Estados do FSM (espelha can_fsm.sv) — só para legibilidade do driver
    //==================================================================
    localparam logic [5:0] IDLE              = 6'd0;
    localparam logic [5:0] TX_SOF            = 6'd1;
    localparam logic [5:0] TX_ARB            = 6'd2;
    localparam logic [5:0] TX_CTRL           = 6'd3;
    localparam logic [5:0] TX_DATA           = 6'd4;
    localparam logic [5:0] TX_CRCSEQ         = 6'd5;
    localparam logic [5:0] TX_CRCDEL         = 6'd6;
    localparam logic [5:0] TX_ACK            = 6'd7;
    localparam logic [5:0] TX_ACKDEL         = 6'd8;
    localparam logic [5:0] TX_EOF            = 6'd9;
    localparam logic [5:0] TX_INTERMISSION   = 6'd10;

    //==================================================================
    // Estado interno do FSM (referência hierárquica — só leitura)
    //==================================================================
    wire [5:0] st = DUT.state;

    //==================================================================
    // Parâmetros do driver (timing do mock)
    //==================================================================
    localparam int NCYC = 8;       // ciclos de clock por bit-time
    localparam int HALF = NCYC/2;

    bit cfg_done = 1'b0;

    integer errors;
    logic [5:0] st_prev;
    integer n_tx_done;
    integer n_tx_pop;
    integer visited_sof, visited_eof;

    task chk(input bit cond, input string msg);
        begin
            if (!cond) begin errors = errors + 1; $display("[TB] FAIL: %s", msg); end
            else         $display("[TB] OK:   %s", msg);
        end
    endtask

    //==================================================================
    // Driver reativo ao estado: gera bit_tick + strobes por bit-time
    //==================================================================
    initial begin: driver
        bit_tick = 1'b0; sample_tick = 1'b0; tx_tick = 1'b0;
        tx_bit_done = 1'b0;
        rx_bit = 1'b1; rx_valid = 1'b0;     // bus recessivo por padrão
        stuff_error = 1'b0;
        wait (cfg_done);
        forever begin
            @(negedge clk);
            case (st)
                // -------- IDLE: fornece 1 bit recessivo (rx_valid) por bit-time
                IDLE: begin
                    bit_tick = 1'b1;
                    rx_bit = 1'b1; rx_valid = 1'b1;
                    @(negedge clk);
                    bit_tick = 1'b0; rx_valid = 1'b0;
                    repeat (NCYC-2) @(posedge clk);
                end

                // -------- TX_ACK: sample_tick com rx_bit dominante (ACK OK)
                TX_ACK: begin
                    bit_tick = 1'b1;
                    @(negedge clk);
                    bit_tick = 1'b0;
                    repeat (HALF-1) @(posedge clk);
                    rx_bit = 1'b0;                 // ACK dominante
                    sample_tick = 1'b1;
                    @(negedge clk);
                    sample_tick = 1'b0;
                    rx_bit = 1'b1;                 // volta a recessivo
                    repeat (HALF-1) @(posedge clk);
                end

                // -------- qualquer outro estado TX: tx_bit_done no meio do bit
                default: begin
                    bit_tick = 1'b1;
                    @(negedge clk);
                    bit_tick = 1'b0;
                    repeat (HALF-1) @(posedge clk);
                    tx_bit_done = 1'b1;
                    @(negedge clk);
                    tx_bit_done = 1'b0;
                    repeat (HALF-1) @(posedge clk);
                end
            endcase
        end
    end

    //==================================================================
    // Monitor de transições do FSM (log + contagem)
    //==================================================================
    initial begin: mon
        st_prev = IDLE;
        visited_sof = 0; visited_eof = 0;
        forever begin
            @(posedge clk);
            if (st !== st_prev) begin
                $display("[@%0t] FSM %0d -> %0d", $time, st_prev, st);
                if (st == TX_SOF)          visited_sof = visited_sof + 1;
                if (st == TX_INTERMISSION) visited_eof = visited_eof + 1;
                st_prev = st;
            end
        end
    end

    //==================================================================
    // Stimulus / checagens
    //==================================================================
    initial begin: stim
        $timeformat(-9, 3, " ns", 12);
        errors = 0; n_tx_done = 0; n_tx_pop = 0;

        $dumpfile("tb_can_fsm.vcd");
        $dumpvars(0, tb_can_fsm);

        // ---- Reset ----
        rst_n = 1'b0;
        // inputs "quietos"
        can_en = 1'b0;
        tx_empty = 1'b1;
        tx_msg = 99'b0;
        rx_full = 1'b0;
        flt_accept = 1'b1;
        crc_out = 15'h0;
        crc_match = 1'b1; crc_error = 1'b0;
        arb_lost = 1'b0; arb_lost_bit = 6'd0;
        error_active = 1'b1; error_passive = 1'b0; bus_off = 1'b0;
        error_flag_req = 1'b0;
        sync_locked = 1'b0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("==========================================================");
        $display("[TB] tb_can_fsm — smoke test (TX 11-bit, ACK OK)");
        $display("==========================================================");

        // 1) Pós-reset: em IDLE
        chk(st === IDLE, "pós-reset em IDLE");
        chk(fsm_busy === 1'b0, "fsm_busy=0 em IDLE");

        // 2) Habilita CAN + programa TX
        //    descritor: {RTR[98]=0, IDE[97]=0, ID[96:68]=0x123, DLC[67:64]=1, DATA[63:0]=0xA5}
        tx_msg   = {1'b0, 1'b0, 29'h00000123, 4'h1, 64'h00000000000000A5};
        tx_empty = 1'b0;
        can_en   = 1'b1;
        cfg_done = 1'b1;             // libera o driver

        // 3) Espera o FSM sair de IDLE (até ~20 bit-times de folga)
        begin: wait_start
            integer i; bit started;
            started = 1'b0;
            for (i = 0; i < 2000; i = i + 1) begin
                @(posedge clk);
                if (st !== IDLE) begin
                    started = 1'b1;
                    $display("[TB] TX iniciou @%0t (st=%0d)", $time, st);
                    i = 2000;
                end
            end
            chk(started === 1'b1, "TX iniciou apos >=11 recessivos em IDLE");
        end

        // 4) Conta int_tx_done / tx_pop e espera TX concluir (voltar a IDLE
        //    após ter passado por TX_INTERMISSION)
        begin: wait_done
            integer i;
            bit done;
            done = 1'b0;
            for (i = 0; i < 100000 && !done; i = i + 1) begin
                @(posedge clk);
                if (int_tx_done) n_tx_done = n_tx_done + 1;
                if (tx_pop)      n_tx_pop   = n_tx_pop   + 1;
                if (st === IDLE && visited_eof > 0) done = 1'b1;
            end
            chk(done === 1'b1, "TX concluiu (voltou a IDLE apos INTERMISSION)");
        end

        // pequena folga para os pulsos registrarem
        repeat (5) @(posedge clk);

        // 5) Checagens finais
        chk(n_tx_done >= 1, $sformatf("int_tx_done pulsou (visto %0d)", n_tx_done));
        chk(n_tx_pop   >= 1, $sformatf("tx_pop pulsou (visto %0d)", n_tx_pop));
        chk(visited_sof >= 1, "passou por TX_SOF");
        chk(visited_eof >= 1, "passou por TX_INTERMISSION");
        chk(st === IDLE,      "voltou a IDLE apos TX");

        $display("----------------------------------------------------------");
        if (errors == 0) $display("[TB] ===== SMOKE TEST PASS =====");
        else             $display("[TB] ===== SMOKE TEST FAIL (%0d erros) =====", errors);
        $display("----------------------------------------------------------");
        $finish;
    end

    //==================================================================
    // Watchdog global
    //==================================================================
    initial begin
        #10ms;
        $display("[TB] TIMEOUT global (10 ms). st=%0d", DUT.state);
        $finish;
    end

endmodule

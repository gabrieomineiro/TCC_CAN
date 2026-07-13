//-----------------------------------------------------------------------------
// tb_can_fifo — Testbench SIMPLES (smoke test, self-checking, nao-UVM) do
// can_fifo (FWFT message-based, MSG_W=99, DEPTH=8).
//
// Cobre: reset -> empty; push N itens -> count/full; FWFT (rdata == topo
// antes do pop); pop -> count/empty; push+pop simultaneo; drop em full;
// no-op em empty.
//
// Rodar (Xcelium, a partir da raiz):
//   xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
//        uvm/testbench/tb_can_fifo.sv
// Syntax-check Icarus:
//   iverilog -g2012 -t null -f script/simlist_can.f uvm/testbench/tb_can_fifo.sv
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_can_fifo;

    localparam int MSG_W  = 99;
    localparam int DEPTH  = 8;

    logic             clk = 1'b0;
    logic             rst_n;
    logic             push, pop;
    logic [MSG_W-1:0] wdata;
    logic [MSG_W-1:0] rdata;
    logic             full, empty, rdata_valid;
    logic [$clog2(DEPTH+1):0] count;   // PTR_W+1 largura do count

    can_fifo #(.MSG_W(MSG_W), .DEPTH(DEPTH)) DUT (
        .clk(clk), .rst_n(rst_n),
        .push(push), .wdata(wdata), .full(full),
        .pop(pop), .rdata(rdata), .empty(empty), .rdata_valid(rdata_valid),
        .count(count)
    );

    always #10 clk = ~clk;

    integer errors;
    logic [MSG_W-1:0] exp_top;   // valor esperado no topo (FWFT)

    // empurra 1 item por ciclo (síncrono); wdata é o "tag" do item
    task do_push(input logic [MSG_W-1:0] d);
        begin
            @(negedge clk);
            push = 1'b1; wdata = d;
            @(negedge clk);
            push = 1'b0;
        end
    endtask

    task do_pop;
        begin
            @(negedge clk);
            pop = 1'b1;
            @(negedge clk);
            pop = 1'b0;
        end
    endtask

    task chk(input bit cond, input string msg);
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("[TB] FAIL: %s", msg);
            end else begin
                $display("[TB] OK:   %s", msg);
            end
        end
    endtask

    initial begin
        $timeformat(-9, 3, " ns", 12);
        errors = 0;
        push = 1'b0; pop = 1'b0; wdata = '0;

        $dumpfile("tb_can_fifo.vcd");
        $dumpvars(0, tb_can_fifo);

        // Reset
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("==========================================================");
        $display("[TB] tb_can_fifo — smoke test");
        $display("==========================================================");

        // 1) Pós-reset: empty=1, count=0, full=0
        chk(empty === 1'b1,            "empty=1 pos-reset");
        chk(full  === 1'b0,            "full=0  pos-reset");
        chk(count == 0,                "count=0 pos-reset");
        chk(rdata_valid === 1'b0,      "rdata_valid=0 pos-reset");

        // 2) Push 8 itens (enche). tag = i (larga em [7:0], resto zero)
        for (int i = 0; i < DEPTH; i++) begin
            do_push({92'b0, 7'b0, i[7:0]});  // wdata[7:0] = i
        end
        @(posedge clk);
        chk(full  === 1'b1,            "full=1 apos encher");
        chk(empty === 1'b0,            "empty=0 apos encher");
        chk(count == DEPTH,            "count=DEPTH apos encher");

        // 3) Push em full -> drop, count não muda
        do_push({99{1'b1}});
        @(posedge clk);
        chk(full === 1'b1,             "full persiste apos push em full");
        chk(count == DEPTH,            "count nao muda apos push em full");

        // 4) FWFT: topo agora é o item 0 (wdata[7:0]=0)
        chk(rdata[7:0] === 8'd0,       "FWFT: rdata == item 0 (topo)");
        chk(rdata_valid === 1'b1,      "rdata_valid=1 com topo valido");

        // 5) Pop todos, conferindo ordem FIFO (item 0,1,2,...,7)
        for (int i = 0; i < DEPTH; i++) begin
            // FWFT: rdata já é o topo ANTES do pop
            chk(rdata[7:0] === i[7:0], $sformatf("pop %0d: rdata == item %0d", i, i));
            do_pop;
            @(posedge clk);
        end
        chk(empty === 1'b1,            "empty=1 apos esvaziar");
        chk(count == 0,                "count=0 apos esvaziar");
        chk(rdata_valid === 1'b0,      "rdata_valid=0 apos esvaziar");

        // 6) Pop em empty -> no-op
        do_pop;
        @(posedge clk);
        chk(empty === 1'b1,            "empty persiste apos pop em empty");
        chk(count == 0,                "count=0 apos pop em empty");

        // 7) Push + Pop simultâneo (count mantém com 1 item)
        //    Antes garante count=1; então push+pop -> do_push=1, do_pop=1,
        //    count não muda.
        do_push({91'b0, 8'hAA});        // count de 0 -> 1
        @(posedge clk);
        chk(count == 1,                 "precondicao: count=1");
        @(negedge clk);
        push = 1'b1; pop = 1'b1; wdata = {91'b0, 8'hAB};
        @(negedge clk);
        push = 1'b0; pop = 1'b0;
        @(posedge clk);
        chk(count == 1,                 "push+pop simultaneo mantem count=1");

        // 8) Esvazia e faz 1 push isolado, confere FWFT
        do_pop;                         // count de 1 -> 0
        @(posedge clk);
        chk(count == 0,                 "precondicao: count=0 apos pop");
        do_push({91'b0, 8'hAB});
        @(posedge clk);
        chk(rdata[7:0] === 8'hAB,       "apos 1 push: rdata == 0xAB");
        chk(count == 1,                 "count=1 apos 1 push");

        // --------------------------------------------------
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

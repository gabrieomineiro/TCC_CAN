//-----------------------------------------------------------------------------
// tb_can_acceptance — Testbench SIMPLES (smoke test, self-checking, nao-UVM)
// do can_acceptance (4 filtros code+mask, política RESTRITIVA OR).
//
// Cobre:
//   - mask=0 (casa tudo) com filtro habilitado -> accept.
//   - filtro desabilitado (filt_en=0) -> reject.
//   - mask=1 (must match) com match -> accept, sem match -> reject.
//   - match de IDE quando mask[29]=0.
//   - comportamento sticky entre strobes.
//
// Rodar (Xcelium):
//   xrun -sv -access +rwc -timescale 1ns/1ps -f script/simlist_can.f \
//        uvm/testbench/tb_can_acceptance.sv
// Icarus:
//   iverilog -g2012 -t null -f script/simlist_can.f uvm/testbench/tb_can_acceptance.sv
//-----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_can_acceptance;

    localparam int N = 4;

    logic        clk = 1'b0;
    logic        rst_n;
    logic [28:0] id;
    logic        ide;
    logic [29:0] filt_code [N];
    logic [29:0] filt_mask [N];
    logic [N-1:0] filt_en;
    logic        check_strobe;
    logic        accept, reject;

    can_acceptance #(.NUM_FILTERS(N)) DUT (
        .clk(clk), .rst_n(rst_n),
        .id(id), .ide(ide),
        .filt_code(filt_code), .filt_mask(filt_mask), .filt_en(filt_en),
        .check_strobe(check_strobe),
        .accept(accept), .reject(reject)
    );

    always #10 clk = ~clk;

    integer errors;

    task chk(input bit cond, input string msg);
        begin
            if (!cond) begin errors = errors + 1; $display("[TB] FAIL: %s", msg); end
            else         $display("[TB] OK:   %s", msg);
        end
    endtask

    // Avalia com um strobe e checa accept/reject esperados
    task eval_check(input bit exp_accept, input string msg);
        begin
            @(negedge clk); check_strobe = 1'b1;
            @(negedge clk); check_strobe = 1'b0;
            @(posedge clk);
            chk(accept === exp_accept,             msg);
            chk(reject === ~exp_accept,            "reject= complemento de accept");
        end
    endtask

    initial begin
        $timeformat(-9, 3, " ns", 12);
        errors = 0;
        id = 29'b0; ide = 1'b0;
        for (int i = 0; i < N; i++) begin
            filt_code[i] = 30'b0;
            filt_mask[i] = 30'b0;
        end
        filt_en = 4'b0;
        check_strobe = 1'b0;

        $dumpfile("tb_can_acceptance.vcd");
        $dumpvars(0, tb_can_acceptance);

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("==========================================================");
        $display("[TB] tb_can_acceptance — smoke test");
        $display("==========================================================");

        // 1) Pós-reset: accept=0, reject=0 (sem strobe ainda)
        chk(accept === 1'b0, "accept=0 pos-reset");
        chk(reject === 1'b0, "reject=0 pos-reset");

        // 2) Sem filtro habilitado -> reject
        id = 29'h123; ide = 1'b0;
        eval_check(1'b0, "sem filtros habilitados -> reject");

        // 3) Filtro 0: mask=0 (casa tudo), habilitado -> accept
        filt_code[0] = 30'b0;
        filt_mask[0] = 30'h3FFFFFFF;   // todos don't care -> casa tudo
        filt_en      = 4'b0001;
        eval_check(1'b1, "filtro 0 mask all-dont-care -> accept");

        // 4) mask=0 (must match all), code != id -> reject
        filt_mask[0] = 30'b0;          // tudo deve casar
        filt_code[0] = {1'b0, 29'h00000123};
        id = 29'h00000124;             // ID diferente
        eval_check(1'b0, "mask=0 code=0x123 id=0x124 -> reject");

        // 5) mask=0, code == id -> accept
        id = 29'h00000123;
        eval_check(1'b1, "mask=0 code=0x123 id=0x123 -> accept");

        // 6) mask parcial: casa só baixos (id[10:0])
        //    mask[10:0]=1 (dont-care), code[28:11]=0, id[10:0] irrelevante
        filt_code[0] = {1'b0, 29'h0};
        filt_mask[0] = {1'b0, 29'h000007FF};   // dont-care nos 11 baixos
        id = 29'h000007FF;             // 11 baixos = 1, mas não importam
        eval_check(1'b1, "mask parcial (dont-care 11 baixos) -> accept");
        id = 29'h00800000;             // bit 23 seta -> casa alto? alto é code=0
        eval_check(1'b0, "mask parcial: alto difere -> reject");

        // 7) IDE mismatch quando mask[29]=0
        filt_code[0] = {1'b0, 29'h0};  // code[IDE]=0 (standard)
        filt_mask[0] = 30'h00000000;   // tudo must-match
        id = 29'h0; ide = 1'b0;        // standard -> casa
        eval_check(1'b1, "IDE code=0 / msg=0 -> accept");
        ide = 1'b1;                    // extended -> mismatch
        eval_check(1'b0, "IDE code=0 / msg=1 -> reject");

        // 8) IDE dont-care (mask[29]=1)
        filt_mask[0] = 30'h20000000;   // só IDE dont-care, resto must-match
        filt_code[0] = {1'b0, 29'h0};
        id = 29'h0; ide = 1'b0;
        eval_check(1'b1, "IDE dont-care, ID=0 standard -> accept");
        ide = 1'b1;
        eval_check(1'b1, "IDE dont-care, ID=0 extended -> accept");

        // 9) OR entre filtros: filtro 0 rejeita, filtro 1 aceita
        filt_mask[0] = 30'b0; filt_code[0] = {1'b0,29'h0};
        filt_mask[1] = 30'h3FFFFFFF; filt_code[1] = 30'h0;
        filt_en = 4'b0011;
        id = 29'hABC; ide = 1'b0;
        eval_check(1'b1, "OR: filtro 1 mask-all accept sobrepõe filtro 0");

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

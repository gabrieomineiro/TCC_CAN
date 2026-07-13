//-----------------------------------------------------------------------------
// can_reg_file
// Interface APB (host) do controlador CAN. Decodifica endereços, armazena os
// registradores, monta/desmonta o descritor de mensagem (99 bits) dos regs
// TX/RX, distribui config (bit timing, filtros) e coleta status/interrupt.
// Layout do descritor e mapa de regs: ver Docs/specs/02 e 01.
//-----------------------------------------------------------------------------
module can_reg_file (
    input  logic        clk,
    input  logic        rst_n,

    // ---- APB slave ----
    input  logic [31:0] paddr,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    // ---- config distribuída ----
    output logic [7:0]  btr_prescaler,
    output logic [2:0]  btr_prop,
    output logic [2:0]  btr_seg1,
    output logic [2:0]  btr_seg2,
    output logic [1:0]  btr_sjw,

    // ---- modo ----
    output logic        can_en,
    output logic        sft_rst,

    // ---- Tx (montagem) ----
    output logic        tx_push,
    output logic [98:0] tx_msg,
    input  logic        tx_full,
    input  logic        tx_empty,

    // ---- Rx (desmontagem) ----
    output logic        rx_pop,
    input  logic [98:0] rx_msg,
    input  logic        rx_empty,
    input  logic [3:0]  rx_count,

    // ---- filtros ----
    output logic [29:0] filt_code [3:0],
    output logic [29:0] filt_mask [3:0],
    output logic [3:0]  filt_en,

    // ---- status/interrupt ----
    input  logic        stat_bus_off,
    input  logic        stat_err_pass,
    input  logic        stat_tx_busy,
    input  logic        stat_rx_avail,
    input  logic        stat_tx_full,
    input  logic [7:0]  tec,
    input  logic [7:0]  rec,
    output logic [7:0]  ien,
    output logic [7:0]  ifg_clear,
    input  logic [7:0]  ifg_flags,
    output logic        irq
);

    // offsets de registrador (selecionados por paddr[7:2])
    localparam logic [5:0] A_MOD      = 6'h00; // 0x00
    localparam logic [5:0] A_BTR      = 6'h01; // 0x04
    localparam logic [5:0] A_TCTRL    = 6'h02; // 0x08
    localparam logic [5:0] A_TID      = 6'h03; // 0x0C
    localparam logic [5:0] A_TDLC     = 6'h04; // 0x10
    localparam logic [5:0] A_TDA      = 6'h05; // 0x14
    localparam logic [5:0] A_TDB      = 6'h06; // 0x18
    localparam logic [5:0] A_RCTRL    = 6'h07; // 0x1C
    localparam logic [5:0] A_RID      = 6'h08; // 0x20
    localparam logic [5:0] A_RDLC     = 6'h09; // 0x24
    localparam logic [5:0] A_RDA      = 6'h0A; // 0x28
    localparam logic [5:0] A_RDB      = 6'h0B; // 0x2C
    localparam logic [5:0] A_STAT     = 6'h0C; // 0x30
    localparam logic [5:0] A_ERR      = 6'h0D; // 0x34
    localparam logic [5:0] A_IEN      = 6'h0E; // 0x38
    localparam logic [5:0] A_IFG      = 6'h0F; // 0x3C
    localparam logic [5:0] A_FILT0C   = 6'h10; // 0x40
    localparam logic [5:0] A_FILT_EN  = 6'h18; // 0x60

    // ---- APB decode ----
    wire [5:0] reg_idx = paddr[7:2];
    wire apb_acc  = psel && penable;             // fase access (1 ciclo)
    wire apb_wr   = apb_acc && pwrite;
    wire apb_rd   = apb_acc && !pwrite;
    wire addr_resv = (reg_idx > A_FILT_EN);      // acima de 0x60 = reservado

    // ---- pulsos de ação (combinacionais, 1 ciclo = acesso APB) ----
    wire tctrl_txreq  = apb_wr && (reg_idx == A_TCTRL) && pwdata[0];
    wire rctrl_rel    = apb_wr && (reg_idx == A_RCTRL) && pwdata[0];
    wire mod_sftrst   = apb_wr && (reg_idx == A_MOD)   && pwdata[1];

    assign tx_push = tctrl_txreq && !tx_full;
    assign rx_pop  = rctrl_rel   && !rx_empty;
    assign sft_rst = mod_sftrst;
    assign pready  = 1'b1;

    // ---- montagem TX ----
    // descritor: {RTR[98], IDE[97], ID[96:68], DLC[67:64], DATA[63:0]}
    assign tx_msg = { tid_r[30], tid_r[29], tid_r[28:0], tdlc_r, tdb_r, tda_r };

    // ---- ifg_clear (W1C em CAN_IFG; sft_rst limpa tudo) ----
    always_comb begin
        ifg_clear = 8'h00;
        if (apb_wr && (reg_idx == A_IFG)) ifg_clear = pwdata[7:0];
        if (mod_sftrst)                   ifg_clear = 8'hFF;
    end

    // ---- registradores de armazenamento ----
    logic        can_en_r;
    logic [7:0]  btr_brp_r;
    logic [2:0]  btr_prop_r, btr_seg1_r, btr_seg2_r;
    logic [1:0]  btr_sjw_r;
    logic [30:0] tid_r;        // [30]RTR [29]IDE [28:0]ID
    logic [3:0]  tdlc_r;
    logic [31:0] tda_r, tdb_r;
    logic [7:0]  ien_r;
    logic [29:0] filt_code_r [3:0];
    logic [29:0] filt_mask_r [3:0];
    logic [3:0]  filt_en_r;

    // índice de filtro a partir do offset (0x40..0x5C)
    wire [2:0] filt_off = reg_idx[3:1];   // 0x10..0x17 -> 0..3 (code/mask alternados)
    wire       filt_is_mask = reg_idx[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            can_en_r    <= 1'b0;
            btr_brp_r   <= 8'd10;          // default 500 kbps @50 MHz
            btr_prop_r  <= 3'd2;
            btr_seg1_r  <= 3'd5;
            btr_seg2_r  <= 3'd2;
            btr_sjw_r   <= 2'd2;
            tid_r       <= 31'b0;
            tdlc_r      <= 4'b0;
            tda_r       <= 32'b0;
            tdb_r       <= 32'b0;
            ien_r       <= 8'b0;
            filt_en_r   <= 4'b0;
            for (int i = 0; i < 4; i++) begin
                filt_code_r[i] <= 30'b0;
                filt_mask_r[i] <= 30'b0;
            end
        end else if (mod_sftrst) begin
            // SFT_RST: zera controle (can_en); preserva BTR/filtros/IEN
            can_en_r <= 1'b0;
        end else if (apb_wr && !addr_resv) begin
            case (reg_idx)
                A_MOD:    can_en_r <= pwdata[0];
                A_BTR: begin
                    btr_brp_r  <= (pwdata[7:0] == 8'h00) ? 8'd1 : pwdata[7:0];
                    btr_prop_r <= pwdata[10:8];
                    btr_seg1_r <= pwdata[14:12];
                    btr_seg2_r <= pwdata[18:16];
                    btr_sjw_r  <= pwdata[21:20];
                end
                A_TID:    tid_r  <= pwdata[30:0];
                A_TDLC:   tdlc_r <= pwdata[3:0];
                A_TDA:    tda_r  <= pwdata;
                A_TDB:    tdb_r  <= pwdata;
                A_IEN:    ien_r  <= pwdata[7:0];
                A_FILT_EN: filt_en_r <= pwdata[3:0];
                default: ;
            endcase
            // filtros code/mask (offsets 0x40..0x5C = reg_idx 0x10..0x17)
            if (reg_idx >= A_FILT0C && reg_idx <= 6'h17) begin
                if (filt_is_mask) filt_mask_r[filt_off[1:0]] <= pwdata[29:0];
                else              filt_code_r[filt_off[1:0]] <= pwdata[29:0];
            end
        end
    end

    // ---- saídas de config ----
    assign btr_prescaler = btr_brp_r;
    assign btr_prop      = btr_prop_r;
    assign btr_seg1      = btr_seg1_r;
    assign btr_seg2      = btr_seg2_r;
    assign btr_sjw       = btr_sjw_r;
    assign can_en        = can_en_r;
    assign ien           = ien_r;
    assign filt_en       = filt_en_r;
    assign irq           = |(ifg_flags & ien_r);

    //---- distribuição de arrays de filtros ----
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi++) begin : g_filt
            assign filt_code[gi] = filt_code_r[gi];
            assign filt_mask[gi] = filt_mask_r[gi];
        end
    endgenerate

    // ---- leitura (prdata) + pslverr ----
    wire rx_v = !rx_empty;
    always_comb begin
        prdata   = 32'h0;
        pslverr  = 1'b0;
        if (apb_rd) begin
            if (addr_resv) begin
                pslverr = 1'b1;
            end else begin
                case (reg_idx)
                    A_MOD:    prdata = {31'b0, can_en_r};   // CAN_EN no bit 0 (spec 01)
                    A_BTR:    prdata = {10'b0, btr_sjw_r, 1'b0, btr_seg2_r,
                                        1'b0, btr_seg1_r, 1'b0, btr_prop_r, btr_brp_r};
                    A_TCTRL:  prdata = 32'h0;
                    A_TID:    prdata = {1'b0, tid_r};
                    A_TDLC:   prdata = {28'b0, tdlc_r};
                    A_TDA:    prdata = tda_r;
                    A_TDB:    prdata = tdb_r;
                    A_RCTRL:  prdata = {16'b0, 4'b0, rx_count, 8'b0};
                    A_RID:    prdata = rx_v ? {1'b0, rx_msg[98:68]} : 32'b0;
                    A_RDLC:   prdata = rx_v ? {28'b0, rx_msg[67:64]} : 32'b0;
                    A_RDA:    prdata = rx_v ? rx_msg[31:0] : 32'b0;
                    A_RDB:    prdata = rx_v ? rx_msg[63:32] : 32'b0;
                    A_STAT:   prdata = {26'b0, tx_empty, stat_tx_full, stat_rx_avail,
                                        stat_tx_busy, stat_err_pass, stat_bus_off};
                    A_ERR:    prdata = {16'b0, rec, tec};
                    A_IEN:    prdata = {24'b0, ien_r};
                    A_IFG:    prdata = {24'b0, ifg_flags};
                    A_FILT_EN:prdata = {28'b0, filt_en_r};
                    default: begin
                        // filtros code/mask (0x10..0x17)
                        if (filt_is_mask)
                            prdata = {2'b0, filt_mask_r[filt_off[1:0]]};
                        else
                            prdata = {2'b0, filt_code_r[filt_off[1:0]]};
                    end
                endcase
            end
        end
    end

endmodule

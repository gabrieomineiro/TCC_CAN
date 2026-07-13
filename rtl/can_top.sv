//-----------------------------------------------------------------------------
// can_top  (Controlador CAN 2.0B — integração)
// Instancia e interconecta todos os blocos: reg_file (APB), btu, bsp, crc,
// fsm, arbitration, error (EML), FIFOs Tx/Rx, acceptance, interrupt.
// Reset parcial: rst_core_n = rst_n & ~sft_rst reinicia o núcleo
// (FSM/FIFOs/EML/BTU/BSP/CRC/arb/filter/int); o reg_file fica em rst_n e
// preserva a configuração (BTR/filtros/IEN). (Docs/specs/00 §9.)
//-----------------------------------------------------------------------------
module can_top #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 500_000
)(
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

    // ---- CAN bus físico ----
    input  logic        can_rx,
    output logic        can_tx,
    output logic        can_tx_oe,

    // ---- interrupt ----
    output logic        irq
);

    localparam int MSG_W = 99;

    // reset parcial do núcleo
    logic sft_rst;
    logic rst_core_n;
    assign rst_core_n = rst_n & ~sft_rst;

    // ---- config (reg_file -> btu/acceptance) ----
    logic [7:0] btr_prescaler;
    logic [2:0] btr_prop, btr_seg1, btr_seg2;
    logic [1:0] btr_sjw;
    logic       can_en;
    logic [29:0] rf_filt_code [3:0];
    logic [29:0] rf_filt_mask [3:0];
    logic [3:0]  rf_filt_en;
    logic [7:0]  ien;

    // ---- Tx FIFO ----
    logic        tx_push, tx_pop, tx_full, tx_empty;
    logic [MSG_W-1:0] rf_tx_msg;   // reg_file -> FIFO wdata
    logic [MSG_W-1:0] tx_fifo_rd;  // FIFO rdata -> FSM
    // ---- Rx FIFO ----
    logic        rx_push, rx_pop, rx_full, rx_empty;
    logic [MSG_W-1:0] fsm_rx_msg;  // FSM -> FIFO wdata
    logic [MSG_W-1:0] rx_fifo_rd;  // FIFO rdata -> reg_file
    logic [3:0]  rx_count;

    // ---- BTU ticks ----
    logic bit_tick, sample_tick, tx_tick;
    logic hard_sync_w;   // FSM -> BTU (hard sync no SOF)
    logic sync_en_w;     // FSM -> BTU (sync enable)

    // ---- FSM <-> BSP ----
    logic bsp_tx_bit, bsp_tx_valid, stuff_en;
    logic rx_bit, rx_valid, stuff_error_bsp, tx_bit_done, bsp_busy;
    logic bit_to_crc, crc_bit_valid;

    // ---- FSM <-> CRC ----
    logic crc_clear, crc_shift;
    logic [14:0] crc_out, rx_crc;
    logic crc_match, crc_error;
    logic check_strobe;

    // ---- FSM <-> Arbitration ----
    logic arb_en, arb_lost;
    logic [5:0] arb_lost_bit;

    // ---- FSM <-> Acceptance ----
    logic [28:0] flt_id;
    logic        flt_ide, flt_check, flt_accept;

    // ---- FSM <-> EML ----
    logic e_bit_err, e_stuff_err, e_crc_err, e_ack_err, e_form_err;
    logic tx_context, frame_tx_ok, frame_rx_ok;
    logic error_active, error_passive, bus_off, error_flag_req;

    // ---- FSM <-> Interrupt ----
    logic int_tx_done, int_rx_avail, int_arb_lost, int_stuff_err, int_crc_err;

    // ---- EML contadores ----
    logic [7:0] tec, rec;

    // ---- status -> reg_file ----
    logic stat_tx_busy, stat_rx_avail;

    // ---- interrupt ----
    logic [7:0] ifg, ifg_clear;
    logic err_warn;

    //------------------------------------------------------------------
    // reg_file (host APB) — reset só por rst_n (preserva config)
    //------------------------------------------------------------------
    can_reg_file u_reg_file (
        .clk(clk), .rst_n(rst_n),
        .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
        .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .btr_prescaler(btr_prescaler), .btr_prop(btr_prop), .btr_seg1(btr_seg1),
        .btr_seg2(btr_seg2), .btr_sjw(btr_sjw),
        .can_en(can_en), .sft_rst(sft_rst),
        .tx_push(tx_push), .tx_msg(rf_tx_msg), .tx_full(tx_full), .tx_empty(tx_empty),
        .rx_pop(rx_pop), .rx_msg(rx_fifo_rd), .rx_empty(rx_empty), .rx_count(rx_count),
        .filt_code(rf_filt_code), .filt_mask(rf_filt_mask), .filt_en(rf_filt_en),
        .stat_bus_off(bus_off), .stat_err_pass(error_passive),
        .stat_tx_busy(stat_tx_busy), .stat_rx_avail(stat_rx_avail),
        .stat_tx_full(tx_full),
        .tec(tec), .rec(rec), .ien(ien),
        .ifg_clear(ifg_clear), .ifg_flags(ifg), .irq(/* usar u_int.irq */)
    );

    //------------------------------------------------------------------
    // BTU
    //------------------------------------------------------------------
    can_btu #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_btu (
        .clk(clk), .rst_n(rst_core_n),
        .prescaler(btr_prescaler), .prop_seg(btr_prop),
        .phase_seg1(btr_seg1), .phase_seg2(btr_seg2), .sjw(btr_sjw),
        .can_rx(can_rx), .sync_en(sync_en_w), .hard_sync(hard_sync_w),
        .bit_tick(bit_tick), .sample_tick(sample_tick), .tx_tick(tx_tick),
        .sample_point(), .bit_time_cnt(),
        .sync_locked(), .edge_detected(), .sync_active(), .fsm_state()
    );

    //------------------------------------------------------------------
    // BSP
    //------------------------------------------------------------------
    can_bsp u_bsp (
        .clk(clk), .rst_n(rst_core_n),
        .bit_tick(bit_tick), .sample_tick(sample_tick),
        .tx_bit(bsp_tx_bit), .tx_valid(bsp_tx_valid), .stuff_en(stuff_en),
        .can_rx(can_rx), .can_tx(can_tx), .can_tx_oe(can_tx_oe),
        .rx_bit(rx_bit), .rx_valid(rx_valid), .tx_bit_done(tx_bit_done),
        .bit_to_crc(bit_to_crc), .crc_bit_valid(crc_bit_valid),
        .stuff_error(stuff_error_bsp), .bsp_busy(bsp_busy)
    );

    //------------------------------------------------------------------
    // CRC-15
    //------------------------------------------------------------------
    can_crc u_crc (
        .clk(clk), .rst_n(rst_core_n),
        .crc_clear(crc_clear), .crc_shift(crc_shift), .bit_in(bit_to_crc),
        .crc_out(crc_out),
        .rx_crc(rx_crc), .check_strobe(check_strobe),
        .crc_match(crc_match), .crc_error(crc_error)
    );

    //------------------------------------------------------------------
    // FSM (Frame Sequencer)
    //------------------------------------------------------------------
    can_fsm u_fsm (
        .clk(clk), .rst_n(rst_core_n),
        .can_en(can_en), .fsm_busy(stat_tx_busy),
        .bit_tick(bit_tick), .sample_tick(sample_tick), .tx_tick(tx_tick),
        .sync_locked(1'b0), .sync_en(sync_en_w), .hard_sync(hard_sync_w),
        .bsp_tx_bit(bsp_tx_bit), .bsp_tx_valid(bsp_tx_valid), .stuff_en(stuff_en),
        .rx_bit(rx_bit), .rx_valid(rx_valid), .stuff_error(stuff_error_bsp),
        .tx_bit_done(tx_bit_done),
        .crc_clear(crc_clear), .crc_shift(crc_shift),
        .crc_out(crc_out), .crc_match(crc_match), .crc_error(crc_error),
        .rx_crc(rx_crc), .check_strobe(check_strobe),
        .arb_en(arb_en), .arb_lost(arb_lost), .arb_lost_bit(arb_lost_bit),
        .tx_pop(tx_pop), .tx_msg(tx_fifo_rd), .tx_empty(tx_empty),
        .rx_push(rx_push), .rx_msg(fsm_rx_msg), .rx_full(rx_full),
        .flt_id(flt_id), .flt_ide(flt_ide), .flt_check(flt_check), .flt_accept(flt_accept),
        .e_bit_err(e_bit_err), .e_stuff_err(e_stuff_err), .e_crc_err(e_crc_err),
        .e_ack_err(e_ack_err), .e_form_err(e_form_err),
        .tx_context(tx_context), .frame_tx_ok(frame_tx_ok), .frame_rx_ok(frame_rx_ok),
        .error_active(error_active), .error_passive(error_passive),
        .bus_off(bus_off), .error_flag_req(error_flag_req),
        .int_tx_done(int_tx_done), .int_rx_avail(int_rx_avail),
        .int_arb_lost(int_arb_lost), .int_stuff_err(int_stuff_err),
        .int_crc_err(int_crc_err),
        .fsm_state()
    );

    //------------------------------------------------------------------
    // Arbitration
    //------------------------------------------------------------------
    can_arbitration u_arb (
        .clk(clk), .rst_n(rst_core_n),
        .sample_tick(sample_tick), .arb_en(arb_en),
        .tx_bit(bsp_tx_bit), .rx_bit(rx_bit),
        .arb_lost(arb_lost), .arb_active(), .arb_lost_bit(arb_lost_bit)
    );

    //------------------------------------------------------------------
    // EML (can_error)
    //------------------------------------------------------------------
    can_error u_err (
        .clk(clk), .rst_n(rst_core_n),
        .bit_error(e_bit_err), .stuff_error(e_stuff_err), .crc_error(e_crc_err),
        .ack_error(e_ack_err), .form_error(e_form_err),
        .tx_context(tx_context), .arb_lost(arb_lost),
        .frame_tx_ok(frame_tx_ok), .frame_rx_ok(frame_rx_ok),
        .err_reset(sft_rst),
        .tec(tec), .rec(rec),
        .error_active(error_active), .error_passive(error_passive),
        .bus_off(bus_off), .error_flag_req(error_flag_req)
    );

    //------------------------------------------------------------------
    // Tx FIFO
    //------------------------------------------------------------------
    can_fifo #(.MSG_W(MSG_W), .DEPTH(8)) u_tx_fifo (
        .clk(clk), .rst_n(rst_core_n),
        .push(tx_push), .wdata(rf_tx_msg), .full(tx_full),
        .pop(tx_pop), .rdata(tx_fifo_rd), .empty(tx_empty), .rdata_valid(),
        .count()
    );

    //------------------------------------------------------------------
    // Rx FIFO
    //------------------------------------------------------------------
    can_fifo #(.MSG_W(MSG_W), .DEPTH(8)) u_rx_fifo (
        .clk(clk), .rst_n(rst_core_n),
        .push(rx_push), .wdata(fsm_rx_msg), .full(rx_full),
        .pop(rx_pop), .rdata(rx_fifo_rd), .empty(rx_empty), .rdata_valid(),
        .count(rx_count)
    );

    //------------------------------------------------------------------
    // Acceptance
    //------------------------------------------------------------------
    can_acceptance #(.NUM_FILTERS(4)) u_filter (
        .clk(clk), .rst_n(rst_core_n),
        .id(flt_id), .ide(flt_ide),
        .filt_code(rf_filt_code), .filt_mask(rf_filt_mask), .filt_en(rf_filt_en),
        .check_strobe(flt_check), .accept(flt_accept), .reject()
    );

    //------------------------------------------------------------------
    // Interrupt
    //------------------------------------------------------------------
    assign err_warn = (tec >= 8'd96) || (rec >= 8'd96);
    assign stat_rx_avail = !rx_empty;

    can_interrupt u_int (
        .clk(clk), .rst_n(rst_core_n),
        .src_tx_done(int_tx_done), .src_rx_avail(int_rx_avail),
        .src_err_warn(err_warn), .src_err_passive(error_passive),
        .src_bus_off(bus_off), .src_arb_lost(int_arb_lost),
        .src_stuff_err(int_stuff_err), .src_crc_err(int_crc_err),
        .ien(ien), .iclear(ifg_clear),
        .ifg(ifg), .irq(irq)
    );

endmodule

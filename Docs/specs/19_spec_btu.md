# 19 — Spec: can_btu (Bit Timing Unit) [consolidação]

## 1. Função
Gera os sinais de temporização de bit CAN: prescaler (gera Time Quanta), segmentação do bit (sync + prop + phase1 + phase2), ponto de amostragem, e suporte a sincronização forte (hard sync) e suave (soft sync com SJW). **Este bloco já existe e está validado** (`rtl/can_btu.sv`, UVM em `uvm/BTU/`); esta spec consolida sua interface/behavior.

## 2. Interface
```systemverilog
module can_btu #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 500_000
)(
    input  logic        clk, rst_n,
    input  logic [7:0]  prescaler,
    input  logic [2:0]  prop_seg, phase_seg1, phase_seg2,
    input  logic [1:0]  sjw,
    input  logic        can_rx,       // p/ detecção de borda
    input  logic        sync_en,
    input  logic        hard_sync,
    output logic        bit_tick,     // pulso no início do bit (TQ=0)
    output logic        sample_tick,  // pulso no ponto de amostragem
    output logic        tx_tick,      // pulso em TQ=1 (ponto de transmissão)
    output logic        sample_point, // nível alto da amostragem ao fim do bit
    output logic [7:0]  bit_time_cnt,
    output logic        sync_locked, edge_detected, sync_active,
    output logic [2:0]  fsm_state
);
```

## 3. Parâmetros / defaults (ver `rtl/can_defines.svh`)
- Default **confirmado (500 kbps @ 50 MHz, sample 80%)**: `DEFAULT_PRESCALER=10`, `DEFAULT_PROP_SEG=2`, `DEFAULT_PHASE_SEG1=5`, `DEFAULT_PHASE_SEG2=2`, `DEFAULT_SJW=2`. (ver `01_mapa_registradores` §3). O `can_defines.svh` deve ser atualizado para estes valores.
- Codificação **direta**: 3-bit segs = nº de TQ (faixa 1..7; `phase_seg2` mín. 2); `sjw` 2 bits (1..3); `sjw <= min(phase_seg1, phase_seg2)`.

## 4. Comportamento (resumo)
- Prescaler: conta `prescaler_safe` (= prescaler, 0→1) ciclos por TQ; `presc_tick` a cada TQ.
- TQ counter: 0..total_tq-1, onde `total_tq = 1 + prop_seg + phase_seg1 + phase_seg2`.
- `sample_tq_base = 1 + prop_seg + phase_seg1`.
- `bit_tick` em TQ=0; `tx_tick` em TQ=1; `sample_tick` em sample_tq (base ou ajustado por resync).
- Detecção de borda de descida (recessivo→dominante) para soft sync.
- FSM de sincronismo: SYNC_IDLE/WAIT_EDGE/ADJUSTING/COMPLETE — ajusta phase_seg1 (alonga, antes do sample) ou phase_seg2 (encurta, depois do sample) limitado a SJW.
- hard_sync reinicia TQ=0 (usado no SOF).

## 5. Codificação (confirmada)
- Os campos `prop_seg/phase_seg1/phase_seg2` são usados **diretamente** como número de TQ (não +1). Faixa válida com 3 bits: 1..7 (0 é ilegal). `phase_seg2` mínimo 2.
- `sjw` 1..3 (2 bits). Constraint `sjw <= min(phase_seg1, phase_seg2)`.
- `prescaler` = número de ciclos de clock por TQ (não +1).
- **Ação de realinhamento (Fase 3):** atualizar `can_defines.svh` aos novos defaults (§3).

## 6. Conexões no topo
- reg_file (`CAN_BTR`) → `prescaler`, `prop_seg`, `phase_seg1`, `phase_seg2`, `sjw`.
- `can_rx` do pino.
- FSM → `sync_en`, `hard_sync` (hard_sync no SOF; sync_en sempre, ou gated).
- Saídas ticks → FSM, BSP, CRC.

## 7. Features para verificação (já cobertas em `uvm/BTU/`)
F01–F09 (ver `gabriel_pessoa_vplan_Entrega1.pdf`): time-quanta, TSEG, sample point, hard sync, soft sync, SJW, dominant/recessive, clock drift, reset. Ambiente UVM refeito na Fase 1 (propriedades + cobertura por bit).

//-----------------------------------------------------------------------------
// Módulo: can_error
// Descrição: Tratamento de erros CAN conforme ISO 11898
//            Implementa contadores TEC/REC e gerencia estados de erro
//-----------------------------------------------------------------------------

module can_error (
    input  logic        clk,
    input  logic        rst_n,
    
    // Entradas de erro
    input  logic        crc_error,
    input  logic        stuff_error,
    input  logic        ack_error,
    input  logic        form_error,
    input  logic        arbitration_lost,
    
    // Controle
    input  logic        error_reset,
    input  logic        increment_tec,
    input  logic        increment_rec,
    input  logic        decrement_rec,
    
    // Contadores
    output logic [7:0]  tec_counter,   // Transmit Error Counter
    output logic [7:0]  rec_counter,   // Receive Error Counter
    
    // Status
    output logic        error_active,  // < 128 TEC and REC
    output logic        error_passive, // >= 128 TEC or REC
    output logic        bus_off        // >= 256 TEC
);

    // Internal registers
    logic [8:0] tec;   // 9-bit to detect overflow to 256
    logic [7:0] rec;
    logic [2:0] error_state;
    
    // Error state FSM
    typedef enum logic [2:0] {
        ERROR_ACTIVE_STATE,
        ERROR_PASSIVE_STATE,
        BUS_OFF_STATE
    } error_state_t;
    
    error_state_t current_state, next_state;
    
    // TEC Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tec <= 9'd0;
        end else if (error_reset) begin
            tec <= 9'd0;
        end else if (increment_tec) begin
            if (tec < 9'd255) begin
                tec <= tec + 9'd1;
            end
        end
    end
    
    // REC Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rec <= 8'd0;
        end else if (error_reset) begin
            rec <= 8'd0;
        end else begin
            case ({increment_rec, decrement_rec})
                2'b10: begin
                    if (!form_error) begin
                        if (rec < 8'd254) rec <= rec + 8'd1;
                    end
                end
                2'b01: begin
                    if (rec > 8'd0) rec <= rec - 8'd1;
                end
                default: begin
                    if (form_error && rec > 8'd0) rec <= rec - 8'd1;
                end
            endcase
        end
    end
    
    // Error state transition
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= ERROR_ACTIVE_STATE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            ERROR_ACTIVE_STATE: begin
                if (tec >= 8'd128 || rec >= 8'd128)
                    next_state = ERROR_PASSIVE_STATE;
            end
            ERROR_PASSIVE_STATE: begin
                if (tec >= 8'd256)
                    next_state = BUS_OFF_STATE;
                else if (tec < 8'd128 && rec < 8'd128)
                    next_state = ERROR_ACTIVE_STATE;
            end
            BUS_OFF_STATE: begin
                if (error_reset)
                    next_state = ERROR_ACTIVE_STATE;
            end
        endcase
    end
    
    // Output assignments
    assign tec_counter = (tec > 8'd255) ? 8'd255 : tec[7:0];
    assign rec_counter = rec;
    assign error_active = (current_state == ERROR_ACTIVE_STATE);
    assign error_passive = (current_state == ERROR_PASSIVE_STATE);
    assign bus_off = (current_state == BUS_OFF_STATE);

endmodule
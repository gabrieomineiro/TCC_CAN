//============================================================
// Testes do BTU (base + derivados). Seleção via +UVM_TESTNAME.
//   can_btu_test         : smoke (default)
//   can_btu_full_test    : regressão completa (todas as seqs)
//   can_btu_hard_sync_test, can_btu_soft_sync_test,
//   can_btu_sjw_sat_test, can_btu_baud_test,
//   can_btu_boundary_test, can_btu_reset_test
//============================================================

class can_btu_base_test extends uvm_test;
    `uvm_component_utils(can_btu_base_test)
    can_btu_env env;
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = can_btu_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        do_run(phase);
        #200;   // dreno p/ propagação dos últimos itens
        phase.drop_objection(this);
    endtask
    virtual task do_run(uvm_phase phase); endtask
endclass

//---------------- SMOKE (default) ----------------
class can_btu_test extends can_btu_base_test;
    `uvm_component_utils(can_btu_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    virtual task do_run(uvm_phase phase);
        can_btu_random_seq s;
        s = can_btu_random_seq::type_id::create("s");
        s.count = 8;
        s.start(env.agt.seqr);
    endtask
endclass

//---------------- FULL (regressão) ----------------
class can_btu_full_test extends can_btu_base_test;
    `uvm_component_utils(can_btu_full_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    virtual task do_run(uvm_phase phase);
        can_btu_random_seq    rs;
        can_btu_hard_sync_seq hs;
        can_btu_soft_sync_seq ss;
        can_btu_sjw_sat_seq   js;
        can_btu_baud_seq      bs;
        can_btu_boundary_seq  bnd;
        can_btu_reset_seq     rts;

        rs  = can_btu_random_seq::type_id::create("rs");   rs.count = 25; rs.start(env.agt.seqr);
        hs  = can_btu_hard_sync_seq::type_id::create("hs"); hs.start(env.agt.seqr);
        ss  = can_btu_soft_sync_seq::type_id::create("ss"); ss.start(env.agt.seqr);
        js  = can_btu_sjw_sat_seq::type_id::create("js");   js.start(env.agt.seqr);
        bs  = can_btu_baud_seq::type_id::create("bs");      bs.start(env.agt.seqr);
        bnd = can_btu_boundary_seq::type_id::create("bnd"); bnd.start(env.agt.seqr);
        rts = can_btu_reset_seq::type_id::create("rts");    rts.start(env.agt.seqr);
    endtask
endclass

//---------------- DIRIGIDOS ----------------
class can_btu_hard_sync_test extends can_btu_base_test;
    `uvm_component_utils(can_btu_hard_sync_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task do_run(uvm_phase phase);
        can_btu_hard_sync_seq s = can_btu_hard_sync_seq::type_id::create("s");
        s.start(env.agt.seqr);
    endtask
endclass

class can_btu_soft_sync_test extends can_btu_base_test;
    `uvm_component_utils(can_btu_soft_sync_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task do_run(uvm_phase phase);
        can_btu_soft_sync_seq s = can_btu_soft_sync_seq::type_id::create("s");
        s.start(env.agt.seqr);
    endtask
endclass

class can_btu_sjw_sat_test extends can_btu_base_test;
    `uvm_component_utils(can_btu_sjw_sat_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task do_run(uvm_phase phase);
        can_btu_sjw_sat_seq s = can_btu_sjw_sat_seq::type_id::create("s");
        s.start(env.agt.seqr);
    endtask
endclass

class can_btu_baud_test extends can_btu_base_test;
    `uvm_component_utils(can_btu_baud_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task do_run(uvm_phase phase);
        can_btu_baud_seq s = can_btu_baud_seq::type_id::create("s");
        s.start(env.agt.seqr);
    endtask
endclass

class can_btu_boundary_test extends can_btu_base_test;
    `uvm_component_utils(can_btu_boundary_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task do_run(uvm_phase phase);
        can_btu_boundary_seq s = can_btu_boundary_seq::type_id::create("s");
        s.start(env.agt.seqr);
    endtask
endclass

class can_btu_reset_test extends can_btu_base_test;
    `uvm_component_utils(can_btu_reset_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task do_run(uvm_phase phase);
        can_btu_reset_seq s = can_btu_reset_seq::type_id::create("s");
        s.start(env.agt.seqr);
    endtask
endclass

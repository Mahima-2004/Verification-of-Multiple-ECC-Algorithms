`ifndef ECC_MEM_AGENT_SV
`define ECC_MEM_AGENT_SV

class ecc_mem_agent extends uvm_agent;
    `uvm_component_utils(ecc_mem_agent)
    
    ecc_mem_driver driver;
    ecc_mem_sequencer sequencer;
    ecc_mem_monitor monitor;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = ecc_mem_monitor::type_id::create("monitor", this);
        
        if(get_is_active() == UVM_ACTIVE) begin
            driver = ecc_mem_driver::type_id::create("driver", this);
            sequencer = ecc_mem_sequencer::type_id::create("sequencer", this);
        end
    endfunction
    
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
        `uvm_info("AGENT", "Agent connect phase complete", UVM_DEBUG)
    endfunction
endclass

`endif
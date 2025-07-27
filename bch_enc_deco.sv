`timescale 1ns/1ps

module ecc_memory (
    input wire clk,
    input wire rst_n,
    input wire en,
    input wire wr_en,
    input wire [7:0] addr,
    input wire [3:0] data_in,
    input wire [2:0] ecc_in,
    output logic [3:0] data_out,
    output logic [2:0] ecc_out,
    output logic error_detected,
    output logic error_corrected
);
    // Memory array with ECC protection (Hamming 7,4)
    typedef struct packed {
        logic [3:0] data;
        logic [2:0] ecc;
    } mem_entry_t;
    
    mem_entry_t memory [0:255];
    
    // Hamming (7,4) encode
    function automatic logic [2:0] generate_ecc(input logic [3:0] data);
        logic [2:0] ecc;
        // Parity bit positions: p0, p1, p2
        // Data bit positions: d0, d1, d2, d3
        // Codeword: [p0 p1 d0 p2 d1 d2 d3] (bit 6:0)
        ecc[0] = data[0] ^ data[1] ^ data[3]; // p0
        ecc[1] = data[0] ^ data[2] ^ data[3]; // p1
        ecc[2] = data[1] ^ data[2] ^ data[3]; // p2
        return ecc;
    endfunction

    // Hamming (7,4) decode and correct
    function automatic mem_entry_t correct_errors(
        input logic [3:0] data,
        input logic [2:0] ecc
    );
        mem_entry_t corrected;
        logic [2:0] syndrome;
        logic [6:0] codeword;
        // Assemble codeword: [p0 p1 d0 p2 d1 d2 d3]
        codeword[6] = data[3];
        codeword[5] = data[2];
        codeword[4] = data[1];
        codeword[3] = ecc[2];
        codeword[2] = data[0];
        codeword[1] = ecc[1];
        codeword[0] = ecc[0];
        // Syndrome calculation
        syndrome[0] = codeword[0] ^ codeword[2] ^ codeword[4] ^ codeword[6];
        syndrome[1] = codeword[1] ^ codeword[2] ^ codeword[5] ^ codeword[6];
        syndrome[2] = codeword[3] ^ codeword[4] ^ codeword[5] ^ codeword[6];
        corrected.data = data;
        corrected.ecc = ecc;
        if (syndrome != 0) begin
            // Single-bit error detected, correct it
            int err_pos = {syndrome[2], syndrome[1], syndrome[0]};
            if (err_pos < 7) begin
                codeword[err_pos] = ~codeword[err_pos];
            end
        end
        // Extract corrected data and ecc
        corrected.data[3] = codeword[6];
        corrected.data[2] = codeword[5];
        corrected.data[1] = codeword[4];
        corrected.data[0] = codeword[2];
        corrected.ecc[2] = codeword[3];
        corrected.ecc[1] = codeword[1];
        corrected.ecc[0] = codeword[0];
        return corrected;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            foreach (memory[i]) begin
                memory[i].data <= '0;
                memory[i].ecc <= '0;
            end
            data_out <= '0;
            ecc_out <= '0;
            error_detected <= 0;
            error_corrected <= 0;
        end else if (en) begin
            if (wr_en) begin
                memory[addr].data <= data_in;
                memory[addr].ecc <= generate_ecc(data_in);
                data_out <= '0;
                ecc_out <= '0;
                error_detected <= 0;
                error_corrected <= 0;
            end else begin
                mem_entry_t corrected;
                logic [2:0] calc_ecc;
                logic [2:0] syndrome_dbg;
                calc_ecc = generate_ecc(memory[addr].data);
                corrected = correct_errors(memory[addr].data, memory[addr].ecc);
                syndrome_dbg = calc_ecc ^ memory[addr].ecc;
                data_out <= corrected.data;
                ecc_out <= corrected.ecc;
                error_detected <= (calc_ecc != memory[addr].ecc);
                error_corrected <= (corrected.data != memory[addr].data || corrected.ecc != memory[addr].ecc);
                if (error_corrected)
                    memory[addr] <= corrected;
                $display("READ: addr=%h data=%b ecc=%b corrected_data=%b corrected_ecc=%b syndrome=%b error_detected=%b error_corrected=%b", addr, memory[addr].data, memory[addr].ecc, corrected.data, corrected.ecc, syndrome_dbg, error_detected, error_corrected);
            end
        end
    end
endmodule
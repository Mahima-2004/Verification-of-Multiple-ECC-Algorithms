
module hamming_decoder_7_4 (
    input  logic [6:0] codeword_in,
    output logic [3:0] data_out,
    output logic       error_detected,
    output logic       error_corrected,
    output logic [6:0] corrected_codeword,
    output logic [2:0] syndrome
);
    always_comb begin
        // Extract data bits (assuming no errors initially)
        data_out = {codeword_in[6], codeword_in[5], codeword_in[4], codeword_in[2]};
        error_detected = 0;
        error_corrected = 0;
        corrected_codeword = codeword_in;
        
        // Calculate syndrome
        // S1 = P1 ^ D0 ^ D1 ^ D3
        syndrome[0] = codeword_in[0] ^ codeword_in[2] ^ codeword_in[4] ^ codeword_in[6];
        
        // S2 = P2 ^ D0 ^ D2 ^ D3  
        syndrome[1] = codeword_in[1] ^ codeword_in[2] ^ codeword_in[5] ^ codeword_in[6];
        
        // S4 = P4 ^ D1 ^ D2 ^ D3
        syndrome[2] = codeword_in[3] ^ codeword_in[4] ^ codeword_in[5] ^ codeword_in[6];
        
        if (syndrome != 3'b000) begin
            error_detected = 1;
            
            // Syndrome directly gives us error position (1-indexed)
            // Convert to 0-indexed and correct the bit
            if (syndrome >= 1 && syndrome <= 7) begin
                logic [6:0] trial;
                trial = codeword_in;
                trial[syndrome - 1] ^= 1'b1;  // Correct the error
                corrected_codeword = trial;
                
                // Extract corrected data
                data_out = {trial[6], trial[5], trial[4], trial[2]};
                error_corrected = 1;
            end
        end
    end
endmodule

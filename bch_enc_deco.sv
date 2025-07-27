module bch_decoder_15_5 (
    input  logic [14:0] codeword_in,
    output logic [4:0]  data_out,
    output logic        error_detected,
    output logic        error_corrected,
    output logic [14:0] corrected_codeword,
    output logic [9:0]  syndrome
);
    localparam logic [10:0] generator = 11'b10100110111;  // G(x) of (15,5) BCH
    logic [14:0] trial;
    integer i, j;
    logic found;  // control flag
    
    // Syndrome calculator function
    function automatic logic [9:0] compute_syndrome(input logic [14:0] cw);
        logic [14:0] dividend = cw;
        for (int k = 14; k >= 10; k--) begin
            if (dividend[k]) begin
                for (int b = 0; b < 11; b++) begin
                    dividend[k - b] ^= generator[10 - b];
                end
            end
        end
        return dividend[9:0];
    endfunction
    
    always_comb begin
        data_out         = codeword_in[14:10];
        error_detected   = 0;
        error_corrected  = 0;
        corrected_codeword = codeword_in;
        syndrome         = compute_syndrome(codeword_in);
        found            = 0;
        
        if (syndrome != 10'b0) begin
            error_detected = 1;
            
            // Try 1-bit error correction
            for (i = 0; i < 15; i++) begin
                trial = codeword_in;
                trial[i] ^= 1'b1;
                if (compute_syndrome(trial) == 10'b0) begin
                    corrected_codeword = trial;
                    data_out = trial[14:10];
                    error_corrected = 1;
                    found = 1;
                    break;
                end
            end
            
            // Try 2-bit error correction (if not already corrected)
            if (!found) begin
                for (i = 0; i < 14 && !found; i++) begin
                    for (j = i + 1; j < 15 && !found; j++) begin
                        trial = codeword_in;
                        trial[i] ^= 1'b1;
                        trial[j] ^= 1'b1;
                        if (compute_syndrome(trial) == 10'b0) begin
                            corrected_codeword = trial;
                            data_out = trial[14:10];
                            error_corrected = 1;
                            found = 1;
                        end
                    end
                end
            end
        end
    end
endmodule

module bch_encoder_15_5 (
    input  logic [4:0]  data_in,
    output logic [14:0] codeword
);
    localparam logic [10:0] generator = 11'b10100110111;
    logic [14:0] temp;
    integer i;
    
    always_comb begin
        // Initialize dividend with data_in and 10 zero bits
        temp = {data_in, 10'b0};
        
        // Perform modulo-2 division
        for (i = 14; i >= 10; i--) begin
            if (temp[i]) begin
                temp[i -: 11] ^= generator;
            end
        end
        
        // Append remainder to original data
        codeword = {data_in, temp[9:0]};
    end
endmodule
// Code your design here
module hamming_encoder_7_4 (
    input  logic [3:0] data_in,
    output logic [6:0] codeword
);
    logic p1, p2, p4;  // Parity bits
    
    always_comb begin
        // Calculate parity bits
        // P1 covers positions 1,3,5,7 (bits 0,2,4,6 in 0-indexed)
        p1 = data_in[0] ^ data_in[1] ^ data_in[3];
        
        // P2 covers positions 2,3,6,7 (bits 1,2,5,6 in 0-indexed)  
        p2 = data_in[0] ^ data_in[2] ^ data_in[3];
        
        // P4 covers positions 4,5,6,7 (bits 3,4,5,6 in 0-indexed)
        p4 = data_in[1] ^ data_in[2] ^ data_in[3];
        
        // Construct codeword: [d3 d2 d1 p4 d0 p2 p1]
        codeword = {data_in[3], data_in[2], data_in[1], p4, data_in[0], p2, p1};
    end
endmodule

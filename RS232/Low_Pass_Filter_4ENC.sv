// for encoder 
module Low_Pass_Filter_4ENC
(
	output logic sig_filter,	
	input signal,	
	input [13:0] r_LPF_threshold_enc,  //	Unit : 0.08us  /// 2^3 = 8,  r_LPF_threshold_enc=0 => By Pass
	input clk, 
	input reset
);

//// ---------------- internal constants --------------
	parameter N = 13 ;		

	logic [N-1 : 0] counter;							// timing regs
	logic reset_counter;							
	logic LPF_threshold;
	//assign counter
	logic [4:0] q;
	always @(posedge clk)
		begin
			if(reset)
				begin
					q 				<= 5'b0;
					sig_filter 		<= signal;
					//sig_filter 		<= 0;
					reset_counter 	<= 0;
					LPF_threshold 	<= 0;
				end
			else 
				begin
					q[4:0] 				<= {q[3:0], signal};
					if (LPF_threshold) 	sig_filter <= q[4];
					reset_counter 		<= q[1]^q[0];
					//LPF_threshold 		<= (counter[N-1: 4] >= r_LPF_threshold_enc);
					LPF_threshold 		<= (counter[N-1: 0] >= r_LPF_threshold_enc);
				end
		end
	
	always @(posedge clk)
		begin
			if(reset | reset_counter)
				counter <= 0;
			else 
				if (~counter[N-1]) counter <= counter + 1;
		end
		
endmodule

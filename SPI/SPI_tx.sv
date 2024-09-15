module SPI_tx(
	input logic clk, // 100MHz
	input logic sclk, // counter
	input logic rst,
	input logic tx_req,
	input logic[15:0] data,
	output logic miso
);
	
	typedef enum{INIT, START_SPI_TX, SEND_DATA, FINISH} state_t;
	state_t ps, ns;
	
	// 在負緣時傳送資料
	logic sclk_negedge;
	negedge_detector negedge_detector_u2(
		.clk(clk),
		.rst(rst),
		.enc_filter(sclk),
		.enc_neg(sclk_negedge)
	);
	
	// counter 計算傳送幾筆資料
	logic send_data_counter_reset;
	logic[31:0] send_data_counter;
	always_ff @(posedge clk) begin
		if(rst | send_data_counter_reset)
			send_data_counter <= 32'h00000000;
		else if(sclk_negedge)
			send_data_counter <= send_data_counter + 1;
	end

	// FSM
	always_ff @(posedge clk) begin
		if(rst)
			ps <= INIT;
		else
			ps <= ns;
	end

	// shift register 輸出miso
	logic load_shift_data;
	logic[15:0] shift_data;
	always_ff @(posedge clk) begin
		if(rst)
			shift_data <= 16'h0000;
		else if(load_shift_data)
			shift_data <= data;
		else if(sclk_negedge)
			{miso, shift_data[15:1]} <= shift_data;
	end

	// controller
	always_comb begin 
		send_data_counter_reset = 0;	
		load_shift_data = 0;
		ns = ps;
		case(ps)
			INIT:
				begin
					send_data_counter_reset = 1;
					ns = START_SPI_TX;
				end
			START_SPI_TX:
				begin // 收到傳送訊息請求
					if(tx_req == 1) begin
						load_shift_data = 1;
						ns = SEND_DATA;
					end
				end
			SEND_DATA:
				begin // 傳送 16bits 的資料
					if(send_data_counter >= 16) begin
						send_data_counter_reset = 1;
						ns = FINISH;
					end
				end
			FINISH:
				begin
					ns = INIT;
				end
		endcase
	end
	
endmodule
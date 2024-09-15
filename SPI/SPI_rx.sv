`timescale 1ns/1ps
module SPI_rx(
	input logic clk, // 100MHz
	input logic sclk, // counter
	input logic rst,
	input logic ssn, // 決定master要和哪個slave傳輸資料
	input logic mosi, // master傳送資料到slave slave接收從master傳來的資料
	output logic[7:0] address,
	output logic[15:0] data,
	output logic[15:0] read_data,
	output logic read_en,
	output logic write_en,
	output logic tx_req
);
	logic rx_finish;
	typedef enum{INIT, START_SPI_RX, RECEIVE_ADDRESS, DUMMY, CHECK_COMMAND, RECEIVE_DATA, TX_REQ, FINISH, WRITE} state_t;
	state_t ps, ns;
	
	// 偵測與slave開始通信
	logic ssn_negedge;
	negedge_detector negedge_detector_u1(
		.clk(clk),
		.rst(rst),
		.enc_filter(ssn),
		.enc_neg(ssn_negedge)
	);
	
	// clk正緣偵測
	logic sclk_posedge;
	posedge_detector posedge_detector_u1(
		.clk(clk),
		.rst(rst),
		.enc_filter(sclk),
		.enc_pos(sclk_posedge)
	);
	
	// FSM
	always_ff @(posedge clk) begin
		if(rst)
			ps <= INIT;
		else
			ps <= ns;
	end

	// counter
	logic receive_data_counter_reset;
	logic[31:0] receive_data_counter;
	always_ff @(posedge clk) begin
		if(rst | receive_data_counter_reset)
			receive_data_counter <= 32'h00000000;
		else if(sclk_posedge)
			receive_data_counter <= receive_data_counter + 1;
	end

	// shift register
	logic[15:0] shift_data;
	always_ff @(posedge clk) begin 
		if(rst)
			shift_data <= 16'h0000;
		else if(sclk_posedge) // MSB先送
			shift_data <= {shift_data[14:0], mosi};
	end
	
	// register
	logic command;
	logic load_address, load_data, load_command;
	always_ff @(posedge clk) begin
		if(rst) begin
			address <= 8'h00;
			data <= 16'h0000;
			command <= 1'b0;
		end
		else if(load_address)
			address <= shift_data[7:0];
		else if(load_data)
			data <= shift_data;
		else if(load_command)
			command <= shift_data[7];
	end
	
	// register file
	logic[15:0] reg_file [255:0];
	//logic[15:0] read_data;
	always_ff @(posedge clk) begin
		if(write_en)
			reg_file[address] <= data;
		else 
			read_data <= reg_file[address];
	end
	
	// controller
	always_comb begin
		receive_data_counter_reset = 0;
		load_address = 0;
		load_command = 0;
		load_data = 0;
		write_en = 0;
		read_en = 0;
		tx_req = 0;
		rx_finish = 0;
		ns = ps;
		case(ps)
			INIT: 
				begin
					receive_data_counter_reset = 1;
					ns = START_SPI_RX;
				end
			START_SPI_RX:
				begin
					if(ssn_negedge) begin 
						// 需要將 read 階段的counter reset
						receive_data_counter_reset = 1;
						ns = RECEIVE_ADDRESS;
					end
				end
			RECEIVE_ADDRESS:
				begin
					if(receive_data_counter >= 8) begin
						load_address = 1;
						ns = DUMMY;
					end
				end
			DUMMY:
				begin
					if(receive_data_counter >= 16) begin
						load_command = 1;
						receive_data_counter_reset = 1;
						ns = CHECK_COMMAND;
					end
				end
			CHECK_COMMAND:
				begin
					if(command == 0) begin
						ns = RECEIVE_DATA;
					end
					else if(command == 1) begin
						//read_en = 1;
						ns = TX_REQ;
					end
				end
			RECEIVE_DATA:
				begin
					if(receive_data_counter >= 16) begin
						load_data = 1;
						receive_data_counter_reset = 1;
						ns = WRITE;
					end
				end
			WRITE:
				begin
					write_en = 1;
					ns = FINISH;
				end
			TX_REQ: 
				begin
					tx_req = 1;
					ns = FINISH;
				end
			FINISH:
				begin
					rx_finish = 1;
					ns = INIT;
				end
		endcase
	end
	
endmodule
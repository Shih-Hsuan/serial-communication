`timescale 1ns/100ps
module rs232(
	input logic clk,
	input logic rst,
	input logic[13:0] r_LPF_threshold,
	input logic rx,
	output logic tx,
	output logic[7:0] rx_data
);
	logic rx_finish;
	typedef enum{START, RX_START, NUM_BITS, RECEIVE, COMPLETE, RW_REG_F, TX_REQ_1, TX_ACK_1, TX_REQ_2, TX_ACK_2, TX_REQ_3, TX_ACK_3, TX_REQ_4, TX_ACK_4} state_t;
	state_t ps, ns;
	
	// FSM
	always_ff @(posedge clk) begin
		if(rst)
			ps <= START;
		else	
			ps <= ns;
	end
	
	// Low Pass Filter
	logic rx_filter;
	Low_Pass_Filter_4ENC Low_Pass_Filter_4ENC_1(
		.clk(clk),
		.reset(rst),
		.signal(rx),
		.r_LPF_threshold_enc(r_LPF_threshold), // 20
		.sig_filter(rx_filter) // output
	);
	
	// negedge detector
	logic s_signal, d_signal, rx_neg;
	always_ff @(posedge clk) begin
		if(rst) begin
			s_signal <= 1'b1;
			d_signal <= 1'b1;
			rx_neg <= 1'b0;
		end
		else begin
			{d_signal, s_signal} <= {s_signal, rx_filter};
			rx_neg <= ~s_signal & d_signal;
		end
	end
	
	// bit counter ( 在每一個bit的中間抓取資料，確保資料穩定 )
	logic rst_bit_cnt, bit_flag;
	logic[5:0] bit_cnt;
	always_ff @(posedge clk) begin
		if(rst | rst_bit_cnt)
			bit_cnt <= 0;
		else if(bit_flag)
			bit_cnt <= bit_cnt + 1;
	end
	
	// baud couter: Baud rate = 38400bit/s = 38400bit/50000000clk
	logic[15:0] baud_cnt;
	logic BAUD_CNT_MAX, BAUD_CNT_MAX_HALF;
	assign BAUD_CNT_MAX = baud_cnt >= 16'b0000010100010110; // 1302 clk
	assign BAUD_CNT_MAX_HALF = baud_cnt == 16'b0000001010001011; // 652 clk
	logic rst_baud_cnt;
	always_ff @(posedge clk) begin
		if(rst | rst_baud_cnt)
			baud_cnt <= 0;
		else	
			baud_cnt <= baud_cnt + 1;
	end
	
	// shift register
	always_ff @(posedge clk) begin
		if(rst)
			rx_data <= 0;
		else if(bit_flag) begin // 右移 LSB先送
			rx_data <= {rx, rx_data[7:1]}; 
		end
	end
	
	// check sum counter 
	logic rst_chk_sum_temp, add_chk_sum, load_chk_sum;
	logic[7:0] chk_sum_temp;
	logic[7:0] chk_sum;
	always_ff @(posedge clk) begin
		if(rst | rst_chk_sum_temp)
			chk_sum_temp <= 0;
		else if(add_chk_sum) // checksum以前所有接收到的資料加總
			chk_sum_temp <= chk_sum_temp + rx_data;
		//else if(load_chk_sum) // 移置 pkg shift reg 否則會造成 chk_sum 同時賦值
			//chk_sum <= chk_sum_temp;
	end
	
	// package counter 完整收到1個8bits的資料
	logic rst_pkg_cnt, pkg_ready;
	logic[2:0] pkg_cnt;
	always_ff @(posedge clk) begin
		if(rst | rst_pkg_cnt)
			pkg_cnt <= 3'b000;
		else if(rx_finish)
			pkg_cnt <= pkg_cnt + 1;
	end
	
	// package shift register
	logic[7:0] head;
	logic[7:0] addr1;
	logic[7:0] addr2;
	logic[7:0] data1;
	logic[7:0] data2;
	logic[7:0] r_w;
	logic[7:0] tail;
	always_ff @(posedge clk) begin
		if(rst) begin
			head <= 0;
			addr1 <= 0;
			addr2 <= 0;
			data1 <= 0;
			data2 <= 0;
			r_w <= 0;
			chk_sum <= 0;
			tail <= 0;
		end
		else if(rx_finish) begin
			tail <= rx_data;
			if(pkg_ready == 0)
				chk_sum <= tail;
			else if(load_chk_sum)
				chk_sum <= chk_sum_temp;
			r_w <= chk_sum;
			data2 <= r_w;
			data1 <= data2;
			addr2 <= data1;
			addr1 <= addr2;
			head <= addr1;
		end
	end
	
	// register file 256 * 8-bit
	logic write;
	logic[7:0] addr, data, data_r;
	logic[7:0] reg_file [255:0];
	assign addr = {addr1[3:0], addr2[3:0]}; // 格式:16'h3_3_
	assign data = {data1[3:0], data2[3:0]}; // 格式:16'h3_3_
	always_ff @(posedge clk) begin
		if(write)
			reg_file[addr] <= data;
	end
	assign data_r = reg_file[addr];
	
	
	// tx_idx 輸出的封包格式
	logic rst_tx_idx, inc_tx_idx;
	logic[1:0] tx_idx;
	logic[7:0] tx_data;
	logic[7:0] tx_data_temp [3:0];
	assign tx_data_temp[0] = 8'h02;
	assign tx_data_temp[1] = {4'h3, data_r[7:4]};
	assign tx_data_temp[2] = {4'h3, data_r[3:0]};
	assign tx_data_temp[3] = 8'h03;
	always_ff @(posedge clk) begin
		if(rst | rst_tx_idx) begin
			tx_data <= 0;
			tx_idx <= 0;
		end
		else if(inc_tx_idx) begin
			tx_idx <= tx_idx + 1;
			tx_data <= tx_data_temp[tx_idx];
		end
	end
	
	
	// Tx
	logic tx_ack, tx_req;
	rs232_tx rs232_tx_u1(
		.clk(clk),
		.rst(rst),
		.tx_req(tx_req), // 發送請求
		.tx_data(tx_data), // 要發送的資料
		.tx_ack(tx_ack), // 完整傳送完一筆資料
		.tx(tx)  // 傳送訊號
	);

	// controller
	always_comb begin
		rst_baud_cnt = 0;
		rst_bit_cnt = 0;
		bit_flag = 0;
		rx_finish = 0;
		rst_pkg_cnt = 0;
		pkg_ready = 0;
		write = 0;
		rst_tx_idx = 0;
		inc_tx_idx = 0;
		tx_req = 0;
		rst_chk_sum_temp = 0;
		add_chk_sum = 0;
		load_chk_sum = 0;
		ns = ps;
		case(ps)
			START: 
				begin
					rst_tx_idx = 1;
					rst_chk_sum_temp = 1;
					ns = RX_START;
				end
			RX_START: // 偵測到負緣觸發 開始計算bit數
				begin
					if(rx_neg)
						ns = NUM_BITS;
				end
			NUM_BITS:
				begin
					rst_baud_cnt = 1;
					if(bit_cnt > 8) // data: 8bits 
						ns = COMPLETE;
					else
						ns = RECEIVE;
				end
			RECEIVE:
				begin // 在每一個bit的中間抓取資料，確保資料穩定
					if(BAUD_CNT_MAX_HALF)
						bit_flag = 1;
					if(BAUD_CNT_MAX)
						ns = NUM_BITS;
				end
			COMPLETE:
				begin
					rst_bit_cnt = 1;
					rx_finish = 1;
					if(pkg_cnt == 7) begin
						load_chk_sum = 1;
						rst_pkg_cnt = 1;
						pkg_ready = 1;
						rst_chk_sum_temp = 1;
						ns = RW_REG_F;
					end
					if(pkg_cnt < 6) begin
						add_chk_sum = 1;
						ns = RX_START;
					end
					if(pkg_cnt == 6) begin
						//load_chk_sum = 1;
						ns = RX_START;
					end
				end
			RW_REG_F:
				begin
					if(r_w[0] == 1) begin
						write = 1; // 寫入 RefFile
						ns = RX_START;
					end
					else 
						ns = TX_REQ_1;
				end
			TX_REQ_1:
				begin // 請求發送第一筆資料
					tx_req = 1;
					inc_tx_idx = 1;
					ns = TX_ACK_1;
				end
			TX_ACK_1:
				begin // 是否正確接收資料
					if(tx_ack == 1)
						ns = TX_REQ_2;
				end
			TX_REQ_2:
				begin
					tx_req = 1;
					inc_tx_idx = 1;
					ns = TX_ACK_2;
				end
			TX_ACK_2:
				begin
					if(tx_ack == 1)
						ns = TX_REQ_3;
				end
			TX_REQ_3:
				begin
					tx_req = 1;
					inc_tx_idx = 1;
					ns = TX_ACK_3;
				end
			TX_ACK_3:
				begin
					if(tx_ack == 1)
						ns = TX_REQ_4;
				end
			TX_REQ_4:
				begin
					tx_req = 1;
					inc_tx_idx = 1;
					ns = TX_ACK_4;
				end
			TX_ACK_4:
				begin
					if(tx_ack == 1)
						ns = START;
				end
		endcase
	end
endmodule
`timescale 1ns/100ps
module rs232_tx(
	input logic clk,
	input logic rst,
	input logic tx_req, // 發送請求
	input logic[7:0] tx_data, // 要發送的資料
	output logic tx_ack, // 完整傳送完一筆資料
	output logic tx  // 傳送訊號
);
	logic bdcnt_rst, load_tx_data, shift_enable, bit_rst;
	logic[4:0] bit_cnt;
	logic[9:0] shift_reg;
	logic[11:0] baud_cnt, BAUD_CNT_MAX;
	typedef enum{IDLE, CHK_REQ, LD_TX_DATA, CHK_BIT_CNT, TRANS, COMP} state_t;
	state_t ps, ns;
	
	// BAUD_CNT_MAX = 1302, clk = 50MHz,  鮑率 = 38400(bit/s)
	assign BAUD_CNT_MAX = 11'b10100010110;
	always_ff @(posedge clk) begin
		if(rst | bdcnt_rst)
			baud_cnt <= #1 12'b000000000000;
		else 
			baud_cnt <= #1 baud_cnt + 1;
	end

	// bit counter 傳輸幾個位元
	always_ff @(posedge clk) begin
		if(rst | bit_rst)
			bit_cnt <= #1 5'b00000;
		else if(shift_enable)
			bit_cnt <= #1 bit_cnt + 1;
	end
	
	//shift register
	always_ff @(posedge clk) begin
		if(rst) begin
			tx <= 1'b1;
			shift_reg <= #1 10'b0000000000;
		end
		else if(load_tx_data) // STOP DATA START
			shift_reg <= #1 {1'b1, tx_data[7:0], 1'b0};
		else if(shift_enable) 
			{shift_reg, tx} <= #1 {1'b1, shift_reg};
	end
	
	// fsm
	always_ff @(posedge clk) begin
		if(rst)
			ps <= IDLE;
		else
			ps <= ns;
	end
	
	// controller
	always_comb begin
		bdcnt_rst = 0;
		load_tx_data = 0;
		shift_enable = 0;
		bit_rst = 0;
		tx_ack = 0;
		ns = ps;
		case(ps)
			IDLE:
				begin
					ns = CHK_REQ;
				end
			CHK_REQ:
				begin
					if(tx_req)
						ns = LD_TX_DATA;
				end
			LD_TX_DATA:
				begin // 載入要傳送的資料
					load_tx_data = 1;
					ns = CHK_BIT_CNT;
				end
			CHK_BIT_CNT:
				begin // 檢查已經傳送完多少個bit
					if(bit_cnt == 10) begin
						bit_rst = 1;
						ns = COMP;
					end
					else	
						ns = TRANS;
				end
			TRANS:
				begin // 傳送 1 個 bit
					if(baud_cnt >= BAUD_CNT_MAX) begin
						bdcnt_rst = 1;
						shift_enable = 1;
						ns = CHK_BIT_CNT;
					end
				end
			COMP:
				begin // 傳送完畢
					if(tx_req == 0)	begin
						tx_ack = 1;
						ns = CHK_REQ;
					end
				end
		endcase
	end
	
endmodule
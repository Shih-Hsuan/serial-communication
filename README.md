# RS232 與 SPI 測試說明
## RS232 測試
### 測試說明:
1. 接收並解析整個 package 資料，依格式將資料分類輸出，並結合 RS-232 Transmitter 將資料依照 package 格式回傳。
2. 輸入:
   * clk : 50M
   * rst 
   * rx : 接收到資料(1-bit)
3. 輸出
   * head[7:0] : 8’h02
   * addr[7:0] : 解析完的真實 address
   * data[7:0] : 解析完的真實 data
   * r_w[7:0] : 讀取(8’h00)或是寫入(8’h01)
   * tail[7:0] : 8’h03
   * pkg_ready : 標示完整接收到 1 個 package 的 trigger。
   * tx_data[7:0] : 要給 transmitter 回傳的資料。
   * tx : 傳出去的資料(1-bit)
4. 測資:
   * 8’h02, 8’h30, 8’h32, 8’h30, 8’h33, 8’h01, 8’h03
   * 8’h02, 8’h30, 8’h32, 8’h00, 8’h00, 8’h00, 8’h03
### 測試結果: <br/>
![image](https://github.com/user-attachments/assets/89bcebaa-7d79-4e65-8cfd-9a4de2994aa7)
### 結論與心得:
此專案完整實現 RS232 的傳輸功能，首先可讀取從其他 device 透過 rs232 傳出的資料，先用低通濾波器過濾，再進入 Rx，可透過傳入的第 6 個 byte 資料判斷是否要寫入/讀取暫存器檔案，若是讀取，則會藉由傳入的第 2、3 個 byte 得到暫存器檔案的地址並透過 Tx 輸出資料該地址的暫存器檔案資料。這次作業有點難度，需要很清楚每個小元件的功能，才能撰寫出整體架構。

---
## SPI 測試
### SPI Slave 測試說明:
1. 完成 SPI Slave 的接收與傳輸功能，並顯示其模擬圖。
2. SPI Slave 功能說明
   * 若收到寫入指令，依序接收 32 位元 mosi 資料，依照資料格式將資料寫進 register file。
   * 若收到讀取指令，將資料從 register file 中讀出來，並依序傳至miso 接腳。
3. testbench.sv 會呼叫 DE0_CV.sv，請在 DE0_CV.sv 中完成程式碼撰寫。
4. DE0_CV.sv 使用接腳：
   * CLOCK_50：50MHz 的 clk 訊號。
   * RESET_N：系統 reset，為 0 時重置系統。
   * GPIO_0[0]：傳訊號進 SPI Slave 的 mosi。
   * GPIO_0[1]：傳訊號進 SPI Slave 的 sclk。
   * GPIO_0[2]：傳訊號進 SPI Slave 的 ssn。
   * GPIO_0[3]：接收 SPI Slave 的 miso 訊號。
5. SPI.sv 輸入:
   * clk (請將 DE0_CV 的 CLOCK_50，用 PLL 升至 100MHz)
   * mosi
   * sclk(testbench 已設定為 10MHz)
   * ssn 
   * reset
6. SPI.sv 輸出:
   * data_debug [15:0](將讀取的 register file 資料接出來)
   * miso
### 測試結果: <br/>
![image](https://github.com/user-attachments/assets/f05f5f9f-7e7b-4c06-8dbd-0864375f1cdb)
### 結論與心得:
此專案完整實作 SPI Slave 的接收與傳輸功能，主要是由 SPI RX、RegisterFile和 SPI TX 三個 module 組成，在程式撰寫上需要注意的是 SPI 與 RS232 不同，它是由 MSB 開始傳遞資料，傳輸格式為 8bits address + 1bit command + 7bits don`t care + 16bits data，其中可以透過 command 來判斷資料是要做讀、寫。

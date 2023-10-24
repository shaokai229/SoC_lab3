# SoC_lab3 FIR

# Design specification
* Data Width 32
* Data Num TBD - Based on size of data file
* Interface
  - data_in: stream (Xn)
  - data_out: stream (Yn)
  - coef[Tape_Num-1:0] axilite
  - len: axilite
  - ap_start: axilite
  - ap_done: axilite
* Using one Multiplier and one Adder
* Shift register implemented with SRAM (Shift_RAM, size = 10 DW) – size = 10 DW
* Tap coefficient implemented with SRAM (Tap_RAM = 11 DW) and initialized by axilite write
* Operation
  - ap_start to initiate FIR engine (ap_start valid for one clock cycle)
  - Stream-in Xn. The rate is depending on the FIR processing speed. Use axi-stream valid/ready for flow control
  - Stream out Yn, the output rate depends on FIR processing speed

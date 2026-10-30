// Tang Nano 20K 板载晶振 27 MHz -> 周期 37.037 ns
create_clock -name clk_27M -period 37.037 -waveform {0 18.518} [get_ports {clk}]

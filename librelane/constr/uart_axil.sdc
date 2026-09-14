# uart_axil constraints
# Default 50 MHz (20 ns), same intent as quartus/uart2seg.sdc.

if { [info exists ::env(CLOCK_PERIOD)] } {
    set clk_period $::env(CLOCK_PERIOD)
} else {
    set clk_period 20.0
}

create_clock -name i_clk -period $clk_period [get_ports {i_clk}]

# Active-low async reset
set_false_path -from [get_ports {i_rst_n}]

# UART serial pin is asynchronous to i_clk (sampled inside uart_rx)
set_false_path -from [get_ports {i_rx}]
set_false_path -to   [get_ports {o_tx}]

# Define clocks
netlist clock clk -period 10 

# Constrain rst
netlist constraint resetb -value 1'b1 -after_init

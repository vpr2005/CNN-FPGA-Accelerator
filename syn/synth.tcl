#-----------------------------------------------------------------------------
# File: synth.tcl
# Description: Batch synthesis script for Vivado targeting AMD/Xilinx Artix-7.
#              Generates resource utilization, timing, and power reports.
#-----------------------------------------------------------------------------

set part "xc7a100tcsg324-1"
set top_module "cnn_top"
set output_dir "syn/reports"

file mkdir $output_dir

# Read SystemVerilog RTL sources
read_verilog -sv [glob rtl/*.sv]

# Read Timing Constraints
read_xdc syn/constraints.xdc

# Run Synthesis (Out of Context mode for IP core accelerator)
synth_design -top $top_module -part $part -mode out_of_context

# Generate detailed reports
report_utilization -file "$output_dir/utilization.rpt"
report_utilization -hierarchical -file "$output_dir/utilization_hierarchical.rpt"
report_timing_summary -file "$output_dir/timing_summary.rpt"
report_power -file "$output_dir/power.rpt"

puts "==========================================================="
puts ">>> VIVADO SYNTHESIS COMPLETED SUCCESSFULLY! <<<"
puts ">>> Reports saved to: $output_dir <<<"
puts "==========================================================="

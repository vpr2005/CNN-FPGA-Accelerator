#-----------------------------------------------------------------------------
# File: create_project.tcl
# Description: Generates a complete Vivado GUI Project (.xpr) for the
#              CNN FPGA Accelerator, pre-configured with all sources,
#              testbenches, data files, and constraints.
#-----------------------------------------------------------------------------

set script_path [file normalize [info script]]
set script_dir  [file dirname $script_path]
set repo_dir    [file normalize "$script_dir/.."]
set proj_name   "cnn_accelerator"
set proj_dir    [file normalize "$repo_dir/vivado_project"]
set part_num    "xc7a100tcsg324-1"

puts "=========================================================="
puts "Repository Root:   $repo_dir"
puts "Creating Project:  $proj_name"
puts "Target Device:     $part_num"
puts "Project Output:    $proj_dir"
puts "=========================================================="

# Create project
create_project -force $proj_name $proj_dir -part $part_num

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# 1. Add Synthesizable RTL Source Files
set rtl_files [glob -nocomplain "$repo_dir/rtl/*.sv"]
if {[llength $rtl_files] > 0} {
    add_files -norecurse $rtl_files
    set_property file_type "SystemVerilog" [get_files $rtl_files]
    set_property top cnn_top [current_fileset]
}

# 2. Add Constraints
set xdc_file "$repo_dir/syn/constraints.xdc"
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
}

# 3. Add Simulation Testbenches
set tb_files [glob -nocomplain "$repo_dir/tb/*.sv"]
if {[llength $tb_files] > 0} {
    add_files -fileset sim_1 -norecurse $tb_files
    set_property file_type "SystemVerilog" [get_files $tb_files]
    set_property top tb_cnn_top [get_filesets sim_1]
    set_property top_lib xil_defaultlib [get_filesets sim_1]
}

# 4. Add Memory (.mem) Stimulus Data Files to Simulation Fileset
set mem_files [glob -nocomplain "$repo_dir/data/*.mem"]
if {[llength $mem_files] > 0} {
    add_files -fileset sim_1 -norecurse $mem_files
}

# Configure simulation settings
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "=========================================================="
puts ">>> Vivado Project created successfully! <<<"
puts "Project File: $proj_dir/$proj_name.xpr"
puts "=========================================================="

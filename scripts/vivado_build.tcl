# Build the Arty A7-100T demonstration from a clean Vivado batch session.
# Run from the repository root:
#   vivado -mode batch -source scripts/vivado_build.tcl

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set build_dir [file join $repo_dir build vivado]

file mkdir $build_dir
create_project -force rv32i_arty_a7 $build_dir -part xc7a100tcsg324-1

set rtl_files [list \
  [file join $repo_dir rtl rv32i_pkg.sv] \
  [file join $repo_dir rtl rv32i_alu.sv] \
  [file join $repo_dir rtl rv32i_imm_gen.sv] \
  [file join $repo_dir rtl rv32i_regfile.sv] \
  [file join $repo_dir rtl rv32i_decoder.sv] \
  [file join $repo_dir rtl rv32i_core.sv] \
  [file join $repo_dir rtl rv32i_soc.sv] \
  [file join $repo_dir fpga arty_a7_100t_top.sv]]

add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $repo_dir fpga arty_a7_100t.xdc]
add_files -norecurse [file join $repo_dir sim programs fpga_demo.hex]
set_property file_type {Memory Initialization Files} [get_files fpga_demo.hex]
set_property top arty_a7_100t_top [current_fileset]

update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1
report_utilization -file [file join $repo_dir reports post_synth_utilization.rpt]
report_timing_summary -file [file join $repo_dir reports post_synth_timing.rpt]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
report_utilization -file [file join $repo_dir reports post_route_utilization.rpt]
report_timing_summary -file [file join $repo_dir reports post_route_timing.rpt]

puts "Bitstream: [file join $build_dir rv32i_arty_a7.runs impl_1 arty_a7_100t_top.bit]"


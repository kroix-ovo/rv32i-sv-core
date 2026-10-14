# Build the Arty or Nexys A7-100T demonstration from a clean batch session.
# Run from the repository root:
#   vivado -mode batch -source scripts/vivado_build.tcl
# Optional arguments: <separate-build-directory> <arty|nexys> <demo|selftest>

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set build_dir [file join $repo_dir build vivado]
set report_dir [file join $repo_dir reports]

# Optional separate output directory preserves earlier implementation evidence.
if {$argc > 0} {
  set build_dir [file normalize [lindex $argv 0]]
  set report_dir [file join $build_dir reports]
}

file mkdir $build_dir
file mkdir $report_dir
set board [expr {$argc > 1 ? [lindex $argv 1] : "arty"}]
if {$board ni {arty nexys}} { error "Board must be arty or nexys" }
set project_name rv32i_${board}_a7
set top ${board}_a7_100t_top
set program [expr {$argc > 2 ? [lindex $argv 2] : "demo"}]
if {$program ni {demo selftest}} { error "Program must be demo or selftest" }
if {$program eq "selftest"} {
  if {$board ne "nexys"} { error "Self-test target currently requires nexys" }
  set top nexys_a7_selftest_top
}
create_project -force $project_name $build_dir -part xc7a100tcsg324-1

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
if {$board eq "nexys"} {
  add_files -norecurse [file join $repo_dir fpga nexys_a7_100t_top.sv]
  if {$program eq "selftest"} {
    add_files -norecurse [file join $repo_dir fpga nexys_a7_selftest_top.sv]
  }
}
add_files -fileset constrs_1 -norecurse [file join $repo_dir fpga ${board}_a7_100t.xdc]
set image fpga_${program}.hex
add_files -norecurse [file join $repo_dir sim programs $image]
set_property file_type {Memory Initialization Files} [get_files $image]
set_property top $top [current_fileset]

update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_timing_summary -file [file join $report_dir post_synth_timing.rpt]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -file [file join $report_dir post_route_timing.rpt]

# A successful bitstream write does not mean the 100 MHz clock met timing.
# Read the routed report and fail the batch command when setup slack is less
# than zero. The report remains available for diagnosis in either case.
set timing_file [open [file join $report_dir post_route_timing.rpt] r]
set timing_text [read $timing_file]
close $timing_file
if {![regexp {WNS\(ns\)[^\n]*\n[^\n]*\n[ \t]*(-?[0-9]+\.[0-9]+)[ \t]+} $timing_text -> wns]} {
  error "Could not read routed WNS from post_route_timing.rpt"
}
set bitstream [file join $build_dir ${project_name}.runs impl_1 ${top}.bit]
if {![file exists $bitstream]} {
  error "Bitstream was not written: $bitstream"
}
puts "Routed WNS: $wns ns"
if {$wns < 0} {
  error "100 MHz setup timing failed; inspect post_route_timing.rpt"
}
puts "Bitstream: $bitstream"

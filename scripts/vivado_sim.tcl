# Run one self-checking testbench in Vivado xsim.
# Optional first argument: tb_alu, tb_core_directed, or tb_core_traps.
# Example:
#   vivado -mode batch -source scripts/vivado_sim.tcl -tclargs tb_core_traps

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set test_top [expr {$argc > 0 ? [lindex $argv 0] : "tb_core_directed"}]

if {$test_top ni {tb_alu tb_core_directed tb_core_traps}} {
  error "Unknown testbench '$test_top'"
}

# launch_simulation needs a saved project in Vivado 2023.2. Each testbench gets
# its own generated directory, so compile state from one top cannot leak into
# another. Source files remain in the repository; Vivado outputs go under build.
set sim_dir [file join $repo_dir build vivado_sim $test_top]
file mkdir $sim_dir
create_project -force rv32i_sim_$test_top $sim_dir -part xc7a100tcsg324-1
set rtl_files [list \
  [file join $repo_dir rtl rv32i_pkg.sv] \
  [file join $repo_dir rtl rv32i_alu.sv] \
  [file join $repo_dir rtl rv32i_imm_gen.sv] \
  [file join $repo_dir rtl rv32i_regfile.sv] \
  [file join $repo_dir rtl rv32i_decoder.sv] \
  [file join $repo_dir rtl rv32i_core.sv] \
  [file join $repo_dir rtl rv32i_soc.sv]]

add_files -norecurse $rtl_files
add_files -fileset sim_1 -norecurse [file join $repo_dir tb ${test_top}.sv]
add_files -fileset sim_1 -norecurse [file join $repo_dir tb rv32i_core_assertions.sv]
add_files -norecurse [file join $repo_dir sim programs rv32i_directed.hex]
set_property top $test_top [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sim_1

# The directed testbench uses a relative $readmemh path. xsim changes its
# working directory, so copy the image to that path in the generated project.
set xsim_dir [file join $sim_dir rv32i_sim_${test_top}.sim sim_1 behav xsim]
file mkdir [file join $xsim_dir sim programs]
file copy -force [file join $repo_dir sim programs rv32i_directed.hex] \
  [file join $xsim_dir sim programs rv32i_directed.hex]

launch_simulation -simset sim_1 -mode behavioral
close_sim

# xsim can return after $fatal without causing Vivado to fail. Check the
# simulator log so a failed testbench gives the shell a nonzero exit status.
set simulation_log [file join $xsim_dir simulate.log]
if {![file exists $simulation_log]} {
  error "Simulation log was not created: $simulation_log"
}
set log_file [open $simulation_log r]
set log_text [read $log_file]
close $log_file
if {[regexp {Fatal:|ERROR:} $log_text] || ![regexp {PASS:} $log_text]} {
  error "Simulation $test_top did not pass; inspect $simulation_log"
}
puts "PASS: Vivado xsim $test_top"

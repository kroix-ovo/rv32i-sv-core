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

create_project -in_memory -part xc7a100tcsg324-1
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
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

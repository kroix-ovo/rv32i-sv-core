# Program volatile FPGA configuration only, and save the device status.
# Usage: vivado -mode batch -source scripts/vivado_program.tcl \
#          -tclargs <bitstream> <status-file> [target-serial]
if {$argc < 2} { error "Expected bitstream and status-file arguments" }
set bitstream [file normalize [lindex $argv 0]]
set status_file [file normalize [lindex $argv 1]]
if {![file exists $bitstream]} { error "Missing bitstream: $bitstream" }
open_hw_manager
connect_hw_server
set targets [get_hw_targets]
if {$argc > 2} { set targets [get_hw_targets */[lindex $argv 2]] }
if {[llength $targets] != 1} { error "Expected exactly one hardware target: $targets" }
current_hw_target [lindex $targets 0]
open_hw_target
set devices [get_hw_devices]
if {[llength $devices] != 1} { error "Expected exactly one FPGA: $devices" }
set device [lindex $devices 0]
if {[get_property PART $device] ne "xc7a100t"} {
  error "Expected xc7a100t, found [get_property PART $device]"
}
set_property PROGRAM.FILE $bitstream $device
program_hw_devices $device
refresh_hw_device $device
set receipt [open $status_file w]
puts $receipt "Target: [current_hw_target]"
puts $receipt "Device: $device"
puts $receipt "Part: [get_property PART $device]"
puts $receipt "Bitstream: $bitstream"
foreach property [list_property $device] {
  if {[string match *REGISTER* $property] || [string match *STATUS* $property]} {
    puts $receipt "${property}: [get_property $property $device]"
  }
}
close $receipt
puts "PROGRAMMING_COMPLETE status-file=$status_file"
close_hw_target
disconnect_hw_server
close_hw_manager

param(
  [string]$Iverilog = "iverilog",
  [string]$Vvp = "vvp"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

python sim/build_programs.py
New-Item -ItemType Directory -Force sim/build | Out-Null

$rtl = @(
  "rtl/rv32i_pkg.sv",
  "rtl/rv32i_alu.sv",
  "rtl/rv32i_imm_gen.sv",
  "rtl/rv32i_regfile.sv",
  "rtl/rv32i_decoder.sv",
  "rtl/rv32i_core.sv",
  "rtl/rv32i_soc.sv"
)

& $Iverilog -g2012 -Wall -s tb_alu -o sim/build/tb_alu.vvp @rtl tb/tb_alu.sv
if ($LASTEXITCODE -ne 0) { throw "ALU compilation failed" }
& $Vvp sim/build/tb_alu.vvp
if ($LASTEXITCODE -ne 0) { throw "ALU test failed" }

& $Iverilog -g2012 -Wall -s tb_core_directed -o sim/build/tb_core_directed.vvp @rtl tb/tb_core_directed.sv
if ($LASTEXITCODE -ne 0) { throw "Directed-core compilation failed" }
& $Vvp sim/build/tb_core_directed.vvp
if ($LASTEXITCODE -ne 0) { throw "Directed-core test failed" }

& $Iverilog -g2012 -Wall -s tb_core_traps -o sim/build/tb_core_traps.vvp @rtl tb/tb_core_traps.sv
if ($LASTEXITCODE -ne 0) { throw "Trap-test compilation failed" }
& $Vvp sim/build/tb_core_traps.vvp
if ($LASTEXITCODE -ne 0) { throw "Trap test failed" }

Write-Host "All RV32I tests passed."

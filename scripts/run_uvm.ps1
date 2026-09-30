param(
  [string]$VivadoBin = "C:\Xilinx\Vivado\2023.2\bin",
  [int]$Seed = 1325
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$out = Join-Path $repo "build\uvm"
New-Item -ItemType Directory -Force $out | Out-Null
$xvlog = Join-Path $VivadoBin "xvlog.bat"
$xelab = Join-Path $VivadoBin "xelab.bat"
$xsim = Join-Path $VivadoBin "xsim.bat"
foreach ($tool in @($xvlog, $xelab, $xsim)) {
  if (!(Test-Path -LiteralPath $tool)) { throw "Missing Vivado simulator tool: $tool" }
}

Push-Location $out
try {
  $sources = @(
    (Join-Path $repo "rtl\rv32i_pkg.sv"),
    (Join-Path $repo "rtl\rv32i_alu.sv"),
    (Join-Path $repo "rtl\rv32i_imm_gen.sv"),
    (Join-Path $repo "rtl\rv32i_regfile.sv"),
    (Join-Path $repo "rtl\rv32i_decoder.sv"),
    (Join-Path $repo "rtl\rv32i_core.sv"),
    (Join-Path $repo "tb\uvm\rv32i_core_if.sv"),
    (Join-Path $repo "tb\uvm\rv32i_uvm_pkg.sv"),
    (Join-Path $repo "tb\uvm\tb_core_uvm.sv")
  )
  & $xvlog -sv -L uvm -i (Join-Path $repo "tb\uvm") @sources 2>&1 |
    Tee-Object -FilePath (Join-Path $out "compile.txt")
  if ($LASTEXITCODE -ne 0) { throw "UVM xvlog compile failed; see build/uvm/compile.txt" }

  & $xelab -L uvm work.tb_core_uvm -s tb_core_uvm -timescale 1ns/1ps 2>&1 |
    Tee-Object -FilePath (Join-Path $out "elaborate.txt")
  if ($LASTEXITCODE -ne 0) { throw "UVM xelab elaboration failed; see build/uvm/elaborate.txt" }

  $program = Join-Path $repo "sim\programs\rv32i_directed.hex"
  if (!(Test-Path -LiteralPath $program)) {
    throw "Missing directed program image; run python sim/build_programs.py"
  }
  Copy-Item -LiteralPath $program -Destination (Join-Path $out "directed.hex") -Force
  Set-Content -Path (Join-Path $out "seed.txt") -Value $Seed
  "run 1 ms`nquit" | Set-Content -Path (Join-Path $out "run.tcl")
  & $xsim tb_core_uvm -tclbatch run.tcl -onerror quit `
    -cov_db_dir coverage -cov_db_name rv32i_uvm 2>&1 |
    Tee-Object -FilePath (Join-Path $out "run.txt")
  if ($LASTEXITCODE -ne 0) { throw "UVM xsim run failed; see build/uvm/run.txt" }
  $log = Get-Content -Raw -Path (Join-Path $out "run.txt")
  if ($log -notmatch "RV32I_UVM_PASS" -or
      $log -match "UVM_ERROR\s*:\s*[1-9]" -or
      $log -match "UVM_FATAL\s*:\s*[1-9]" -or
      $log -match "(^|\s)(ERROR|FATAL):") {
    throw "UVM suite failed or completion marker missing; see build/uvm/run.txt"
  }
  Write-Host "PASS: XSim UVM 1.2 RV32I core suite (seed $Seed)"
} finally {
  Pop-Location
}

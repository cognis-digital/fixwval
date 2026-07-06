<#
.SYNOPSIS
    fixwval installer for Windows.
.DESCRIPTION
    GnuCOBOL (cobc) is not shipped with Windows. Obtain it via one of:
      * MSYS2:      pacman -S mingw-w64-x86_64-gnucobol
      * Chocolatey: choco install gnucobol
      * WSL:        run ./install.sh inside a WSL Ubuntu shell
    Once 'cobc' is on PATH, this script builds fixwval + fwmode and (optionally)
    copies them to a destination on your PATH.
.PARAMETER Dest
    Directory to copy the built binaries into (created if absent).
.EXAMPLE
    ./install.ps1
.EXAMPLE
    ./install.ps1 -Dest "$env:USERPROFILE\bin"
#>
param(
    [string]$Dest = ""
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

$cobc = Get-Command cobc -ErrorAction SilentlyContinue
if (-not $cobc) {
    Write-Host "GnuCOBOL (cobc) was not found on PATH." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Install it with one of:"
    Write-Host "  MSYS2:      pacman -S mingw-w64-x86_64-gnucobol"
    Write-Host "  Chocolatey: choco install gnucobol"
    Write-Host "  WSL:        wsl bash ./install.sh"
    Write-Host ""
    Write-Host "Then re-run:  ./install.ps1"
    exit 1
}

Write-Host ">> building with:" (& cobc --version | Select-Object -First 1)
& cobc -x -free -o fixwval.exe fixwval.cob
& cobc -x -free -o fwmode.exe  fwmode.cob

Write-Host ">> smoke test"
& ./fixwval.exe demos/session_clean.fix | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "   fixwval OK" }

if ($Dest -ne "") {
    if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest | Out-Null }
    Copy-Item fixwval.exe (Join-Path $Dest "fixwval.exe") -Force
    Copy-Item fwmode.exe  (Join-Path $Dest "fwmode.exe")  -Force
    Write-Host ">> installed to $Dest"
}
Write-Host ">> done. Try:  ./fixwval.exe demos/session_broken.fix"

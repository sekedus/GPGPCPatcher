<#
.SYNOPSIS
    Get working directory path for patches
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Import-Module ".\HelperModule.psm1" -Force

$prodDir = "C:\Program Files\Google\Play Games"
$devDir = "C:\Program Files\Google\Play Games Developer Emulator"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Get working directory" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

if (Test-Path $prodDir) {
    $installVersion = Get-InstallVersion -ServiceDir (Join-Path $prodDir "current\service")
    Write-Host "Google Play Games on PC (Prod):" -ForegroundColor Green
    Write-Host "  Version: $installVersion" -ForegroundColor Gray
    Write-Host "  Install path: $prodDir" -ForegroundColor Gray
    Write-Host "  __WORK_DIR__: $(Join-Path $PSScriptRoot "prod-$installVersion")" -ForegroundColor White
    Write-Host ""
}

if (Test-Path $devDir) {
    $installVersion = Get-InstallVersion -ServiceDir (Join-Path $devDir "current\service")
    Write-Host "Google Play Games on PC Developer Emulator (Dev):" -ForegroundColor Green
    Write-Host "  Version: $installVersion" -ForegroundColor Gray
    Write-Host "  Install path: $devDir" -ForegroundColor Gray
    Write-Host "  __WORK_DIR__: $(Join-Path $PSScriptRoot "dev-$installVersion")" -ForegroundColor White
    Write-Host ""
}

if (-not (Test-Path $prodDir) -and -not (Test-Path $devDir)) {
    Write-Host "ERROR: Google Play Games on PC not found!" -ForegroundColor Red
    Write-Host "  Expected paths:" -ForegroundColor Yellow
    Write-Host "    Prod: $prodDir" -ForegroundColor White
    Write-Host "    Dev: $devDir" -ForegroundColor White
    Write-Host ""
}

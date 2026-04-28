<#
.SYNOPSIS
    Patch Service.exe.config to add kernel cmdline parameter
.DESCRIPTION
    Adds androidboot.verifiedbootstate=orange to bypass AVB checks
.PARAMETER Dev
    Use Developer Emulator (DE) paths instead of production version
.PARAMETER WorkDir
    Path to working directory (default to patcher directory)
.EXAMPLE
    .\_Patch-ServiceConfig.ps1
.EXAMPLE
    .\_Patch-ServiceConfig.ps1 -Dev
.EXAMPLE
    .\_Patch-ServiceConfig.ps1 -Dev -WorkDir "..\dev-26.3.725.2"
.NOTES
    Requires: PowerShell 5.1+ (Admin)
    Reference: https://github.com/chsbuffer/hpesuperpower/blob/2688f08fa2cb89790244f2d403f16a3c10ab4d85/UnlockCommand.cs#L37
#>

param(
    [switch]$Dev,
    [string]$WorkDir
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\HelperModule.psm1" -Force

$installDir = Get-InstallDir -Dev:$Dev
$versionName = if ($Dev) { "Dev" } else { "Prod" }
$patcherDir = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrEmpty($WorkDir)) {
    # Default to patcher directory if not set
    $WorkDir = $patcherDir
} elseif (-not [System.IO.Path]::IsPathRooted($WorkDir)) {
    $WorkDir = Join-Path $patcherDir $WorkDir
    $WorkDir = [System.IO.Path]::GetFullPath($WorkDir)
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Service.exe.config Patcher" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if GPGPC is running
Test-Running -Dev:$Dev -InstallDir $installDir

# Check if config exists
$configPath = "$installDir\service\Service.exe.config"
if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: Service.exe.config not found!" -ForegroundColor Red
    Write-Host "  Expected: $configPath" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Version: $versionName" -ForegroundColor Gray
Write-Host "  Target path: $configPath" -ForegroundColor Gray
Write-Host "  Working directory: $WorkDir" -ForegroundColor Gray
Write-Host ""

# Create backup directory if it doesn't exist
$backupDir = Join-Path $WorkDir "backup"
New-Directory -Path $backupDir

# Create backup file
$backupPath = Join-Path $backupDir "Service.exe.config"
if (-not (Test-Path $backupPath)) {
    Write-Host "Creating backup..." -ForegroundColor Green
    Copy-Item $configPath $backupPath
    Write-Host "  Backup: $backupPath" -ForegroundColor Gray
} else {
    Write-Host "Backup already exists: $backupPath" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "Loading XML configuration..." -ForegroundColor Green
Write-Host ""
[xml]$xml = Get-Content $configPath

# Find the EmulatorGuestParameters node
$xpath = "/configuration/applicationSettings/Google.Hpe.Service.Properties.EmulatorSettings/setting[@name='EmulatorGuestParameters']/value"
$node = $xml.SelectSingleNode($xpath)

if ($node -eq $null) {
    Write-Host "ERROR: EmulatorGuestParameters node not found in config!" -ForegroundColor Red
    Write-Host "This might be an unsupported version." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# https://developers.google.com/android/management/reference/rest/v1/VerifiedBootState
$paramToAdd = "androidboot.verifiedbootstate=orange "

# Check if already patched
if ($node.InnerText.Contains($paramToAdd.Trim())) {
    Write-Host "Already patched! Nothing to do." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Current value:" -ForegroundColor White
    Write-Host "$($node.InnerText)" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

Write-Host "Original value:" -ForegroundColor Yellow
Write-Host "$($node.InnerText)" -ForegroundColor White
Write-Host ""

# Apply patch
$node.InnerText = $paramToAdd + $node.InnerText

Write-Host "New value:" -ForegroundColor Yellow
Write-Host "$($node.InnerText)" -ForegroundColor White
Write-Host ""

# Save
Write-Host "Saving configuration..." -ForegroundColor Green
$xml.Save($configPath)

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  SUCCESS: Service.exe.config patched" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Kernel parameter added: androidboot.verifiedbootstate=orange" -ForegroundColor White
Write-Host ""

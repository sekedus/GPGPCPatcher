<#
.SYNOPSIS
    Patch bios.rom to disable secure boot
.DESCRIPTION
    Modifies bios.rom to allow booting unsigned/modified boot images
.PARAMETER Dev
    Use Developer Emulator (DE) paths instead of production version
.PARAMETER WorkDir
    Path to working directory (default to patcher directory)
.EXAMPLE
    .\_Patch-Bios.ps1
.EXAMPLE
    .\_Patch-Bios.ps1 -Dev
.EXAMPLE
    .\_Patch-Bios.ps1 -Dev -WorkDir "..\dev-26.3.725.2"
.NOTES
    Requires: PowerShell 5.1+ (Admin)
    Reference: https://github.com/chsbuffer/hpesuperpower/blob/2688f08fa2cb89790244f2d403f16a3c10ab4d85/UnlockCommand.cs#L15
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
Write-Host "  bios.rom Patcher" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if GPGPC is running
Test-Running -Dev:$Dev -InstallDir $installDir

# Check if config exists
$biosPath = "$installDir\emulator\avd\bios.rom"
if (-not (Test-Path $biosPath)) {
    Write-Host "ERROR: bios.rom not found!" -ForegroundColor Red
    Write-Host "  Expected: $biosPath" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Version: $versionName" -ForegroundColor Gray
Write-Host "  Target path: $biosPath" -ForegroundColor Gray
Write-Host "  Working directory: $WorkDir" -ForegroundColor Gray
Write-Host ""

# Create backup directory if it doesn't exist
$backupDir = Join-Path $WorkDir "backup"
New-Directory -Path $backupDir

# Create backup file
$backupPath = Join-Path $backupDir "bios.rom"
if (-not (Test-Path $backupPath)) {
    Write-Host "Creating backup..." -ForegroundColor Green
    Copy-Item $biosPath $backupPath
    Write-Host "  Backup: $backupPath" -ForegroundColor Gray
} else {
    Write-Host "Backup already exists: $backupPath" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "Reading bios.rom..." -ForegroundColor Green
$bios = [System.IO.File]::ReadAllBytes($biosPath)
Write-Host "  File size: $($bios.Length) bytes ($([math]::Round($bios.Length/1MB, 2)) MB)" -ForegroundColor Gray
Write-Host ""

# Pattern to find and replace
$from = [System.Text.Encoding]::ASCII.GetBytes(" verified_boot_android")
$to = [System.Text.Encoding]::ASCII.GetBytes("          boot_android")  # spaces replace "verified_"

Write-Host "Searching for secure boot verification string..." -ForegroundColor Green

# Find the pattern
$offset = -1
for ($i = 0; $i -le ($bios.Length - $from.Length); $i++) {
    $match = $true
    for ($j = 0; $j -lt $from.Length; $j++) {
        if ($bios[$i + $j] -ne $from[$j]) {
            $match = $false
            break
        }
    }
    if ($match) {
        $offset = $i
        break
    }
}

if ($offset -eq -1) {
    Write-Host "Pattern not found!" -ForegroundColor Yellow
    Write-Host "The BIOS might already be patched, or this is an unsupported version." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host "  Found at offset: 0x$($offset.ToString('X8')) ($offset)" -ForegroundColor Green
Write-Host ""

# Show before/after
$originalBytes = $bios[$offset..($offset + $from.Length - 1)]
$originalString = [System.Text.Encoding]::ASCII.GetString($originalBytes)

Write-Host "Original bytes:" -ForegroundColor Yellow
Write-Host "  '$originalString'" -ForegroundColor White
Write-Host ""

# Apply patch
for ($i = 0; $i -lt $to.Length; $i++) {
    $bios[$offset + $i] = $to[$i]
}

$patchedBytes = $bios[$offset..($offset + $to.Length - 1)]
$patchedString = [System.Text.Encoding]::ASCII.GetString($patchedBytes)

Write-Host "Patched bytes:" -ForegroundColor Yellow
Write-Host "  '$patchedString'" -ForegroundColor White
Write-Host ""

# Write patched BIOS
Write-Host "Writing patched bios.rom..." -ForegroundColor Green
[System.IO.File]::WriteAllBytes($biosPath, $bios)

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  SUCCESS! BIOS patched" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Patch location: 0x$($offset.ToString('X8'))" -ForegroundColor White
Write-Host "  Secure boot: DISABLED" -ForegroundColor White
Write-Host ""

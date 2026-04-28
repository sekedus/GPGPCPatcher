<#
.SYNOPSIS
    Patch boot_a.img using WSL with libmagiskboot.so from Magisk APK
.DESCRIPTION
    PowerShell wrapper that calls magisk_patch-boot.sh in WSL
.PARAMETER Dev
    Use Developer Emulator (DE) paths instead of production version
.PARAMETER BootPath
    Path to boot_a.img file (default: .\{WorkDir}\extracted\boot_a.img)
.PARAMETER MagiskApk
    Path to Magisk.apk file (default: ..\resources\Magisk.apk)
.PARAMETER SuperApk
    Path to superpower.apk file (default: ..\resources\superpower-{versionName}.apk)
.PARAMETER OutputPath
    Path for output patched image (default: .\{WorkDir}\patched\boot_a-patched.img)
.PARAMETER WorkDir
    Path to working directory (default to patcher directory)
.EXAMPLE
    .\_Patch-BootWithMagisk.ps1 -BootPath "D:\Custom_Path\boot_a.img" -MagiskApk "D:\Custom_Path\Magisk.apk" -SuperApk "D:\Custom_Path\superpower.apk" -OutputPath "D:\Custom_Path\boot_a-patched.img" -WorkDir "..\dev-26.3.725.2"
.NOTES
    Requires: PowerShell 5.1+ (Admin) and WSL2 (sudo)
    Reference: 
    - https://github.com/chsbuffer/hpesuperpower/blob/2688f08fa2cb89790244f2d403f16a3c10ab4d85/BootPatchCommand.cs
    - https://github.com/topjohnwu/Magisk/blob/e8a58776f1d7bdf852072ad0baa6eceb9a1e4aac/scripts/boot_patch.sh
    - https://github.com/topjohnwu/Magisk/blob/e8a58776f1d7bdf852072ad0baa6eceb9a1e4aac/scripts/host_patch.sh
#>

param(
    [switch]$Dev,
    [string]$BootPath,
    [string]$MagiskApk,
    [string]$SuperApk,
    [string]$OutputPath,
    [string]$WorkDir
)

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\HelperModule.psm1" -Force

$patcherDir = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrEmpty($WorkDir)) {
    # Default to patcher directory if not set
    $WorkDir = $patcherDir
} elseif (-not [System.IO.Path]::IsPathRooted($WorkDir)) {
    $WorkDir = Join-Path $patcherDir $WorkDir
    $WorkDir = [System.IO.Path]::GetFullPath($WorkDir)
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Magisk Boot Patcher (WSL + libmagiskboot.so)" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# =======================================================
# Check WSL Installation
# =======================================================

Write-Host "Checking prerequisites..." -ForegroundColor Green

try {
    $null = wsl --status 2>&1
    Write-Host "  WSL is installed" -ForegroundColor Gray
} catch {
    Write-Host "ERROR: WSL is not installed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Install WSL by running (as Administrator):" -ForegroundColor Cyan
    Write-Host "  wsl --install" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Get WSL distributions
$wslDistros = wsl --list --quiet |
    Where-Object { $_ -match '\S' } |
    ForEach-Object { $_.Trim() -replace '\x00','' -replace '\r','' }

if ($wslDistros.Count -eq 0) {
    Write-Host "ERROR: No WSL distributions installed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Install a distribution:" -ForegroundColor Cyan
    Write-Host "  wsl --install -d Ubuntu" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Select distribution
$wslDistro = $wslDistros[0]

Write-Host "  Using WSL: $wslDistro" -ForegroundColor Gray
Write-Host ""

# =======================================================
# Validate Input Files
# =======================================================

# Resolve paths
if ([string]::IsNullOrEmpty($BootPath)) {
    $BootPath = Join-Path $WorkDir "extracted\boot_a.img"
} elseif (-not [System.IO.Path]::IsPathRooted($BootPath)) {
    $BootPath = Join-Path $WorkDir $BootPath
    $BootPath = [System.IO.Path]::GetFullPath($BootPath)
}

if ([string]::IsNullOrEmpty($MagiskApk)) {
    $MagiskApk = Join-Path $patcherDir "resources\Magisk.apk"
} elseif (-not [System.IO.Path]::IsPathRooted($MagiskApk)) {
    $MagiskApk = Join-Path $patcherDir $MagiskApk
    $MagiskApk = [System.IO.Path]::GetFullPath($MagiskApk)
}

if ([string]::IsNullOrEmpty($SuperApk)) {
    $superRelease = if ($Dev) { "dev" } else { "prod" }
    $SuperApk = Join-Path $patcherDir "resources\superpower-$superRelease.apk"
} elseif (-not [System.IO.Path]::IsPathRooted($SuperApk)) {
    $SuperApk = Join-Path $patcherDir $SuperApk
    $SuperApk = [System.IO.Path]::GetFullPath($SuperApk)
}

# Check existence
if (-not (Test-Path $BootPath)) {
    Write-Host "ERROR: boot_a.img not found!" -ForegroundColor Red
    Write-Host "  Path: $BootPath" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

if (-not (Test-Path $MagiskApk)) {
    Write-Host "ERROR: Magisk APK not found!" -ForegroundColor Red
    Write-Host "  Path: $MagiskApk" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

if (-not (Test-Path $SuperApk)) {
    Write-Host "ERROR: superpower.apk not found!" -ForegroundColor Red
    Write-Host "  Path: $SuperApk" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Set default output path to patched folder
$patchedDir = Join-Path $WorkDir "patched"
New-Directory -Path $patchedDir
if ([string]::IsNullOrEmpty($OutputPath)) {
    $OutputPath = Join-Path $patchedDir "boot_a-patched.img"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $WorkDir $OutputPath
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
}

Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Boot image: $BootPath" -ForegroundColor Gray
Write-Host "  Magisk APK: $MagiskApk" -ForegroundColor Gray
Write-Host "  Superpower APK: $SuperApk" -ForegroundColor Gray
Write-Host "  Output: $OutputPath" -ForegroundColor Gray
Write-Host "  Working directory: $WorkDir" -ForegroundColor Gray
Write-Host ""

# =======================================================
# Copy Shell Script to WSL-accessible Location
# =======================================================

$shellScriptPath = Join-Path $PSScriptRoot "magisk_patch-boot.sh"

if (-not (Test-Path $shellScriptPath)) {
    Write-Host "ERROR: magisk_patch-boot.sh not found!" -ForegroundColor Red
    Write-Host "  Expected: $shellScriptPath" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please ensure magisk_patch-boot.sh is in the same directory as this script." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Convert paths to WSL format
$wslBootPath = Convert-ToWslPath -WindowsPath $BootPath
$wslMagiskApk = Convert-ToWslPath -WindowsPath $MagiskApk
$wslSuperApk = Convert-ToWslPath -WindowsPath $SuperApk
$wslOutputPath = Convert-ToWslPath -WindowsPath $OutputPath
$wslShellScript = Convert-ToWslPath -WindowsPath $shellScriptPath

Write-Host "WSL Paths:" -ForegroundColor Green
Write-Host "  Boot: $wslBootPath" -ForegroundColor Gray
Write-Host "  Magisk: $wslMagiskApk" -ForegroundColor Gray
Write-Host "  Superpower: $wslSuperApk" -ForegroundColor Gray
Write-Host "  Output: $wslOutputPath" -ForegroundColor Gray
Write-Host ""

# =======================================================
# Build WSL Command
# =======================================================

$wslCommand = "chmod +x '$wslShellScript' && bash '$wslShellScript' '$wslBootPath' '$wslMagiskApk' '$wslSuperApk' '$wslOutputPath'"

# =======================================================
# Execute in WSL
# =======================================================

Write-Host "Executing in WSL..." -ForegroundColor Green
Write-Host ""
Write-Host "--------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

try {
    if ($wslDistro) {
        wsl -d $wslDistro --exec bash -c $wslCommand
    } else {
        wsl --exec bash -c $wslCommand
    }

    $exitCode = $LASTEXITCODE

    Write-Host "--------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    if ($exitCode -ne 0) {
        throw "WSL command exited with code: $exitCode"
    }

} catch {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host "  ERROR: Patching failed!" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host " $_" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# =======================================================
# Verify Output
# =======================================================

if (-not (Test-Path $OutputPath)) {
    Write-Host "ERROR: Output file not created!" -ForegroundColor Red
    Write-Host "  Expected: $OutputPath" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$outputSize = (Get-Item $OutputPath).Length

Write-Host "================================================" -ForegroundColor Green
Write-Host "  PowerShell Wrapper: SUCCESS!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output file verified:" -ForegroundColor Cyan
Write-Host "  Path: $OutputPath" -ForegroundColor White
Write-Host "  Size: $outputSize bytes ($([math]::Round($outputSize/1MB, 2)) MB)" -ForegroundColor White
Write-Host ""

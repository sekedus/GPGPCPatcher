<#
.SYNOPSIS
    Patch super.img using WSL and helper shell scripts
.DESCRIPTION
    Uses super_patch-product.sh to modify super partition
.PARAMETER SuperPath
    Path to super.img file (default: .\{WorkDir}\extracted\super.img)
.PARAMETER ApkPath
    Path to APK file to install into system (optional, skips system patch if not set)
.PARAMETER ApkTargetDir
    Target directory inside system partition (default: system/app)
    Valid values: system/app, system/priv-app, system/system_ext/priv-app
.PARAMETER AdbproxyPath
    Path to adbproxy binary (default: ..\resources\bin\adbproxy)
.PARAMETER OutputPath
    Path for output patched image (default: .\{WorkDir}\patched\super-patched.img)
.PARAMETER WorkDir
    Path to working directory (default to patcher directory)
.EXAMPLE
    .\_Patch-Super.ps1
.EXAMPLE
    .\_Patch-Super.ps1 -SuperPath "D:\Custom_Path\super.img" -ApkPath "D:\Custom_Path\MyApp.apk" -ApkTargetDir "system/priv-app" -AdbproxyPath "D:\Custom_Path\adbproxy" -OutputPath "D:\Custom_Path\super-patched.img" -WorkDir "..\dev-26.3.725.2"
.NOTES
    Requires: PowerShell 5.1+ (Admin) and WSL2 (sudo) with lpunpack, lpmake, lpdump, simg2img, img2simg, e2fsck, resize2fs
    References:
        - https://xdaforums.com/t/4486817/post-90052467
        - https://www.hovatek.com/forum/thread-49389.html
        - https://xdaforums.com/t/4196625/
#>

param(
    [switch]$Dev,
    [string]$SuperPath,
    [string]$OutputPath,
    [string]$ApkPath,
    [string]$ApkTargetDir = "system/app",
    [string]$AdbproxyPath,
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
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  super.img Patcher" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# =======================================================
# Check Prerequisites
# =======================================================

Write-Host "Checking prerequisites..." -ForegroundColor Green
Write-Host ""

# Check WSL Installation
try {
    $null = wsl --status 2>&1
    Write-Host "WSL is installed" -ForegroundColor Gray
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

# Set default super.img path to working directory
if ([string]::IsNullOrEmpty($SuperPath)) {
    $SuperPath = Join-Path $WorkDir "extracted\super.img"
} elseif (-not [System.IO.Path]::IsPathRooted($SuperPath)) {
    $SuperPath = Join-Path $WorkDir $SuperPath
    $SuperPath = [System.IO.Path]::GetFullPath($SuperPath)
}

if (-not $Dev) {
    if ([string]::IsNullOrEmpty($ApkPath)) {
        $ApkPath = Join-Path $patcherDir "resources\Launcher3QuickStep.zip"
    } elseif (-not [System.IO.Path]::IsPathRooted($ApkPath)) {
        $ApkPath = Join-Path $patcherDir $ApkPath
        $ApkPath = [System.IO.Path]::GetFullPath($ApkPath)
    }
}

if ([string]::IsNullOrEmpty($AdbproxyPath)) {
    $AdbproxyPath = Join-Path $patcherDir "resources\bin\adbproxy"
} elseif (-not [System.IO.Path]::IsPathRooted($AdbproxyPath)) {
    $AdbproxyPath = Join-Path $patcherDir $AdbproxyPath
    $AdbproxyPath = [System.IO.Path]::GetFullPath($AdbproxyPath)
}

# Set default output path to patched folder
$patchedDir = Join-Path $WorkDir "patched"
New-Directory -Path $patchedDir
if ([string]::IsNullOrEmpty($OutputPath)) {
    $OutputPath = Join-Path $patchedDir "super-patched.img"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $WorkDir $OutputPath
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
}

if (-not (Test-Path $SuperPath)) {
    Write-Host "ERROR: super.img not found!" -ForegroundColor Red
    Write-Host "  Path: $SuperPath" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Extract first with:" -ForegroundColor Cyan
    Write-Host '  .\_Extract-Partition.ps1 -PartitionName "super"' -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$ApkExists = -not [string]::IsNullOrEmpty($ApkPath)
if ($ApkExists) {
    if (-not (Test-Path $ApkPath)) {
        Write-Host "ERROR: APK not found!" -ForegroundColor Red
        Write-Host "  Path: $ApkPath" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

if (-not (Test-Path $AdbproxyPath)) {
    Write-Host "ERROR: adbproxy binary not found!" -ForegroundColor Red
    Write-Host "  Path: $AdbproxyPath" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  super.img file: $SuperPath" -ForegroundColor Gray
if ($ApkExists) {
    Write-Host "  APK: $ApkPath" -ForegroundColor Gray
    Write-Host "  APK Target Dir: $ApkTargetDir" -ForegroundColor Gray
} else {
    Write-Host "  APK: (not set, skipping system patch)" -ForegroundColor DarkGray
}
Write-Host "  adbproxy: $AdbproxyPath" -ForegroundColor Gray
Write-Host "  Output: $OutputPath" -ForegroundColor Gray
Write-Host ""

# =======================================================
# Copy Shell Script to WSL-accessible Location
# =======================================================

# Convert to WSL paths
$wslSuperPath = Convert-ToWslPath -WindowsPath $SuperPath
$wslOutputPath = Convert-ToWslPath -WindowsPath $OutputPath
$wslApkPath = if ($ApkExists) { Convert-ToWslPath -WindowsPath $ApkPath } else { "" }
$wslUnpackScript  = Convert-ToWslPath -WindowsPath (Join-Path $PSScriptRoot "super_unpack.sh")
$wslProductScript = Convert-ToWslPath -WindowsPath (Join-Path $PSScriptRoot "super_patch-product.sh")
$wslSystemScript  = Convert-ToWslPath -WindowsPath (Join-Path $PSScriptRoot "super_patch-system.sh")
$wslVendorScript  = Convert-ToWslPath -WindowsPath (Join-Path $PSScriptRoot "super_patch-vendor.sh")
$wslRepackScript  = Convert-ToWslPath -WindowsPath (Join-Path $PSScriptRoot "super_repack.sh")
$wslAdbproxyPath = Convert-ToWslPath -WindowsPath $AdbproxyPath

Write-Host "WSL Paths:" -ForegroundColor Green
Write-Host "  super.img file:  $wslSuperPath" -ForegroundColor Gray
Write-Host "  Output:  $wslOutputPath" -ForegroundColor Gray
Write-Host ""

# =======================================================
# Build WSL Command
# =======================================================

# Check if all patch steps are skipped
$allStepsSkipped = $Dev -and -not $ApkExists
if ($allStepsSkipped) {
    Write-Host "No APK provided and Developer version selected, skipping all patch steps..." -ForegroundColor Yellow
    Write-Host ""
    exit 5  # custom exit code for "skipped"
}

# Check all shell scripts exist
foreach ($scriptFile in @("super_unpack.sh", "super_patch-system.sh", "super_patch-product.sh", "super_patch-vendor.sh", "super_repack.sh")) {
    $scriptFullPath = Join-Path $PSScriptRoot $scriptFile
    if (-not (Test-Path $scriptFullPath)) {
        Write-Host "ERROR: $scriptFile not found!" -ForegroundColor Red
        Write-Host "  Expected: $scriptFullPath" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

$wslCommand = @"
set -e
sudo true
chmod +x '$wslUnpackScript'
chmod +x '$wslProductScript'
chmod +x '$wslSystemScript'
chmod +x '$wslVendorScript'
chmod +x '$wslRepackScript'
echo ''
echo '======================================================='
echo '[1/5] Unpacking super.img ...'
echo '======================================================='
SUPER_UNPACKED_DIR=`$(sudo bash '$wslUnpackScript' '$wslSuperPath')
export SUPER_UNPACKED_DIR
echo "SUPER_UNPACKED_DIR=`$SUPER_UNPACKED_DIR"
echo ''
echo '======================================================='
echo '[2/5] Patching product_a ...'
echo '======================================================='
echo ''
$(if ($Dev) {
    "echo '  SKIPPED (Developer version, no product patch)'"
} else {
    "sudo -E bash '$wslProductScript'"
})
echo ''
echo '======================================================='
echo '[3/5] Patching system_a ...'
echo '======================================================='
echo ''
$(if ($ApkExists) {
    "sudo -E bash '$wslSystemScript' '$wslApkPath' '$ApkTargetDir'"
} else {
    "echo '  SKIPPED (no APK provided)'"
})
echo ''
echo '======================================================='
echo '[4/5] Patching vendor_a ...'
echo '======================================================='
echo ''
$(if ($Dev) {
    "echo '  SKIPPED (Developer version, no vendor patch)'"
} else {
    "sudo -E bash '$wslVendorScript' '$wslAdbproxyPath'"
})
echo ''
echo '======================================================='
echo '[5/5] Repacking super image ...'
echo '======================================================='
echo ''
sudo -E bash '$wslRepackScript' '$wslSuperPath' '$wslOutputPath' '$ApkExists'
"@

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
    Write-Host "  $_" -ForegroundColor Yellow
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

<#
.SYNOPSIS
    Enable ADB in Google Play Games on PC (Prod/Retail/Regular) by copying files from Dev version.
.DESCRIPTION
    Backs up existing files from Prod, then copies ADB-enabled files from Dev to Prod.
    This enables ADB functionality in the Google Play Games on PC (Prod).
.PARAMETER Restore
    Restore from backup instead of patching
.PARAMETER WorkDir
    Path to working directory (default to patcher directory)
.PARAMETER Force
    Skip confirmation prompts
.EXAMPLE
    .\_Enable-ADB.ps1
    Backup and patch files
.EXAMPLE
    .\_Enable-ADB.ps1 -Restore -WorkDir "..\prod-26.3.725.2"
    Restore original files from backup
.NOTES
    Requires: PowerShell 5.1+ (Admin), both Prod and Dev to be installed
    Reference: https://xdaforums.com/t/4486817/post-90018526
#>

param(
    [switch]$Restore,
    [switch]$Force,
    [string]$WorkDir
)

#Requires -RunAsAdministrator

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
Write-Host "  ADB File Patcher (Enable ADB in Prod Version)" -ForegroundColor Cyan
if ($Restore) {
    Write-Host "  RESTORE MODE" -ForegroundColor Yellow
}
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# =======================================================
# Define Paths
# =======================================================

$prodDir = Join-Path (Get-InstallDir) "emulator"
$devDir = Join-Path (Get-InstallDir -Dev:$true) "emulator"
$backupDir = Join-Path $WorkDir "backup\adb"

# =======================================================
# Files to Backup (from Prod)
# =======================================================

$filesToBackup = @(
    "CrashReporting.dll",
    "GuiLibExport.dll",
    "cperfetto.dll",
    "crosvm.exe",
    "gfxstream_backend.dll",
    "libglib-2.0-0.dll",
    "libiconv-2.dll",
    "libintl-8.dll",
    "libpcre2-8-0.dll",
    "libsecure_env.dll",
    "libsecurity.dll",
    "libslirp-0.dll",
    "r8Brain.dll",
    "recorder_delegate_lib.dll"
)

# =======================================================
# Files to Copy (from Dev to Prod)
# =======================================================

$filesToCopy = @(
    "adb.exe",
    "adbproxy.exe",
    "AdbWinApi.dll",
    "AdbWinUsbApi.dll"
) + $filesToBackup

# =======================================================
# Check Prerequisites
# =======================================================

Write-Host "Checking prerequisites..." -ForegroundColor Green

if (-not (Test-Path $prodDir)) {
    Write-Host "ERROR: Google Play Games on PC (Prod) not found!" -ForegroundColor Red
    Write-Host "  Path: $prodDir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Install Google Play Games on PC (Prod/Retail/Regular) from:" -ForegroundColor Cyan
    Write-Host "  https://g.co/googleplaygames" -ForegroundColor White
    exit 1
}

if (-not (Test-Path $devDir)) {
    Write-Host "ERROR: Google Play Games on PC Developer Emulator not found!" -ForegroundColor Red
    Write-Host "  Path: $devDir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Install Google Play Games on PC Developer Emulator from:" -ForegroundColor Cyan
    Write-Host "  https://developer.android.com/games/playgames/emulator" -ForegroundColor White
    exit 1
}

Write-Host "  Prod installation found" -ForegroundColor Gray
Write-Host "  Dev installation found" -ForegroundColor Gray
Write-Host ""

# Check if GPGPC is running
Test-Running -InstallDir (Split-Path -Parent $prodDir)
Test-Running -Dev:$true -InstallDir (Split-Path -Parent $devDir)

# =======================================================
# RESTORE MODE
# =======================================================

if ($Restore) {
    if (-not (Test-Path $backupDir)) {
        Write-Host "ERROR: Backup directory not found!" -ForegroundColor Red
        Write-Host "  Path: $backupDir" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    Write-Host "Backup directory: $backupDir" -ForegroundColor Gray

    if (-not $Force) {
        $confirm = Read-Host "Restore original files from backup? (yes/no)"
        if ($confirm -ne "yes") {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            Write-Host ""
            exit 0
        }
    }

    Write-Host ""
    Write-Host "Restoring files..." -ForegroundColor Green

    $restoredCount = 0
    $skippedCount = 0

    foreach ($file in $filesToBackup) {
        $backupFile = Join-Path $backupDir $file
        $targetFile = Join-Path $prodDir $file

        if (Test-Path $backupFile) {
            try {
                Copy-Item $backupFile $targetFile -Force
                Write-Host "  Restored: $file" -ForegroundColor Gray
                $restoredCount++
            } catch {
                Write-Host "  Failed to restore: $file" -ForegroundColor Red
                Write-Host "    $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Backup not found: $file" -ForegroundColor Yellow
            $skippedCount++
        }
    }

    Write-Host ""
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host "  RESTORE COMPLETE!" -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Restored: $restoredCount files" -ForegroundColor White
    if ($skippedCount -gt 0) {
        Write-Host "  Skipped:  $skippedCount files" -ForegroundColor Gray
    }
    Write-Host ""

    exit 0
}

# =======================================================
# PATCH MODE
# =======================================================

Write-Host "Operation summary:" -ForegroundColor Green
Write-Host "  Source:      Dev" -ForegroundColor Gray
Write-Host "  Destination: Prod" -ForegroundColor Gray
Write-Host "  Files:       $($filesToCopy.Count) files" -ForegroundColor Gray
Write-Host "  Backup:      $backupDir" -ForegroundColor Gray
Write-Host ""

if (-not $Force) {
    Write-Host "This will:" -ForegroundColor Yellow
    Write-Host "  1. Backup $($filesToBackup.Count) files from Prod" -ForegroundColor White
    Write-Host "  2. Copy $($filesToCopy.Count) files from Dev" -ForegroundColor White
    Write-Host "  3. Enable ADB functionality in Prod version" -ForegroundColor White
    Write-Host ""

    $confirm = Read-Host "Continue? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }
}

Write-Host ""

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  STEP 1: Creating Backup" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# Create backup directory
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
    Write-Host "Created backup directory: $backupDir" -ForegroundColor Gray
} else {
    Write-Host "Backup directory exists: $backupDir" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Backing up files from Prod..." -ForegroundColor Green

$backedUpCount = 0
$skippedCount = 0

foreach ($file in $filesToBackup) {
    $sourceFile = Join-Path $prodDir $file
    $backupFile = Join-Path $backupDir $file

    if (Test-Path $sourceFile) {
        # Only backup if not already backed up
        if (-not (Test-Path $backupFile)) {
            try {
                Copy-Item $sourceFile $backupFile -Force
                Write-Host "  Backed up: $file" -ForegroundColor Green
                $backedUpCount++
            } catch {
                Write-Host "  Failed to backup: $file" -ForegroundColor Red
                Write-Host "    $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Already backed up: $file" -ForegroundColor Gray
            $skippedCount++
        }
    } else {
        Write-Host "  Not found (skipped): $file" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Backup summary:" -ForegroundColor Green
Write-Host "  Backed up: $backedUpCount files" -ForegroundColor White
if ($skippedCount -gt 0) {
    Write-Host "  Already backed up: $skippedCount files" -ForegroundColor Gray
}
Write-Host ""

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "  STEP 2: Copying Files from Dev" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Copying ADB-enabled files..." -ForegroundColor Green
Write-Host ""

$copiedCount = 0
$failedCount = 0
$missingCount = 0

foreach ($file in $filesToCopy) {
    $sourceFile = Join-Path $devDir $file
    $targetFile = Join-Path $prodDir $file

    if (Test-Path $sourceFile) {
        try {
            # Get file sizes
            $sourceSize = (Get-Item $sourceFile).Length
            $sourceSizeKB = [math]::Round($sourceSize / 1KB, 2)

            # Check digest before copying, skip if match
            if (Test-Path $targetFile) {
                $sourceHash = (Get-FileHash $sourceFile -Algorithm SHA256).Hash
                $targetHash = (Get-FileHash $targetFile -Algorithm SHA256).Hash
                if ($sourceHash -eq $targetHash) {
                    Write-Host "  Skipped (identical): $file ($sourceSizeKB KB)" -ForegroundColor Gray
                    $copiedCount++
                    continue
                }
            }

            # Copy file
            Copy-Item $sourceFile $targetFile -Force

            # Verify copy
            $targetSize = (Get-Item $targetFile).Length

            if ($targetSize -eq $sourceSize) {
                Write-Host "  Copied: $file ($sourceSizeKB KB)" -ForegroundColor Green
                $copiedCount++
            } else {
                Write-Host "  Size mismatch: $file" -ForegroundColor Yellow
                Write-Host "    Source: $sourceSize bytes" -ForegroundColor Gray
                Write-Host "    Target: $targetSize bytes" -ForegroundColor Gray
                $failedCount++
            }

        } catch {
            Write-Host "  Failed to copy: $file" -ForegroundColor Red
            Write-Host "    $_" -ForegroundColor Yellow
            $failedCount++
        }
    } else {
        Write-Host "  Not found in Dev: $file" -ForegroundColor Red
        $missingCount++
    }
}

Write-Host ""

# =======================================================
# Summary
# =======================================================

if ($failedCount -gt 0 -or $missingCount -gt 0) {
    Write-Host "====================================================" -ForegroundColor Yellow
    Write-Host "  COMPLETED WITH WARNINGS" -ForegroundColor Yellow
    Write-Host "====================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Copy summary:" -ForegroundColor Green
    Write-Host "  Copied:  $copiedCount files" -ForegroundColor White
    if ($failedCount -gt 0) {
        Write-Host "  Failed:  $failedCount files" -ForegroundColor Yellow
    }
    if ($missingCount -gt 0) {
        Write-Host "  Missing: $missingCount files" -ForegroundColor Yellow
    }
} else {
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host "  SUCCESS!" -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Copy summary:" -ForegroundColor Green
    Write-Host "  Copied: $copiedCount files" -ForegroundColor White
}

Write-Host ""

Write-Host "What was done:" -ForegroundColor Green
Write-Host "  Backed up original files to: $backupDir" -ForegroundColor White
Write-Host "  Copied ADB-enabled files from Dev" -ForegroundColor White
Write-Host "  ADB functionality now enabled in Prod version" -ForegroundColor Green
Write-Host ""

# Write-Host "Restore original files:" -ForegroundColor Cyan
# Write-Host "  .\_Enable-ADB.ps1 -Restore -WorkDir `"$backupDir`"" -ForegroundColor Yellow
# Write-Host ""

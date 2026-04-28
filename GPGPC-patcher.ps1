<#
.SYNOPSIS
    Fully automated patcher for Google Play Games on PC (GPGPC).
.DESCRIPTION
    Fully automated workflow:
    1. Patch ServiceLib.dll or Service.exe
    2. Patch Service.exe.config
    3. Patch aggregate.img
        ├─ boot_a.img
        ├─ super.img
        │   ├─ product_a.img
        │   ├─ system_a.img
        │   └─ vendor_a.img
        └─ vbmeta_a.img
    4. Patch bios.rom
.PARAMETER Dev
    Use Developer Emulator paths instead of prod version
.PARAMETER Restore
    Restore original files from backup instead of patching
.PARAMETER MagiskApk
    Optional path to Magisk APK
.EXAMPLE
    .\GPGPC.ps1
.EXAMPLE
    .\GPGPC.ps1 -Dev -Restore
.EXAMPLE
    .\GPGPC.ps1 -Dev -MagiskApk "D:\Custom_Path\Magisk.apk"
.NOTES
    Requires: PowerShell 5.1+ (Admin) and WSL2 (sudo)
#>

param(
    [switch]$Dev,
    [switch]$Restore,
    [string]$MagiskApk
)

#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Import-Module ".\HelperModule.psm1" -Force

# Script version
$ScriptVersion = "1.0.0"

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  Google Play Games on PC (GPGPC) Patcher v$ScriptVersion" -ForegroundColor Cyan
if ($Restore) {
    Write-Host "  RESTORE MODE" -ForegroundColor Yellow
}
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# Check if GPGPC is running
Test-Running -InstallDir (Get-InstallDir)
Test-Running -Dev:$true -InstallDir (Get-InstallDir -Dev:$true)

# Define Paths
$installDir = Get-InstallDir -Dev:$Dev
$InstallVersion = Get-InstallVersion -ServiceDir (Join-Path $installDir "service")
$versionName = if ($Dev) { "dev" } else { "prod" }
$scriptDir = Join-Path $PSScriptRoot "scripts"

# Create working directory for this version
$workDir = Join-Path $PSScriptRoot "$versionName-$InstallVersion"
if (-not (Test-Path $workDir)) {
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
}

if ($Restore) {
    $backupDir = Join-Path $workDir "backup"
    Write-Host "Restoring files from:" -ForegroundColor Green
    Write-Host "  $backupDir" -ForegroundColor Gray
    Write-Host ""

    $targets = @(
        'emulator\avd\aggregate.img',
        'emulator\avd\bios.rom',
        'service\Service.exe',
        'service\Service.exe.config',
        'service\ServiceLib.dll'
    )

    foreach ($relativePath in $targets) {
        $leaf = Split-Path $relativePath -Leaf
        $src = Join-Path $backupDir $leaf
        $dest = Join-Path $installDir $relativePath
        if (-not (Test-Path $src)) {
            Write-Host "Backup not found: $src" -ForegroundColor Yellow
            continue
        }
        $destDir = Split-Path $dest
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -Path $src -Destination $dest -Force
        Write-Host "Restored $leaf to: $dest" -ForegroundColor Gray
    }
    Write-Host ""

    # Restore ADB files for Prod version
    if (-not $Dev) {
        Write-Host ""
        Write-Host "Restoring emulator files from backup..." -ForegroundColor Green

        & "$scriptDir\_Enable-ADB.ps1" -Restore -Force -WorkDir $workDir

        if (-not $?) {
            Write-Host "Warning: ADB restore script reported an error." -ForegroundColor Yellow
        }
        Write-Host ""
    }

    Write-Host "All done! Original files have been restored from backup." -ForegroundColor Green
    Write-Host ""
    exit 0
}

Write-Host "Version: $versionName $InstallVersion" -ForegroundColor Magenta
Write-Host ""
Write-Host "This will automatically:" -ForegroundColor White
Write-Host "  1. Patch ServiceLib.dll or Service.exe" -ForegroundColor Gray
Write-Host "  2. Patch Service.exe.config" -ForegroundColor Gray
Write-Host "  3. Extract boot_a.img from aggregate.img" -ForegroundColor Gray
Write-Host "  4. Patch boot_a with Magisk + Superpower" -ForegroundColor Gray
Write-Host "  5. Flash boot_a-patched.img to aggregate.img" -ForegroundColor Gray
Write-Host "  6. Extract super.img from aggregate.img" -ForegroundColor Gray
Write-Host "  7. Patch super.img" -ForegroundColor Gray
Write-Host "  8. Flash super-patched.img to aggregate.img" -ForegroundColor Gray
Write-Host "  9. Extract vbmeta_a from aggregate.img" -ForegroundColor Gray
Write-Host "  10. Disable AVB (Android Verified Boot) on vbmeta_a.img" -ForegroundColor Gray
Write-Host "  11. Flash vbmeta_a to aggregate.img" -ForegroundColor Gray
Write-Host "  12. Patch bios.rom" -ForegroundColor Gray
Write-Host ""

$confirmation = Read-Host "Continue? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

Write-Host ""

try {
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 1: Patching ServiceLib.dll or Service.exe" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    if ($Dev) {
        & "$scriptDir\_Patch-Service.ps1" -Dev -WorkDir $workDir
    } else {
        & "$scriptDir\_Patch-Service.ps1" -WorkDir $workDir
    }

    if (-not $?) { throw "Patching failed: ServiceLib.dll or Service.exe" }
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 2: Patching Service.exe.config" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    if ($Dev) {
        & "$scriptDir\_Patch-ServiceConfig.ps1" -Dev -WorkDir $workDir
    } else {
        & "$scriptDir\_Patch-ServiceConfig.ps1" -WorkDir $workDir
    }

    if (-not $?) { throw "Patching failed: Service.exe.config" }
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 3: Extracting boot_a.img from aggregate.img" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    if ($Dev) {
        & "$scriptDir\_Extract-Partition.ps1" -Dev -Y -WorkDir $workDir
    } else {
        & "$scriptDir\_Extract-Partition.ps1" -Y -WorkDir $workDir
    }

    if (-not $?) { throw "Extraction failed: boot_a.img" }
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 4: Patching boot_a with Magisk + Superpower" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    if ($Dev) {
        & "$scriptDir\_Patch-BootWithMagisk.ps1" -Dev -MagiskApk $MagiskApk -WorkDir $workDir
    } else {
        & "$scriptDir\_Patch-BootWithMagisk.ps1" -MagiskApk $MagiskApk -WorkDir $workDir
    }

    if (-not $?) { throw "Patching failed: boot_a.img" }
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 5: Flashing boot_a-patched.img to aggregate.img" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    if ($Dev) {
        & "$scriptDir\_Flash-Partition.ps1" -Dev -Y -WorkDir $workDir
    } else {
        & "$scriptDir\_Flash-Partition.ps1" -Y -WorkDir $workDir
    }

    if (-not $?) { throw "Flashing failed: boot_a-patched.img" }
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 6: Extracting super.img from aggregate.img" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    if ($Dev) {
        & "$scriptDir\_Extract-Partition.ps1" -Dev -Y -PartitionName "super" -WorkDir $workDir
    } else {
        & "$scriptDir\_Extract-Partition.ps1" -Y -PartitionName "super" -WorkDir $workDir
    }

    if (-not $?) { throw "Extraction failed: super.img" }
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 7: Patching super.img" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    $global:LASTEXITCODE = 0 

    if ($Dev) {
        & "$scriptDir\_Patch-Super.ps1" -Dev -WorkDir $workDir
    } else {
        & "$scriptDir\_Patch-Super.ps1" -WorkDir $workDir
    }

    $superExitCode = $LASTEXITCODE
    if ($superExitCode -eq 1) { throw "Patching failed: super.img" }
    $superSkipped = ($superExitCode -eq 5)
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 8: Flashing super-patched.img to aggregate.img" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    if ($superSkipped) {
        Write-Host ""
        Write-Host "SKIPPED (Step 7 was skipped)" -ForegroundColor Yellow
    } else {
        if ($Dev) {
            & "$scriptDir\_Flash-Partition.ps1" -Dev -Y -PartitionName "super" -WorkDir $workDir
        } else {
            & "$scriptDir\_Flash-Partition.ps1" -Y -PartitionName "super" -WorkDir $workDir
        }

        if (-not $?) { throw "Flashing failed: super-patched.img" }
    }
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 9: Extracting vbmeta from aggregate.img" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    foreach ($partition in @("vbmeta_a", "vbmeta_system_a")) {
        if ($Dev) {
            & "$scriptDir\_Extract-Partition.ps1" -Dev -Y -PartitionName $partition -WorkDir $workDir
        } else {
            & "$scriptDir\_Extract-Partition.ps1" -Y -PartitionName $partition -WorkDir $workDir
        }
        if (-not $?) { throw "Extraction failed: $partition" }
    }
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 10: Disabling AVB on vbmeta" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    foreach ($partition in @("vbmeta_a", "vbmeta_system_a")) {
        & "$scriptDir\_Patch-Vbmeta.ps1" -VbmetaName $partition -WorkDir $workDir
        if (-not $?) { throw "Patching failed: $partition" }
    }
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 11: Flashing vbmeta to aggregate.img" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    foreach ($partition in @("vbmeta_a", "vbmeta_system_a")) {
        if ($Dev) {
            & "$scriptDir\_Flash-Partition.ps1" -Dev -Y -PartitionName $partition -WorkDir $workDir
        } else {
            & "$scriptDir\_Flash-Partition.ps1" -Y -PartitionName $partition -WorkDir $workDir
        }
        if (-not $?) { throw "Flashing failed: $partition" }
    }
    Write-Host ""

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "STEP 12: Patching bios.rom" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan

    if ($Dev) {
        & "$scriptDir\_Patch-Bios.ps1" -Dev -WorkDir $workDir
    } else {
        & "$scriptDir\_Patch-Bios.ps1" -WorkDir $workDir
    }

    if (-not $?) { throw "Patching failed: bios.rom" }

    if (-not $Dev) {
        Write-Host ""
        Write-Host "======================================================" -ForegroundColor Cyan
        Write-Host "STEP 13: Enabling ADB in Prod version" -ForegroundColor Cyan
        Write-Host "======================================================" -ForegroundColor Cyan

        & "$scriptDir\_Enable-ADB.ps1" -Force -WorkDir $workDir

        if (-not $?) { throw "Patching failed: ADB" }
    }

    # Success!
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "  COMPLETE!" -ForegroundColor Green
    Write-Host "    All steps completed automatically!" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now start Google Play Games on PC$(if ($Dev) { ' Developer Emulator' })!" -ForegroundColor Cyan
    Write-Host ""

} catch {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host "  ERROR: Automated patching failed!" -ForegroundColor Red
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $_" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

<#
.SYNOPSIS
    Disable AVB verification on vbmeta images
.DESCRIPTION
    Patches vbmeta_a.img and vbmeta_system_a.img to disable Android Verified Boot
.PARAMETER VbmetaPath
    Path to vbmeta file
.PARAMETER VbmetaName
    Name of vbmeta: vbmeta_a or vbmeta_system_a (default: vbmeta_a)
.PARAMETER OutputPath
    Path for output patched image
.PARAMETER WorkDir
    Path to working directory (default to patcher directory)
.EXAMPLE
    .\Patch-Vbmeta.ps1
.EXAMPLE
    .\Patch-Vbmeta.ps1 -VbmetaName "vbmeta_system_a"
.EXAMPLE
    .\Patch-Vbmeta.ps1 -VbmetaPath "D:\Custom_Path\vbmeta_a.img" -OutputPath "D:\Custom_Path\vbmeta_a-patched.img"
.NOTES
    Requires: PowerShell 5.1+ (Admin)
    Reference: https://github.com/libxzr/vbmeta-disable-verification/blob/c3897be2dfe6be930f09515ee9c3f2a5bcafc2b8/jni/main.c
    Related projects:
    - https://github.com/ShlomoHeller/AVB-Disabler
    - https://github.com/WessellUrdata/vbmeta-disable-verification
    - https://github.com/capntrips/android_external_avb/releases/tag/android-13.0.0_r11
#>

param(
    [string]$VbmetaPath,

    [ValidateSet("vbmeta_a", "vbmeta_system_a")]
    [string]$VbmetaName = "vbmeta_a",

    [string]$OutputPath,

    [switch]$Force
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
Write-Host "  vbmeta Patcher (Disable AVB)" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# =======================================================
# Constants
# =======================================================

$AVB_MAGIC = [byte[]](0x41,0x56,0x42,0x30) # "AVB0"
$AVB_MAGIC_LEN = 4
$FLAGS_OFFSET = 123  # offsetof(AvbVBMetaImageHeader.flags)
$FLAG_DISABLE_VERITY = 0x01
$FLAG_DISABLE_VERIFICATION = 0x02

# =======================================================
# Helper Functions
# =======================================================

function Find-VbmetaOffset {
    param([byte[]]$Data)

    for ($i = 0; $i -le $Data.Length - $AVB_MAGIC_LEN; $i++) {
        if ($Data[$i] -eq $AVB_MAGIC[0] -and
            $Data[$i+1] -eq $AVB_MAGIC[1] -and
            $Data[$i+2] -eq $AVB_MAGIC[2] -and
            $Data[$i+3] -eq $AVB_MAGIC[3]) {
            return $i
        }
    }

    return -1
}

function Patch-VbmetaFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath,

        [string]$VbmetaName
    )

    Write-Host "Processing: $VbmetaName" -ForegroundColor Green
    Write-Host "  Input:  $InputPath" -ForegroundColor Gray
    Write-Host "  Output: $OutputPath" -ForegroundColor Gray
    Write-Host ""

    # STEP 1: Read file and validate
    Write-Host "Validating vbmeta image..." -ForegroundColor Green

    [byte[]]$imageBytes = [System.IO.File]::ReadAllBytes($InputPath)
    $vbmetaSize = $imageBytes.Length

    Write-Host "  File size: $vbmetaSize bytes ($([math]::Round($vbmetaSize/1KB, 2)) KB)" -ForegroundColor Gray

    # STEP 2: Locate VBMeta
    Write-Host "  Searching for VBMeta header..." -ForegroundColor Gray
    $vbmetaOffset = Find-VbmetaOffset $imageBytes

    if ($vbmetaOffset -lt 0) {
        Write-Host "ERROR: Invalid vbmeta image!" -ForegroundColor Red
        Write-Host "  VBMeta header (AVB0) not found!" -ForegroundColor Yellow
        Write-Host ""
        throw "VBMeta header (AVB0) not found!"
    }

    Write-Host "  Valid vbmeta image (magic: AVB0 at offset $vbmetaOffset)" -ForegroundColor Gray
    Write-Host ""

    # STEP 3: Read Current Flags
    Write-Host "Reading current flags..." -ForegroundColor Green

    $flagsOffset = $vbmetaOffset + $FLAGS_OFFSET

    if ($flagsOffset + 4 -gt $vbmetaSize) {
        Write-Host "ERROR: Flags offset out of bounds!" -ForegroundColor Red
        Write-Host ""
        throw "Flags offset out of bounds!"
    }

    # Read full 4-byte flags
    $currentFlags = [BitConverter]::ToUInt32($imageBytes, $flagsOffset)

    Write-Host "  Flags offset: $flagsOffset (0x$($flagsOffset.ToString('X')))" -ForegroundColor Gray
    Write-Host "  Current flags: $currentFlags (0x$($currentFlags.ToString('X8')))" -ForegroundColor Gray
    Write-Host ""

    # Decode current state
    $verityDisabled = ($currentFlags -band $FLAG_DISABLE_VERITY) -ne 0
    $verificationDisabled = ($currentFlags -band $FLAG_DISABLE_VERIFICATION) -ne 0

    Write-Host "  Current status:" -ForegroundColor Gray
    if ($verityDisabled) {
        Write-Host "    - Verity: DISABLED" -ForegroundColor Green
    } else {
        Write-Host "    - Verity: ENABLED" -ForegroundColor Red
    }

    if ($verificationDisabled) {
        Write-Host "    - Verification: DISABLED" -ForegroundColor Green
    } else {
        Write-Host "    - Verification: ENABLED" -ForegroundColor Red
    }

    Write-Host ""

    # Check if already disabled
    if ($verityDisabled -and $verificationDisabled) {
        Write-Host "  AVB verification already disabled!" -ForegroundColor Green
        Write-Host "    No patching needed." -ForegroundColor Gray
        Write-Host ""

        # Copy to output if different
        if ($InputPath -ne $OutputPath) {
            Copy-Item $InputPath $OutputPath -Force
            Write-Host "  Copied to: $OutputPath" -ForegroundColor Gray
        }

        return
    }

    # STEP 4: Apply Patch
    Write-Host "Disabling AVB verification..." -ForegroundColor Green

    $newFlags = $currentFlags -bor $FLAG_DISABLE_VERITY -bor $FLAG_DISABLE_VERIFICATION

    Write-Host "  Setting flags:" -ForegroundColor Gray
    Write-Host "    - FLAG_DISABLE_VERITY = 0x$($FLAG_DISABLE_VERITY.ToString('X2'))" -ForegroundColor Gray
    Write-Host "    - FLAG_DISABLE_VERIFICATION = 0x$($FLAG_DISABLE_VERIFICATION.ToString('X2'))" -ForegroundColor Gray
    Write-Host "  New flags: $newFlags (0x$($newFlags.ToString('X8')))" -ForegroundColor Gray
    Write-Host ""

    # Write back full 4 bytes
    Write-Host "  Writing patched image..." -ForegroundColor Gray
    [byte[]]$newBytes = [BitConverter]::GetBytes($newFlags)
    [Array]::Copy($newBytes, 0, $imageBytes, $flagsOffset, 4)

    # STEP 5: Save file
    [System.IO.File]::WriteAllBytes($OutputPath, $imageBytes)

    Write-Host "  Patched image written" -ForegroundColor Gray
    Write-Host ""

    # STEP 6: Verify Patch
    Write-Host "Verifying patch..." -ForegroundColor Green

    [byte[]]$patchedBytes = [System.IO.File]::ReadAllBytes($OutputPath)
    $patchedFlags = [BitConverter]::ToUInt32($patchedBytes, $flagsOffset)

    Write-Host "  Patched flags: $patchedFlags (0x$($patchedFlags.ToString('X8')))" -ForegroundColor Gray

    # Verify flags
    $patchedVerity = ($patchedFlags -band $FLAG_DISABLE_VERITY) -ne 0
    $patchedVerification = ($patchedFlags -band $FLAG_DISABLE_VERIFICATION) -ne 0

    Write-Host ""
    Write-Host "  Verification status after patch:" -ForegroundColor Gray

    if ($patchedVerity) {
        Write-Host "    - Verity: DISABLED" -ForegroundColor Green
    } else {
        Write-Host "    - Verity: ENABLED" -ForegroundColor Red
        throw "Verity flag not set correctly"
    }

    if ($patchedVerification) {
        Write-Host "    - Verification: DISABLED" -ForegroundColor Green
    } else {
        Write-Host "    - Verification: ENABLED" -ForegroundColor Red
        throw "Verification flag not set correctly"
    }

    # Verify size
    $outputSize = (Get-Item $OutputPath).Length
    if ($outputSize -ne $vbmetaSize) {
        Write-Host "ERROR: File size changed!" -ForegroundColor Red
        Write-Host "  Original: $vbmetaSize bytes" -ForegroundColor Yellow
        Write-Host "  Patched:  $outputSize bytes" -ForegroundColor Yellow
        throw "File size changed"
    }

    Write-Host ""
    Write-Host "  File size preserved: $vbmetaSize bytes" -ForegroundColor Gray
    Write-Host ""

    Write-Host "Successfully patched: $VbmetaName" -ForegroundColor Green
    Write-Host "  Flags: 0x$($currentFlags.ToString('X8')) -> 0x$($patchedFlags.ToString('X8'))" -ForegroundColor Gray
    Write-Host ""
}

# =======================================================
# Main Script Logic
# =======================================================

# Set default patched path to working directory
if ([string]::IsNullOrEmpty($VbmetaPath)) {
    $VbmetaPath = Join-Path $WorkDir "extracted\$VbmetaName.img"
} elseif (-not [System.IO.Path]::IsPathRooted($VbmetaPath)) {
    $VbmetaPath = Join-Path $WorkDir $VbmetaPath
    $VbmetaPath = [System.IO.Path]::GetFullPath($VbmetaPath)
}

# Check if patched image exists
if (-not (Test-Path $VbmetaPath)) {
    Write-Host "ERROR: $VbmetaName.img not found!" -ForegroundColor Red
    Write-Host "  Path: $VbmetaPath" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Set default output path to patched folder
$patchedDir = Join-Path $WorkDir "patched"
New-Directory -Path $patchedDir
if ([string]::IsNullOrEmpty($OutputPath)) {
    $OutputPath = Join-Path $patchedDir "$VbmetaName-patched.img"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $WorkDir $OutputPath
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
}

Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Name: $VbmetaName" -ForegroundColor Gray
Write-Host "  Working directory: $WorkDir" -ForegroundColor Gray
Write-Host ""

# Patch images
try {
    Patch-VbmetaFile -InputPath $VbmetaPath -OutputPath $OutputPath -VbmetaName $VbmetaName

    Write-Host "====================================================" -ForegroundColor Green
    Write-Host "  SUCCESS: $VbmetaName patched" -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Patched image: $OutputPath" -ForegroundColor White
    Write-Host ""

} catch {
    Write-Host ""
    Write-Host "ERROR: Patching failed!" -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

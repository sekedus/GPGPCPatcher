<#
.SYNOPSIS
    Flash partition to aggregate.img
.DESCRIPTION
    Replace a partition within aggregate.img with its patched version
.PARAMETER Dev
    Use Developer Emulator (DE) paths instead of production version
.PARAMETER PatchedPath
    Path to patched (default: .\{WorkDir}\patched\{PartitionName}-patched.img)
.PARAMETER PartitionName
    Name of partition to flash (default: boot_a)
.PARAMETER WorkDir
    Path to working directory (default to patcher directory)
.EXAMPLE
    .\_Flash-Partition.ps1
    Flash to boot_a-patched Production version
.EXAMPLE
    .\_Flash-Partition.ps1 -Dev
    Flash boot_a-patched to Developer Emulator (DE)
.EXAMPLE
    .\_Flash-Partition.ps1 -PatchedPath "D:\Custom_Path\magisk_patched.img"
    Flash from custom patched image location
.EXAMPLE
    .\_Flash-Partition.ps1 -Dev -PartitionName "vbmeta_a"
    Flash vbmeta_a partition instead of boot_a
.NOTES
    Requires: PowerShell 5.1+ (Admin)
    Reference: https://github.com/chsbuffer/hpesuperpower/blob/2688f08fa2cb89790244f2d403f16a3c10ab4d85/PartitionCommand.cs#L96
#>

param(
    [switch]$Y,
    [switch]$Dev,
    [string]$PatchedPath,
    [string]$PartitionName = "boot_a",
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
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Flash $PartitionName to aggregate.img" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check if GPGPC is running
Test-Running -Dev:$Dev -InstallDir $installDir

# Set default patched path to working directory
if ([string]::IsNullOrEmpty($PatchedPath)) {
    $PatchedPath = Join-Path $WorkDir "patched\$PartitionName-patched.img"
} elseif (-not [System.IO.Path]::IsPathRooted($PatchedPath)) {
    $PatchedPath = Join-Path $WorkDir $PatchedPath
    $PatchedPath = [System.IO.Path]::GetFullPath($PatchedPath)
}

# Check if patched image exists
if (-not (Test-Path $PatchedPath)) {
    Write-Host "ERROR: $PartitionName-patched.img not found!" -ForegroundColor Red
    Write-Host "  Expected: $PatchedPath" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Check if aggregate.img exists
$aggregatePath = "$installDir\emulator\avd\aggregate.img"
if (-not (Test-Path $aggregatePath)) {
    Write-Host "ERROR: aggregate.img not found!" -ForegroundColor Red
    Write-Host "  Expected: $aggregatePath" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Try these solutions:" -ForegroundColor Cyan
    Write-Host ""

    if ($Dev) {
        Write-Host "  For Production:" -ForegroundColor Yellow
        Write-Host "    .\_Flash-Partition.ps1" -ForegroundColor White
    } else {
        Write-Host "  For Developer Emulator (DE):" -ForegroundColor Yellow
        Write-Host "    .\_Flash-Partition.ps1 -Dev" -ForegroundColor White
    }

    exit 1
}

Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Version: $versionName" -ForegroundColor Gray
Write-Host "  aggregate.img file: $aggregatePath" -ForegroundColor Gray
Write-Host "  Partition: $PartitionName" -ForegroundColor Gray
Write-Host "  Patched path: $PatchedPath" -ForegroundColor Gray
Write-Host "  Working directory: $WorkDir" -ForegroundColor Gray
Write-Host ""

Write-Host "WARNING: This will modify aggregate.img!" -ForegroundColor Yellow
Write-Host "  The file size will remain unchanged." -ForegroundColor Gray
Write-Host ""

$confirmText = 'Type "yes" to continue'
if ($Y) {
    Write-Host "${confirmText}: yes" -ForegroundColor White
    $confirmation = "yes"
} else {
    $confirmation = Read-Host $confirmText
}

if ($confirmation -ne "yes") {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}
Write-Host ""

# Create backup directory if it doesn't exist
$backupDir = Join-Path $WorkDir "backup"
New-Directory -Path $backupDir

# Create backup file
$backupPath = Join-Path $backupDir "aggregate.img"
if (-not (Test-Path $backupPath)) {
    Write-Host "Creating backup..." -ForegroundColor Green
    Copy-Item $aggregatePath $backupPath
    Write-Host "  Backup created: $backupPath" -ForegroundColor Gray
} else {
    Write-Host "Backup already exists: $backupPath" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "Opening aggregate.img..." -ForegroundColor Green
Write-Host ""

# Constants
$LBS = 512  # Logical Block Size

$fs = [System.IO.File]::Open($aggregatePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)

try {
    # Read GPT Header
    Write-Host "Reading GPT header..." -ForegroundColor Green
    $fs.Seek($LBS, [System.IO.SeekOrigin]::Begin) | Out-Null
    $gptHeader = New-Object byte[] $LBS
    $fs.Read($gptHeader, 0, $LBS) | Out-Null

    # Verify GPT signature
    $signature = [System.Text.Encoding]::ASCII.GetString($gptHeader, 0, 8)
    if ($signature -ne "EFI PART") {
        Write-Host "ERROR: Invalid GPT signature: $signature" -ForegroundColor Red
        Write-Host "This doesn't appear to be a valid GPT disk image." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    # Parse GPT header
    $partitionsArrayLba = [BitConverter]::ToUInt64($gptHeader, 72)
    $partitionsCount = [BitConverter]::ToUInt32($gptHeader, 80)
    $partitionEntrySize = [BitConverter]::ToUInt32($gptHeader, 84)

    Write-Host "  GPT signature: OK" -ForegroundColor Gray
    Write-Host "  Partitions array LBA: $partitionsArrayLba" -ForegroundColor Gray
    Write-Host "  Partitions count: $partitionsCount" -ForegroundColor Gray
    Write-Host "  Entry size: $partitionEntrySize bytes" -ForegroundColor Gray
    Write-Host ""

    # Seek to partition entries
    $fs.Seek($partitionsArrayLba * $LBS, [System.IO.SeekOrigin]::Begin) | Out-Null

    Write-Host "Searching for partition: '$PartitionName'..." -ForegroundColor Green
    $found = $false

    for ($i = 0; $i -lt $partitionsCount; $i++) {
        $entry = New-Object byte[] $partitionEntrySize
        $fs.Read($entry, 0, $partitionEntrySize) | Out-Null

        # Check for empty partition
        $typeGuid = $entry[0..15]
        $allZero = ($typeGuid | Where-Object { $_ -ne 0 }).Count -eq 0
        if ($allZero) { break }

        # Read partition name
        $nameBytes = $entry[56..127]
        $name = [System.Text.Encoding]::Unicode.GetString($nameBytes).TrimEnd([char]0)

        if ($name -eq $PartitionName) {
            # Parse partition details
            $firstLba = [BitConverter]::ToUInt64($entry, 32)
            $lastLba = [BitConverter]::ToUInt64($entry, 40)
            $offset = $firstLba * $LBS
            $size = ($lastLba - $firstLba + 1) * $LBS

            Write-Host ""
            Write-Host "Found partition: $name" -ForegroundColor Green
            Write-Host "  First LBA: $firstLba" -ForegroundColor Gray
            Write-Host "  Last LBA: $lastLba" -ForegroundColor Gray
            Write-Host "  Offset: 0x$($offset.ToString('X')) ($offset bytes)" -ForegroundColor Gray
            Write-Host "  Size: $size bytes ($([math]::Round($size/1MB, 2)) MB)" -ForegroundColor Gray
            Write-Host ""

            # Check patched image size
            $patchedFile = [System.IO.File]::OpenRead($PatchedPath)
            try {
                $patchedSize = $patchedFile.Length

                Write-Host "Patched image size: $patchedSize bytes ($([math]::Round($patchedSize/1MB, 2)) MB)" -ForegroundColor Gray
                Write-Host ""

                if ($patchedSize -ne $size) {
                    Write-Host "ERROR: Size mismatch!" -ForegroundColor Red
                    Write-Host "  Partition size: $size bytes ($([math]::Round($size/1MB, 2)) MB)" -ForegroundColor Yellow
                    Write-Host "  Patched image size: $patchedSize bytes ($([math]::Round($patchedSize/1MB, 2)) MB)" -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "The image must be EXACTLY the same size as the partition!" -ForegroundColor Red
                    Write-Host ""
                    exit 1
                }

                Write-Host "Size matches! Proceeding with flash..." -ForegroundColor Green
                Write-Host ""

                # Flash the partition
                $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null

                $bufferSize = 4MB
                $buffer = New-Object byte[] $bufferSize
                $remaining = $size
                $written = 0

                Write-Host "Writing patched image..." -ForegroundColor Green

                while ($remaining -gt 0) {
                    $toRead = [Math]::Min($remaining, $bufferSize)
                    $read = $patchedFile.Read($buffer, 0, $toRead)
                    if ($read -eq 0) { break }

                    $fs.Write($buffer, 0, $read)
                    $remaining -= $read
                    $written += $read

                    # Progress
                    if ($written % (10MB) -eq 0 -or $remaining -eq 0) {
                        $progress = [math]::Round(($written / $size) * 100, 1)
                        Write-Progress -Activity "Flashing $PartitionName" `
                            -Status "$([math]::Round($written/1MB, 2)) MB / $([math]::Round($size/1MB, 2)) MB" `
                            -PercentComplete $progress
                    }
                }

                $fs.Flush()
                Write-Progress -Activity "Flashing $PartitionName" -Completed

                Write-Host ""
                Write-Host "========================================" -ForegroundColor Green
                Write-Host "  SUCCESS! Partition flashed: $PartitionName" -ForegroundColor Green
                Write-Host "========================================" -ForegroundColor Green
                Write-Host ""
                Write-Host "  Total written: $written bytes ($([math]::Round($written/1MB, 2)) MB)" -ForegroundColor White
                Write-Host "  aggregate.img size: UNCHANGED" -ForegroundColor White
                Write-Host ""

                $found = $true
            }
            finally {
                $patchedFile.Close()
            }
            break
        }
    }

    if (-not $found) {
        Write-Host "ERROR: Partition '$PartitionName' not found!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Available partitions in this image:" -ForegroundColor Yellow
        Write-Host ""

        # List all partitions
        $fs.Seek($partitionsArrayLba * $LBS, [System.IO.SeekOrigin]::Begin) | Out-Null
        for ($i = 0; $i -lt $partitionsCount; $i++) {
            $entry = New-Object byte[] $partitionEntrySize
            $fs.Read($entry, 0, $partitionEntrySize) | Out-Null

            $typeGuid = $entry[0..15]
            $allZero = ($typeGuid | Where-Object { $_ -ne 0 }).Count -eq 0
            if ($allZero) { break }

            $nameBytes = $entry[56..127]
            $name = [System.Text.Encoding]::Unicode.GetString($nameBytes).TrimEnd([char]0)

            $firstLba = [BitConverter]::ToUInt64($entry, 32)
            $lastLba = [BitConverter]::ToUInt64($entry, 40)
            $partSize = ($lastLba - $firstLba + 1) * $LBS

            Write-Host "  - $name ($partSize bytes | $([math]::Round($partSize/1MB, 2)) MB)" -ForegroundColor Gray
        }
        Write-Host ""
        exit 1
    }
}
finally {
    $fs.Close()
}

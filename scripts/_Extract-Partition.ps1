<#
.SYNOPSIS
    Extract a partition from an aggregate.img
.DESCRIPTION
    Reads GPT partition table and extract a partition without external tools
.PARAMETER Dev
    Use Developer Emulator (DE) paths instead of production version
.PARAMETER AggregatePath
    Path to aggregate.img file (default: auto-detect based on -Dev switch)
.PARAMETER PartitionName
    Name of partition to extract (default: boot_a)
.PARAMETER OutputPath
    Path where boot_a.img will be saved (default: .\{WorkDir}\extracted\boot_a.img)
.PARAMETER WorkDir
    Path to working directory (default to patcher directory)
.EXAMPLE
    .\_Extract-Partition.ps1
    Extract boot_a from Production version to .\{WorkDir}\extracted\boot_a.img
.EXAMPLE
    .\_Extract-Partition.ps1 -Dev
    Extract boot_a from Developer Emulator (DE) to .\{WorkDir}\extracted\boot_a.img
.EXAMPLE
    .\_Extract-Partition.ps1 -OutputPath "D:\Custom_Path\boot_a.img"
    Extract to custom location
.EXAMPLE
    .\_Extract-Partition.ps1 -AggregatePath "D:\Custom_Path\aggregate.img"
    Extract from custom aggregate.img location
.EXAMPLE
    .\_Extract-Partition.ps1 -Dev -PartitionName "vbmeta_a"
    Extract vbmeta_a partition instead of boot_a
.NOTES
    Requires: PowerShell 5.1+ (Admin)
    Reference: https://github.com/chsbuffer/hpesuperpower/blob/2688f08fa2cb89790244f2d403f16a3c10ab4d85/PartitionCommand.cs#L75
#>

param(
    [switch]$Y,
    [switch]$Dev,
    [string]$AggregatePath,
    [string]$PartitionName = "boot_a",
    [string]$OutputPath,
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
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Extract $PartitionName from aggregate.img" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Check if GPGPC is running
Test-Running -Dev:$Dev -InstallDir $installDir

# Create new directories
$backupDir = Join-Path $WorkDir "backup"
New-Directory -Path $backupDir

$extractDir = Join-Path $WorkDir "extracted"
New-Directory -Path $extractDir

# Auto-determine aggregate.img path
if ([string]::IsNullOrEmpty($AggregatePath)) {
    $backupAggregate = Join-Path $backupDir "aggregate.img"
    if (Test-Path $backupAggregate) {
        $AggregatePath = $backupAggregate
    } else {
        $AggregatePath = "$installDir\emulator\avd\aggregate.img"
    }
} else {
    # Convert relative path to absolute path
    if (-not [System.IO.Path]::IsPathRooted($AggregatePath)) {
        $AggregatePath = Join-Path $WorkDir $AggregatePath
        $AggregatePath = [System.IO.Path]::GetFullPath($AggregatePath)
    }
    $versionName = "unknown"
}

# Set default output path to extracted folder in script directory
if ([string]::IsNullOrEmpty($OutputPath)) {
    $OutputPath = Join-Path $extractDir "$PartitionName.img"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $WorkDir $OutputPath
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
}

# Check if aggregate.img exists
if (-not (Test-Path $AggregatePath)) {
    Write-Host "ERROR: aggregate.img not found!" -ForegroundColor Red
    Write-Host "  Expected: $AggregatePath" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Try these solutions:" -ForegroundColor Cyan
    Write-Host ""

    if ($Dev) {
        Write-Host "  For Production:" -ForegroundColor Yellow
        Write-Host "    .\_Extract-Partition.ps1" -ForegroundColor White
    } else {
        Write-Host "  For Developer Emulator (DE):" -ForegroundColor Yellow
        Write-Host "    .\_Extract-Partition.ps1 -Dev" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "  For Custom Path:" -ForegroundColor Yellow
    Write-Host '    .\_Extract-Partition.ps1 -AggregatePath "C:\Your\Path\aggregate.img"' -ForegroundColor White
    Write-Host ""

    exit 1
}

Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  Version: $versionName" -ForegroundColor Gray
Write-Host "  aggregate.img file: $AggregatePath" -ForegroundColor Gray
Write-Host "  Partition: $PartitionName" -ForegroundColor Gray
Write-Host "  Output: $OutputPath" -ForegroundColor Gray
Write-Host "  Working directory: $WorkDir" -ForegroundColor Gray
Write-Host ""

Write-Host "Opening aggregate.img..." -ForegroundColor Green
Write-Host ""

# Constants
$LBS = 512  # Logical Block Size

$fs = [System.IO.File]::OpenRead($AggregatePath)

try {
    # Read GPT Header (LBA 1)
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

    # Parse GPT header fields
    $partitionsArrayLba = [BitConverter]::ToUInt64($gptHeader, 72)
    $partitionsCount = [BitConverter]::ToUInt32($gptHeader, 80)
    $partitionEntrySize = [BitConverter]::ToUInt32($gptHeader, 84)

    Write-Host "  GPT signature: OK" -ForegroundColor Gray
    Write-Host "  Partitions array LBA: $partitionsArrayLba" -ForegroundColor Gray
    Write-Host "  Partitions count: $partitionsCount" -ForegroundColor Gray
    Write-Host "  Entry size: $partitionEntrySize bytes" -ForegroundColor Gray
    Write-Host ""

    # Seek to partition entries array
    $fs.Seek($partitionsArrayLba * $LBS, [System.IO.SeekOrigin]::Begin) | Out-Null

    Write-Host "Searching for partition: '$PartitionName'..." -ForegroundColor Green
    $found = $false

    # Read partition entries
    for ($i = 0; $i -lt $partitionsCount; $i++) {
        $entry = New-Object byte[] $partitionEntrySize
        $fs.Read($entry, 0, $partitionEntrySize) | Out-Null

        # Check if partition type GUID is all zeros (end of list)
        $typeGuid = $entry[0..15]
        $allZero = ($typeGuid | Where-Object { $_ -ne 0 }).Count -eq 0
        if ($allZero) { break }

        # Read partition name (UTF-16LE, 72 bytes starting at offset 56)
        $nameBytes = $entry[56..127]
        $name = [System.Text.Encoding]::Unicode.GetString($nameBytes).TrimEnd([char]0)

        if ($name -eq $PartitionName) {
            # Parse partition location
            $firstLba = [BitConverter]::ToUInt64($entry, 32)
            $lastLba = [BitConverter]::ToUInt64($entry, 40)
            $offset = $firstLba * $LBS
            $size = ($lastLba - $firstLba + 1) * $LBS

            Write-Host ""
            Write-Host "Found partition: $name" -ForegroundColor Green
            Write-Host "  First LBA: $firstLba" -ForegroundColor Gray
            Write-Host "  Last LBA: $lastLba" -ForegroundColor Gray
            Write-Host "  Offset: $offset bytes (0x$($offset.ToString('X')))" -ForegroundColor Gray
            Write-Host "  Size: $size bytes ($([math]::Round($size/1MB, 2)) MB)" -ForegroundColor Gray
            Write-Host ""

            # Check if output file already exists
            if (Test-Path $OutputPath) {
                Write-Host "WARNING: Output file already exists!" -ForegroundColor Yellow
                Write-Host "  File: $OutputPath" -ForegroundColor Gray
                Write-Host ""

                # Compare SHA256 digests
                Write-Host "Comparing digest of existing file with partition data: $PartitionName" -ForegroundColor Green

                $digestFile = Join-Path $extractDir "_sha256-$PartitionName.txt"
                $sha256 = [System.Security.Cryptography.SHA256]::Create()

                # Get existing file hash: use cached digest if available, else compute
                if (Test-Path $digestFile) {
                    $existingHashStr = (Get-Content $digestFile -Raw).Trim()
                    Write-Host "  Existing file SHA256: $existingHashStr (cached)" -ForegroundColor Gray
                } else {
                    Write-Host "  No cached digest found, hashing existing file..." -ForegroundColor Gray
                    $existingStream = [System.IO.File]::OpenRead($OutputPath)
                    $existingHash = $sha256.ComputeHash($existingStream)
                    $existingStream.Close()
                    $existingHashStr = [BitConverter]::ToString($existingHash) -replace '-'
                    # Save computed digest to cache
                    Set-Content -Path $digestFile -Value $existingHashStr -Encoding ASCII
                    Write-Host "  Digest cached: $digestFile" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "  Existing file SHA256: $existingHashStr" -ForegroundColor Gray
                }

                # Hash partition data from aggregate
                $sha256.Initialize()
                $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null
                $hashBuffer = New-Object byte[] 4MB
                $hashRemaining = $size
                while ($hashRemaining -gt 0) {
                    $toRead = [Math]::Min($hashRemaining, $hashBuffer.Length)
                    $read = $fs.Read($hashBuffer, 0, $toRead)
                    if ($read -eq 0) { break }
                    $sha256.TransformBlock($hashBuffer, 0, $read, $null, 0) | Out-Null
                    $hashRemaining -= $read
                }
                $sha256.TransformFinalBlock(@(), 0, 0) | Out-Null
                $partitionHashStr = [BitConverter]::ToString($sha256.Hash) -replace '-'
                $sha256.Dispose()

                Write-Host "  Partition data SHA256: $partitionHashStr" -ForegroundColor Gray
                Write-Host ""

                if ($existingHashStr -eq $partitionHashStr) {
                    Write-Host "Digests match! Existing file is identical to partition data." -ForegroundColor Green
                    Write-Host "No extraction needed." -ForegroundColor Gray
                    Write-Host ""
                    $found = $true
                    break
                }

                Write-Host "Digests differ. Existing file does not match partition data." -ForegroundColor Yellow
                Write-Host ""

                $confirmText = "Delete and overwrite? (yes/no)"
                if ($Y) {
                    Write-Host "${confirmText}: yes" -ForegroundColor White
                    $overwrite = "yes"
                } else {
                    $overwrite = Read-Host $confirmText
                }

                if ($overwrite -eq "yes") {
                    Remove-Item $OutputPath -Force
                    Write-Host "Existing file deleted." -ForegroundColor Green
                    Write-Host ""
                } else {
                    Write-Host "Operation cancelled." -ForegroundColor Yellow
                    Write-Host ""
                    $found = $true  # prevent "not found" error
                    break
                }
            }

            # Extract partition data
            Write-Host "Extracting $PartitionName data..." -ForegroundColor Green
            $fs.Seek($offset, [System.IO.SeekOrigin]::Begin) | Out-Null

            $digestFile = Join-Path $extractDir "_sha256-$PartitionName.txt"
            $sha256Extract = [System.Security.Cryptography.SHA256]::Create()

            $outFile = [System.IO.File]::Create($OutputPath)
            try {
                $bufferSize = 4MB
                $buffer = New-Object byte[] $bufferSize
                $remaining = $size
                $extracted = 0

                while ($remaining -gt 0) {
                    $toRead = [Math]::Min($remaining, $bufferSize)
                    $read = $fs.Read($buffer, 0, $toRead)
                    if ($read -eq 0) { break }

                    $outFile.Write($buffer, 0, $read)
                    $sha256Extract.TransformBlock($buffer, 0, $read, $null, 0) | Out-Null
                    $remaining -= $read
                    $extracted += $read

                    # Progress indicator
                    if ($extracted % (10MB) -eq 0 -or $remaining -eq 0) {
                        $progress = [math]::Round(($extracted / $size) * 100, 1)
                        Write-Progress -Activity "Extracting $PartitionName" `
                            -Status "$([math]::Round($extracted/1MB, 2)) MB / $([math]::Round($size/1MB, 2)) MB" `
                            -PercentComplete $progress
                    }
                }
                Write-Progress -Activity "Extracting $PartitionName" -Completed

                # Finalize digest and save to sha256.txt
                $sha256Extract.TransformFinalBlock(@(), 0, 0) | Out-Null
                $extractedHashStr = [BitConverter]::ToString($sha256Extract.Hash) -replace '-'
                Set-Content -Path $digestFile -Value $extractedHashStr -Encoding ASCII
                Write-Host ""
                Write-Host "Digest saved: $digestFile" -ForegroundColor Gray

                Write-Host ""
                Write-Host "========================================" -ForegroundColor Green
                Write-Host "  SUCCESS! Partition extracted: $PartitionName" -ForegroundColor Green
                Write-Host "========================================" -ForegroundColor Green
                Write-Host "  Output file: $OutputPath" -ForegroundColor White
                Write-Host "  File size: $([math]::Round($size/1MB, 2)) MB" -ForegroundColor White
                Write-Host ""

                $found = $true
            }
            finally {
                $sha256Extract.Dispose()
                $outFile.Close()
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

            Write-Host "  - $name ($([math]::Round($partSize/1MB, 2)) MB)" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "Extract a different partition, for example:" -ForegroundColor Cyan
        Write-Host '  .\_Extract-Partition.ps1 -PartitionName "vbmeta_a"' -ForegroundColor White
        Write-Host ""
        exit 1
    }
}
finally {
    $fs.Close()
}

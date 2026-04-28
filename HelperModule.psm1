# =======================================================
# Helper functions for GPGPC patcher scripts
# =======================================================

function New-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Convert-ToWslPath {
    param([string]$WindowsPath)
    $absPath = [System.IO.Path]::GetFullPath($WindowsPath)
    $drive = $absPath.Substring(0, 1).ToLower()
    $pathWithoutDrive = $absPath.Substring(3).Replace('\', '/')
    return "/mnt/$drive/$pathWithoutDrive"
}

function Get-InstallDir {
    param([switch]$Dev)
    $prodDir = "C:\Program Files\Google\Play Games\current"
    $devDir = "C:\Program Files\Google\Play Games Developer Emulator\current"
    $installDir = if ($Dev) { $devDir } else { $prodDir }
    return $installDir
}

function Get-InstallVersion {
    param([string]$ServiceDir)
    $path = Join-Path $ServiceDir "Service.exe"
    if (Test-Path $path) {
        $version = (Get-Item $path).VersionInfo.FileVersion
        if (-not [string]::IsNullOrEmpty($version)) {
            $versionSafe = $version -replace '[ /\\:*?"<>|]', '_'
            return $versionSafe
        }
        return "unknown"
    } else {
        Write-Host "ERROR: Service.exe file not found in $ServiceDir" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please ensure that Google Play Games on PC (Prod/Dev) is installed correctly." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

function Test-Running {
    param(
        [switch]$Dev,
        [string]$installDir
    )
    $serviceExePath = Join-Path $installDir "service\Service.exe"
    $isRunning = Get-Process | Where-Object {
        try { $_.MainModule.FileName -eq $serviceExePath }
        catch { $false }
    } | Select-Object -First 1

    if ($isRunning) {
        Write-Host "ERROR: Google Play Games$(if ($Dev) { ' Developer Emulator' }) is still running!" -ForegroundColor Red
        Write-Host "Please close it completely." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Process found: $($isRunning.MainModule.FileName)" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
}

Export-ModuleMember -Function New-Directory, Convert-ToWslPath, Get-InstallDir, Get-InstallVersion, Test-Running

# Relaunch as admin if not already running as admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Restarting script as administrator..."
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Stop all services that start with "GooglePlayGamesServices"
$services = Get-Service -Name "GooglePlayGamesServices*"
foreach ($svc in $services) {
    Write-Host "Configuring service: $($svc.Name)"
    # Set startup type to Manual
    Set-Service -Name $svc.Name -StartupType Manual
    # Stop the service if it's running
    if ($svc.Status -eq 'Running') {
        Stop-Service -Name $svc.Name -Force
        Write-Host "Stopped service: $($svc.Name)"
    }
}

# Relaunch as admin if not already running as admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Restarting script as administrator..."
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Disable scheduled task "Google Play Games Notifier"
$taskName = "Google Play Games Notifier"
try {
    Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Output "Task '$taskName' has been disabled successfully."
} catch {
    Write-Error "Failed to disable task '$taskName'. Error details: $_"
}
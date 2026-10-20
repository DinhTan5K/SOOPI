$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $adbCmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($adbCmd) { $adb = $adbCmd.Source }
}

Write-Host "[SOOPI ADB Watcher] Dang theo doi thiet bi Android de tu dong forward port 5000..."

while ($true) {
    try {
        $devices = & $adb devices 2>$null
        if ($devices -match "\tdevice") {
            $reverseList = & $adb reverse --list 2>$null
            if ($reverseList -notmatch "tcp:5000") {
                & $adb reverse tcp:5000 tcp:5000 2>$null
                Write-Host "[SOOPI ADB Watcher] $(Get-Date -Format 'HH:mm:ss') -> Da tu dong forward port 5000 (adb reverse)!"
            }
        }
    } catch {
        # ignore errors
    }
    Start-Sleep -Seconds 2
}

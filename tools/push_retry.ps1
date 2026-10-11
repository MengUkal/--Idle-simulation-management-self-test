# push_retry.ps1 - git push with auto-retry for transient network failures (GitHub 502 flashes).
# Usage: powershell -File tools\push_retry.ps1 [-Remote origin] [-Branch main] [-Retries 3] [-DelaySec 20]
# Exit 0 = pushed; exit 1 = still failing (local is N commits ahead, push later).
param(
    [string]$Remote = "origin",
    [string]$Branch = "main",
    [int]$Retries = 3,
    [int]$DelaySec = 20
)

$git = "D:\Git\cmd\git.exe"
$root = Split-Path -Parent $PSScriptRoot

for ($i = 1; $i -le $Retries; $i++) {
    $null = & $git -C $root push $Remote $Branch 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Output "[push_retry] OK on attempt $i"; exit 0 }
    Write-Output "[push_retry] attempt $i/$Retries failed (exit $LASTEXITCODE)"
    if ($i -lt $Retries) { Start-Sleep -Seconds $DelaySec }
}

$ahead = & $git -C $root rev-list --count "$Remote/$Branch..$Branch" 2>$null
Write-Output "[push_retry] FAILED - local is ahead by $ahead commit(s); push later (rerun this script)."
exit 1

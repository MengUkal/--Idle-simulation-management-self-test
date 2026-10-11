# Android APK 构建管线（自装分享用：debug 签名）
# 用法: powershell -File tools\build_android.ps1
# 依赖: Godot 导出模板(4.7.2.stable.steam) + Android SDK(C:\Android\Sdk) + JDK(D:\JDK) + debug.keystore(~/.android)
$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot ".."
$godot = "F:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$sdk = "C:\Android\Sdk\build-tools\34.0.0"
$ks = Join-Path $env:USERPROFILE ".android\debug.keystore"

Write-Host "[1/3] Godot 导出 APK..."
& $godot --headless --path $root --export-release "Android" build/IdleTreeRPG.apk
if (-not (Test-Path (Join-Path $root "build\IdleTreeRPG.apk"))) { throw "导出失败" }

Write-Host "[2/3] debug 签名..."
& (Join-Path $sdk "apksigner.bat") sign --ks $ks --ks-pass pass:android --key-pass pass:android (Join-Path $root "build\IdleTreeRPG.apk")

Write-Host "[3/3] 验证..."
& (Join-Path $sdk "apksigner.bat") verify (Join-Path $root "build\IdleTreeRPG.apk")
if ($LASTEXITCODE -ne 0) { throw "签名验证失败" }

Get-Item (Join-Path $root "build\IdleTreeRPG.apk") | ForEach-Object { "完成: {0}  {1:N1} MB" -f $_.Name, ($_.Length / 1MB) }

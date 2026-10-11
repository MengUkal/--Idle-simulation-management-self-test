# preaccept.ps1 — 一键自动预验收（串行测试 + 场景冒烟 + 可选截图取证 + 落盘报告）
# ⚠ 本文件含中文，必须保持 UTF-8 with BOM；用工具改完后若被重写为无 BOM，需先补 BOM 再运行（powershell 5.1 无 BOM 按 GBK 读，全盘乱码）。
# 约定来源：docs/开发环境.md —— Godot tools 版是 GUI 子系统程序（必须 Start-Process -Wait -PassThru 取退出码）、
# 多实例会争 .godot 缓存（必须串行）、截屏旗标各场景不同（本脚本已封装）。
# 用法示例：
#   powershell -File tools\preaccept.ps1                                  # 全量（含 sim_test 长模拟，约 6~10 分钟）
#   powershell -File tools\preaccept.ps1 -SkipSim                         # 跳过长模拟
#   powershell -File tools\preaccept.ps1 -Only balance_test,settings_test # 只跑指定套件（跳过冒烟/取证）
#   powershell -File tools\preaccept.ps1 -Capture                         # 附加 UI 截图取证（窗口模式，会开窗口）
# 产物：build\preaccept\<时间戳>\report.md + 每套件 .out.log/.err.log（build/ 已 .gdignore，不入 Godot 导入）

param(
    [string]$Only = "",          # 逗号分隔套件名，只跑这些（隐含 -SkipSmoke -SkipCapture）
    [switch]$SkipSim,            # 跳过 sim_test（长模拟）
    [switch]$SkipSmoke,          # 跳过场景冒烟
    [switch]$Capture,            # 附加 UI 截图取证
    [int]$TimeoutSec = 1200,     # 单条 Godot 命令超时（秒）
    [string]$GodotExe = "F:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path $GodotExe)) { Write-Output "[preaccept] Godot 不存在：$GodotExe"; exit 2 }
if (-not (Test-Path (Join-Path $ProjectRoot "project.godot"))) { Write-Output "[preaccept] 工程根不对：$ProjectRoot"; exit 2 }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportDir = Join-Path $ProjectRoot "build\preaccept\$stamp"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

# 套件清单（kind=script 走 --script；kind=tscn 跑场景、由测试脚本自带退出码退出）
$scriptSuites = @("balance_test", "match3_test", "market_test", "skills_test", "sim_test")
$tscnSuites   = @("character_test", "talent_test", "paragon_test", "settings_test", "rebirth_e2e")
$smokeScenes  = @("res://scenes/title/title.tscn", "res://scenes/main/main.tscn")
$captureJobs  = @(
    @{ name = "capture_battle";   scene = "res://scenes/battle/battle.tscn"; extra = "-- --capture-debug" },
    @{ name = "capture_market";   scene = "res://scenes/market/market.tscn"; extra = "-- --capture-market" },
    @{ name = "capture_talents";  scene = "res://tests/cap_talents.tscn";    extra = "" },
    @{ name = "capture_paragon";  scene = "res://tests/cap_paragon.tscn";    extra = "" }
)

if ($SkipSim) { $scriptSuites = @($scriptSuites | Where-Object { $_ -ne "sim_test" }) }
$suites = @()
foreach ($s in $scriptSuites) { $suites += @{ name = $s; kind = "script" } }
foreach ($s in $tscnSuites)   { $suites += @{ name = $s; kind = "tscn" } }
$targeted = ($Only -ne "")
if ($targeted) {
    $wanted = @($Only -split '[,\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    $suites = @($suites | Where-Object { $wanted -contains $_.name })
    $missing = @($wanted | Where-Object { $suites.name -notcontains $_ })
    if ($missing.Count -gt 0) { Write-Output ("[preaccept] 未知套件名：{0}" -f ($missing -join ", ")); exit 2 }
}

# 跑一条 Godot 命令：落盘 stdout/stderr，超时强杀，返回 exit code
function Invoke-Godot([string]$ArgLine, [string]$LogBase) {
    $outLog = "$LogBase.out.log"; $errLog = "$LogBase.err.log"
    $p = Start-Process -FilePath $GodotExe -ArgumentList $ArgLine -PassThru -WindowStyle Hidden `
         -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $null = $p.Handle  # PS5.1：不先触碰句柄，退出后 $p.ExitCode 为空
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        $p.Kill()
        return @{ code = -1; out = $outLog; err = $errLog; timedOut = $true }
    }
    return @{ code = $p.ExitCode; out = $outLog; err = $errLog; timedOut = $false }
}

# 从日志数 PASS/FAIL（best-effort；权威判定是退出码）
function Count-Marks([string]$LogPath) {
    $pass = 0; $fail = 0
    if (Test-Path $LogPath) {
        foreach ($line in (Get-Content $LogPath -Encoding UTF8)) {
            if ($line -match '^PASS\b') { $pass++ }
            elseif ($line -match '^FAIL\b') { $fail++ }
        }
    }
    return @{ pass = $pass; fail = $fail }
}

$results = @()
function Add-Result([string]$Name, [string]$Kind, $R) {
    $m = Count-Marks $R.out
    $script:results += [pscustomobject]@{
        name = $Name; kind = $Kind; exit = $R.code; timedOut = $R.timedOut
        pass = $m.pass; fail = $m.fail; log = (Split-Path -Leaf $R.out)
    }
    Write-Output ("{0,-18} exit={1,-4} PASS={2,-4} FAIL={3}{4}" -f $Name, $R.code, $m.pass, $m.fail, $(if ($R.timedOut) { "  [TIMEOUT]" } else { "" }))
}

# 0) 无头导入：注册新资产 .import 与全局类缓存（新 PNG/新 class_name 的已知坑，先跑为敬）
Write-Output "[preaccept] 0) headless import ..."
$imp = Invoke-Godot ('--headless --path "' + $ProjectRoot + '" --import') (Join-Path $reportDir "00_import")
Add-Result "00_import" "import" $imp
$importOk = ($imp.code -eq 0)

# 1) 测试套件（严格串行）
Write-Output "[preaccept] 1) test suites (serial) ..."
foreach ($t in $suites) {
    if ($t.kind -eq "script") {
        $argLine = '--headless --path "' + $ProjectRoot + '" --script res://tests/' + $t.name + '.gd'
    } else {
        $argLine = '--headless --path "' + $ProjectRoot + '" res://tests/' + $t.name + '.tscn'
    }
    $r = Invoke-Godot $argLine (Join-Path $reportDir $t.name)
    Add-Result $t.name $t.kind $r
}

# 2) 场景冒烟（全量模式才有）
if (-not $targeted -and -not $SkipSmoke) {
    Write-Output "[preaccept] 2) scene smoke ..."
    foreach ($scene in $smokeScenes) {
        $argLine = '--headless --fixed-fps 60 --path "' + $ProjectRoot + '" ' + $scene + ' --quit-after 300'
        $r = Invoke-Godot $argLine (Join-Path $reportDir ("smoke_" + (Split-Path $scene -Leaf) -replace '\.tscn$', ''))
        Add-Result ("smoke_" + (Split-Path $scene -Leaf)) "smoke" $r
    }
}

# 3) UI 截图取证（窗口模式，需要真实渲染；产物在 tests\ 与 docs\screenshots\ 惯例位置）
if (-not $targeted -and $Capture) {
    Write-Output "[preaccept] 3) UI capture ..."
    foreach ($c in $captureJobs) {
        $argLine = '--path "' + $ProjectRoot + '" ' + $c.scene + $(if ($c.extra) { " " + $c.extra } else { "" })
        $r = Invoke-Godot $argLine (Join-Path $reportDir $c.name)
        Add-Result $c.name "capture" $r
    }
}

# 4) 报告落盘 + 汇总
$failed = @($script:results | Where-Object { $_.exit -ne 0 })
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# 自动预验收 · $stamp")
$md.Add("")
$md.Add("- 判定：**退出码权威**（0=过），PASS/FAIL 计数为日志 best-effort。")
$md.Add("- import: $(if ($importOk) { 'OK' } else { 'FAIL（会连带一切，先修 import）' })")
$md.Add("")
$md.Add("| 套件 | 类型 | exit | PASS | FAIL | 日志 |")
$md.Add("| --- | --- | --- | --- | --- | --- |")
foreach ($r in $script:results) {
    $md.Add("| $($r.name) | $($r.kind) | $(if ($r.exit -eq 0) { 'OK' } else { $r.exit })$(if ($r.timedOut) { ' TIMEOUT' }) | $($r.pass) | $($r.fail) | $($r.log) |")
}
$md.Add("")
$md.Add("**结论：$(if ($failed.Count -eq 0 -and $importOk) { '全绿 ✅' } else { "有 $($failed.Count) 项失败 ❌" })**（机器可验部分；听感/手感仍需人工终验）")
$reportPath = Join-Path $reportDir "report.md"
$md -join "`r`n" | Set-Content -Encoding UTF8 -Path $reportPath

Write-Output ""
Write-Output "[preaccept] 报告：$reportPath"
if ($failed.Count -eq 0 -and $importOk) { exit 0 } else { exit 1 }

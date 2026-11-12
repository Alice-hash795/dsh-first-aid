#Requires -Version 5.1
<#
.SYNOPSIS
  dsh-first-aid — DSH 自救工具（不依赖 DSH 运行）

.DESCRIPTION
  当 DeepSeek Harness 启动崩溃、进不去任何会话时，用它把数据备份出来、
  把配置回滚到上次可用版本、或者用最小配置把系统拉起来。

  设计原则：安全系统不依赖它要保护的系统。
  - 不加载 DSH、不需要 DSH 处于运行状态
  - 只读复制数据目录，从不删除
  - 所有脚本 UTF-8 无 BOM
  - SQLite 热备份（有 Python 时用 sqlite3.backup，没有则跳过并提示）

.PARAMETER Action
  snapshot 只备份（不碰配置、不启动）
  rescue   备份 + 回滚配置 + 启动 DSH
  minimal  极简启动：bundles 只剩官方两个包（完整配置保留为 package.full.json）
  check    只做配置体检（JSON/YAML 合法性、bundles 是否齐全）
  help     显示帮助

.PARAMETER TargetsFile
  配置文件路径，默认找脚本旁边的 targets.json，找不到则用内置默认值。

.EXAMPLE
  .\dsh-first-aid.ps1 -Action rescue

.EXAMPLE
  .\dsh-first-aid.ps1 -Action snapshot
#>
param(
    [ValidateSet('snapshot', 'rescue', 'minimal', 'check', 'help')]
    [string]$Action = 'help',
    [string]$TargetsFile = ''
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

function Write-Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor DarkYellow }
function Write-Bad($msg) { Write-Host "    $msg" -ForegroundColor Red }

function Show-Help {
    Write-Host @'
dsh-first-aid — DSH 自救工具（不依赖 DSH 运行）

用法:
  .\dsh-first-aid.ps1 -Action snapshot   只备份数据（最安全，随时可跑）
  .\dsh-first-aid.ps1 -Action rescue     备份 + 回滚配置 + 启动 DSH
  .\dsh-first-aid.ps1 -Action minimal    极简启动（只留官方两个包）
  .\dsh-first-aid.ps1 -Action check      配置体检，不写任何文件

配置:
  默认读取脚本同目录的 targets.json，字段见 targets.example.json。
  不提供时用内置探测：DSH_HOME 环境变量 → 常见目录 → 弹窗手选。

备份内容:
  sessions / storages / memory / evolve（SQLite 热备份）/ 各插件家目录 / 配置文件

备份位置:
  targets.json 里的 backupDir，默认 <脚本目录>/backups
'@ -ForegroundColor Gray
}

# ---------- 配置 ----------
function Get-DefaultTargets {
    [pscustomobject]@{
        dshHome      = $null
        profileName  = 'desktop'
        dshExe       = $null
        dataDirs     = @('sessions', 'storages', 'memory', 'evolve')
        extraHomes   = @()
        evolveDb     = 'evolve/memory.db'
        backupDir    = (Join-Path $ScriptDir 'backups')
        keep         = 10
        goodPatch    = 'good-cordis.patch.yml'
        goodPackage  = 'good-package.json'
        safeBundles  = @('@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app')
    }
}

function Load-Targets {
    $path = $TargetsFile
    if (-not $path) { $path = Join-Path $ScriptDir 'targets.json' }
    if ($path -and (Test-Path $path)) {
        Write-Ok "配置：$path"
        $cfg = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $def = Get-DefaultTargets
        foreach ($p in $def.PSObject.Properties) {
            if ($null -eq $cfg.PSObject.Properties[$p.Name]) {
                $cfg | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
            }
        }
        return $cfg
    }
    Write-Warn2 '没找到 targets.json，使用内置探测'
    return Get-DefaultTargets
}

function Resolve-PathCandidate($candidates) {
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $p = $c
        if ($p -match '^\$env:(\w+)$') {
            $p = [Environment]::GetEnvironmentVariable($Matches[1])
        }
        if (-not $p) { continue }
        $p = $p.Replace('/', '\')
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Resolve-DshHome($cfg) {
    $cands = @()
    if ($cfg.dshHome) { $cands += $cfg.dshHome }
    $cands += '$env:DSH_HOME'
    $cands += (Join-Path $env:USERPROFILE '.dsh')
    $cands += 'D:\DSH'
    $cands += 'C:\DSH'
    $found = Resolve-PathCandidate $cands
    if ($found) { return $found }

    # 运行中进程反推
    $proc = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) {
        Write-Warn2 "从运行中的进程反推：$($proc.Path)"
        foreach ($guess in @((Join-Path (Split-Path $proc.Path) '..\DSH'), (Join-Path $env:USERPROFILE '.dsh'))) {
            if (Test-Path $guess) { return (Resolve-Path $guess).Path }
        }
    }

    # 弹窗手选
    Write-Warn2 '找不到 DSH 数据目录，请手动选择'
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '选择 DSH 数据目录（里面有 profiles 的那一层）'
    if ($dlg.ShowDialog() -eq 'OK') { return $dlg.SelectedPath }
    return $null
}

function Resolve-DshExe($cfg) {
    $cands = @()
    if ($cfg.dshExe) { $cands += $cfg.dshExe }
    $cands += 'D:\deep seek\DeepSeek Harness.exe'
    $proc = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) { $cands = @($proc.Path) + $cands }
    return Resolve-PathCandidate $cands
}

function Find-Python {
    $cands = @()
    if ($env:DSH_HOME) { $cands += (Join-Path $env:DSH_HOME 'dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe') }
    $cands += (Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe')
    return Resolve-PathCandidate $cands
}

# ---------- 动作 ----------
function Invoke-Snapshot($cfg, $dshHome) {
    $backupDir = $cfg.backupDir
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zip = Join-Path $backupDir "rescue-$stamp.zip"
    $staging = Join-Path $ScriptDir "staging-$stamp"
    $items = @()

    foreach ($d in $cfg.dataDirs) {
        $p = Join-Path $dshHome $d
        if ((Test-Path $p) -and ($d -ne 'evolve')) { $items += $p }
    }
    foreach ($h in $cfg.extraHomes) {
        $hp = $h
        if ($hp -match '^\$env:(\w+)$') { $hp = [Environment]::GetEnvironmentVariable($Matches[1]) }
        if ($hp -and (Test-Path $hp)) { $items += $hp }
    }

    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    $profileDir = Join-Path $dshHome ("profiles\" + $cfg.profileName)
    foreach ($f in @('cordis.patch.yml', 'package.json', 'pnpm-lock.yaml')) {
        $src = Join-Path $profileDir $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $staging $f) -Force }
    }

    # evolve：SQLite 热备份
    $dbRel = $cfg.evolveDb
    if ($dbRel) {
        $memDb = Join-Path $dshHome $dbRel
        $py = Find-Python
        if ((Test-Path $memDb) -and $py) {
            $dst = Join-Path $staging 'memory.db'
            $dbPath = $memDb.Replace('\', '/')
            $pyCode = "import sqlite3,sys`nsrc=sqlite3.connect('file:$dbPath?mode=rw',uri=True)`ntry:`n    src.execute('PRAGMA wal_checkpoint(TRUNCATE)')`nexcept Exception: pass`ndst=sqlite3.connect(sys.argv[1])`nsrc.backup(dst)`ndst.close() `n"
            & $py -c $pyCode $dst 2>$null
            if (Test-Path $dst) { Write-Ok 'memory.db 热备份完成' } else { Write-Warn2 'memory.db 热备份失败，已跳过' }
        } elseif (Test-Path $memDb) {
            try {
                Copy-Item $memDb (Join-Path $staging 'memory.db') -Force
                Write-Warn2 '没有 Python，memory.db 用普通复制（可能不是最新）'
            } catch {
                Write-Warn2 'memory.db 被占用，跳过'
            }
        }
    }
    $items += $staging

    if ($items.Count -eq 0) {
        Write-Bad '没有可备份的内容'
        return $null
    }
    Write-Step "备份 -> $zip"
    Compress-Archive -Path $items -DestinationPath $zip -CompressionLevel Fastest -Force
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    $mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Ok "完成：$mb MB"

    Get-ChildItem $backupDir -Filter 'rescue-*.zip' | Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $cfg.keep | Remove-Item -Force -ErrorAction SilentlyContinue
    return $zip
}

function Invoke-Rescue($cfg, $dshHome) {
    $zip = Invoke-Snapshot $cfg $dshHome
    $profileDir = Join-Path $dshHome ("profiles\" + $cfg.profileName)

    Write-Step '回滚配置'
    $pairs = @(
        @((Join-Path $ScriptDir $cfg.goodPatch), (Join-Path $profileDir 'cordis.patch.yml')),
        @((Join-Path $ScriptDir $cfg.goodPackage), (Join-Path $profileDir 'package.json'))
    )
    foreach ($pair in $pairs) {
        $src, $dst = $pair
        if (-not (Test-Path $src)) { Write-Warn2 "缺少 $([System.IO.Path]::GetFileName($src))，跳过"; continue }
        if (Test-Path $dst) { Copy-Item $dst "$dst.before-rescue" -Force }
        Copy-Item $src $dst -Force
        Write-Ok "$([System.IO.Path]::GetFileName($dst)) 已恢复"
    }

    $exe = Resolve-DshExe $cfg
    Write-Step '启动 DSH'
    if ($exe) {
        Start-Process -FilePath $exe
        Write-Ok "已启动：$exe"
    } else {
        Write-Bad '找不到 DSH 可执行文件，请手动启动'
    }
    if ($zip) { Write-Ok "备份保留在：$zip" }
}

function Invoke-Minimal($cfg, $dshHome) {
    $profileDir = Join-Path $dshHome ("profiles\" + $cfg.profileName)
    $pkg = Join-Path $profileDir 'package.json'
    $patch = Join-Path $profileDir 'cordis.patch.yml'

    if (-not (Test-Path $pkg)) { throw "找不到 $pkg" }

    # 先备份
    Invoke-Snapshot $cfg $dshHome | Out-Null

    Write-Step '切换到最小配置'
    if (Test-Path (Join-Path $profileDir 'package.full.json')) {
        Remove-Item (Join-Path $profileDir 'package.full.json') -Force
    }
    Rename-Item $pkg 'package.full.json'
    Write-Ok '完整配置保留为 package.full.json'

    $minimal = [ordered]@{
        name = 'dsh-profile-desktop'
        private = $true
        dependencies = [ordered]@{}
        dsh = [ordered]@{ profile = [ordered]@{ bundles = $cfg.safeBundles } }
    } | ConvertTo-Json -Depth 6

    [System.IO.File]::WriteAllText($pkg, $minimal, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok '最小 package.json 已写入（无 BOM）'

    if (Test-Path $patch) {
        if (Test-Path "$patch.disabled") { Remove-Item "$patch.disabled" -Force }
        Rename-Item $patch 'cordis.patch.yml.disabled'
        Write-Ok 'cordis.patch.yml 已禁用'
    }

    $exe = Resolve-DshExe $cfg
    if ($exe) {
        Start-Process -FilePath $exe
        Write-Ok "已启动：$exe"
    } else {
        Write-Bad '找不到 DSH 可执行文件，请手动启动'
    }
}

function Invoke-Check($cfg, $dshHome) {
    $profileDir = Join-Path $dshHome ("profiles\" + $cfg.profileName)
    $fails = 0
    Write-Step "体检：$profileDir"

    $pkgPath = Join-Path $profileDir 'package.json'
    if (Test-Path $pkgPath) {
        $bytes = [System.IO.File]::ReadAllBytes($pkgPath)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Write-Bad 'package.json 带 BOM！'; $fails++
        } else {
            try { $pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json; Write-Ok 'package.json 合法且无 BOM' }
            catch { Write-Bad "package.json 解析失败：$($_.Exception.Message)"; $fails++ }
        }
        if ($pkg -and $pkg.dsh -and $pkg.dsh.profile -and $pkg.dsh.profile.bundles) {
            $nm = Join-Path $profileDir 'node_modules'
            foreach ($b in $pkg.dsh.profile.bundles) {
                if ($b -like '@deepseek-ai/*') { continue }
                if (-not (Test-Path (Join-Path $nm $b))) { Write-Bad "bundle 缺失：$b"; $fails++ }
            }
            if ($fails -eq 0) { Write-Ok "bundles 齐全（$($pkg.dsh.profile.bundles.Count) 个）" }
        }
    } else {
        Write-Bad '没有 package.json'; $fails++
    }

    $patchPath = Join-Path $profileDir 'cordis.patch.yml'
    if (Test-Path $patchPath) {
        $pb = [System.IO.File]::ReadAllBytes($patchPath)
        if ($pb.Length -ge 3 -and $pb[0] -eq 0xEF -and $pb[1] -eq 0xBB -and $pb[2] -eq 0xBF) {
            Write-Bad 'cordis.patch.yml 带 BOM！'; $fails++
        } else {
            Write-Ok 'cordis.patch.yml 无 BOM'
        }
    }

    Write-Host ''
    if ($fails -eq 0) { Write-Ok '体检通过' } else { Write-Bad "发现 $fails 处问题" }
    return $fails
}

# ---------- 主流程 ----------
if ($Action -eq 'help') { Show-Help; return }

$cfg = Load-Targets
$dshHome = Resolve-DshHome $cfg
if (-not $dshHome) { throw '无法确定 DSH 数据目录' }
Write-Ok "DSH 数据目录：$dshHome"

switch ($Action) {
    'snapshot' { $z = Invoke-Snapshot $cfg $dshHome; if ($z) { Write-Ok "备份：$z" } }
    'rescue' { Invoke-Rescue $cfg $dshHome }
    'minimal' { Invoke-Minimal $cfg $dshHome }
    'check' { $f = Invoke-Check $cfg $dshHome; exit $f }
}

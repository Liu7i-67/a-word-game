<#
.SYNOPSIS
    自动递增版本号并重新打包安卓 APK（已签名）。

.DESCRIPTION
    1. 读取 export_presets.cfg 里的 version/code 与 version/name。
    2. versionCode +1；versionName 按指定级别（patch/minor/major）递增。
    3. 运行 Godot --import 重新导入资源。
    4. 运行 Godot --export-release 导出并签名 APK。
    5. 用 apksigner 校验签名（如能找到 Android SDK）。

.PARAMETER VersionBump
    versionName 递增哪一段：patch(默认) / minor / major / none。
    versionCode 始终 +1（除非 none）。

.PARAMETER GodotPath
    Godot 控制台 exe 路径。留空则依次取 $env:GODOT / $env:GODOT4 / 自动探测。

.PARAMETER Preset
    导出预设名（默认 Android）。

.PARAMETER Output
    输出 APK 路径（默认 builds/a-word-game.apk）。

.EXAMPLE
    .\scripts\build_apk.ps1
    .\scripts\build_apk.ps1 -VersionBump minor
    .\scripts\build_apk.ps1 -VersionBump none   # 不改版本号，只重新打包
#>
param(
    [ValidateSet('patch', 'minor', 'major', 'none')]
    [string]$VersionBump = 'patch',
    [string]$GodotPath = '',
    [string]$Preset = 'Android',
    [string]$Output = ''
)

$ErrorActionPreference = 'Stop'
# 让中文输出在任意控制台编码下都正常显示
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$presetFile = Join-Path $root 'export_presets.cfg'

if (-not (Test-Path $presetFile)) {
    throw "找不到 export_presets.cfg：$presetFile"
}

# ---------- 1. 定位 Godot ----------
function Find-Godot([string]$Hint) {
    if ($Hint) {
        if (Test-Path $Hint) { return $Hint }
        throw "指定的 GodotPath 不存在：$Hint"
    }
    foreach ($v in 'GODOT', 'GODOT4', 'GODOT_BIN') {
        $e = [Environment]::GetEnvironmentVariable($v)
        if ($e -and (Test-Path $e)) { return $e }
    }
    $roots = @('E:\qbb', 'C:\Program Files', 'C:\Program Files (x86)', $env:LOCALAPPDATA, $env:USERPROFILE)
    foreach ($r in $roots) {
        if (-not $r -or -not (Test-Path $r)) { continue }
        $hits = @()
        try {
            $hits = Get-ChildItem -Path $r -Recurse -Depth 2 -File -Filter 'Godot*.exe' -ErrorAction SilentlyContinue
        } catch { }
        if ($hits) {
            $con = $hits | Where-Object { $_.Name -like '*console*' } | Select-Object -First 1
            if ($con) { return $con.FullName }
            return ($hits | Select-Object -First 1).FullName
        }
    }
    return $null
}

# ---------- 2. 定位 apksigner（可选校验） ----------
function Find-ApkSigner {
    $roots = @()
    foreach ($v in 'ANDROID_HOME', 'ANDROID_SDK_ROOT') {
        $e = [Environment]::GetEnvironmentVariable($v)
        if ($e) { $roots += $e }
    }
    $roots += 'E:\qbb\soft\android_sdk'   # 本机兜底
    foreach ($r in $roots) {
        $btDir = Join-Path $r 'build-tools'
        if (Test-Path $btDir) {
            $bt = Get-ChildItem -Path $btDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
            if ($bt) {
                $signer = Join-Path $bt.FullName 'apksigner.bat'
                if (Test-Path $signer) { return $signer }
            }
        }
    }
    return $null
}

# ---------- 3. 递增版本号 ----------
$content = [System.IO.File]::ReadAllText($presetFile)
$mCode = [regex]::Match($content, 'version/code=(\d+)')
$mName = [regex]::Match($content, 'version/name="([^"]*)"')
if (-not $mCode.Success -or -not $mName.Success) {
    throw 'export_presets.cfg 中未找到 version/code 或 version/name'
}
$curCode = [int]$mCode.Groups[1].Value
$curName = $mName.Groups[1].Value

$parts = $curName.Split('.')
while ($parts.Count -lt 3) { $parts += '0' }
$major = [int]$parts[0]; $minor = [int]$parts[1]; $patch = [int]$parts[2]
$newCode = $curCode + 1
switch ($VersionBump) {
    'major' { $major++; $minor = 0; $patch = 0 }
    'minor' { $minor++; $patch = 0 }
    'patch' { $patch++ }
    'none'  { $newCode = $curCode }
}
$newName = "$major.$minor.$patch"

if ($newCode -ne $curCode -or $newName -ne $curName) {
    Write-Host "版本号：$curName ($curCode)  ->  $newName ($newCode)" -ForegroundColor Cyan
    $content = [regex]::Replace($content, 'version/code=\d+', "version/code=$newCode")
    $content = [regex]::Replace($content, 'version/name="[^"]*"', "version/name=`"$newName`"")
    [System.IO.File]::WriteAllText($presetFile, $content)
} else {
    Write-Host "版本号不变：$curName ($curCode)" -ForegroundColor Cyan
}

# ---------- 4. 定位 Godot ----------
$godot = Find-Godot $GodotPath
if (-not $godot) {
    throw "未找到 Godot。请用 -GodotPath 指定，或设置环境变量 GODOT 指向 Godot 控制台 exe。"
}
Write-Host "Godot：$godot" -ForegroundColor DarkGray

# ---------- 5. 导入 + 导出 ----------
$buildsDir = Join-Path $root 'builds'
if (-not (Test-Path $buildsDir)) { New-Item -ItemType Directory -Path $buildsDir | Out-Null }
if (-not $Output) { $Output = Join-Path $buildsDir 'a-word-game.apk' }
elseif (-not [System.IO.Path]::IsPathRooted($Output)) { $Output = Join-Path $root $Output }

Write-Host "导入资源..." -ForegroundColor Yellow
& $godot --path "$root" --import
if ($LASTEXITCODE -ne 0) { throw "Godot 导入失败 (exit $LASTEXITCODE)" }

Write-Host "导出并签名 APK -> $Output" -ForegroundColor Yellow
& $godot --path "$root" --export-release $Preset "$Output"
if ($LASTEXITCODE -ne 0) { throw "Godot 导出失败 (exit $LASTEXITCODE)" }

if (-not (Test-Path $Output)) { throw "导出完成但找不到 APK：$Output" }

# ---------- 6. 校验签名 ----------
$signer = Find-ApkSigner
$sigOk = $null
if ($signer) {
    & $signer verify "$Output" 2>&1 | Out-Null
    $sigOk = ($LASTEXITCODE -eq 0)
} else {
    Write-Host "未找到 Android SDK / apksigner，跳过签名校验。" -ForegroundColor DarkGray
}

# ---------- 7. 汇总 ----------
$fi = Get-Item $Output
Write-Host ""
Write-Host "================ 打包完成 ================" -ForegroundColor Green
Write-Host ("版本   : {0} (versionCode {1})" -f $newName, $newCode)
Write-Host ("APK    : {0}" -f $fi.FullName)
Write-Host ("大小   : {0} MB" -f [math]::Round($fi.Length / 1MB, 1))
if ($sigOk -ne $null) {
    Write-Host ("签名   : {0}" -f $(if ($sigOk) { '已验证 ✓' } else { '校验失败 ✗' })) -ForegroundColor $(if ($sigOk) { 'Green' } else { 'Red' })
}
Write-Host "==========================================" -ForegroundColor Green

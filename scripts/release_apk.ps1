<#
.SYNOPSIS
    一条命令完成：递增版本号 → 打包签名 APK → 创建 GitHub Release 并上传 APK。

.DESCRIPTION
    1. 调用 scripts/build_apk.ps1 递增版本并打包（版本号写入 export_presets.cfg，不入库）。
    2. 从 env/.env 读取 GITHUB_TOKEN。
    3. 在 GitHub 仓库创建 tag（v{版本号}）与 Release，上传 APK 资产。
    若同名 tag 的 Release 已存在：更新其资产（先删同名旧资产再上传）。

.PARAMETER VersionBump
    递增级别：patch(默认) / minor / major / none。

.PARAMETER Repo
    GitHub 仓库（默认 Liu7i-67/a-word-game）。

.PARAMETER Notes
    Release 说明（默认自动生成一行）。

.EXAMPLE
    .\scripts\release_apk.ps1                    # patch +1 并发布
    .\scripts\release_apk.ps1 -VersionBump minor
    .\scripts\release_apk.ps1 -VersionBump none  # 不改版本号重新发布
#>
param(
    [ValidateSet('patch', 'minor', 'major', 'none')]
    [string]$VersionBump = 'patch',
    [string]$Repo = 'Liu7i-67/a-word-game',
    [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# ---------- 1. 打包（复用 build_apk.ps1：版本号 + 导入 + 导出 + 签名校验） ----------
& (Join-Path $PSScriptRoot 'build_apk.ps1') -VersionBump $VersionBump
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "打包失败 (exit $LASTEXITCODE)" }

# ---------- 2. 读取版本号 ----------
$presetFile = Join-Path $root 'export_presets.cfg'
$content = [System.IO.File]::ReadAllText($presetFile)
$verName = [regex]::Match($content, 'version/name="([^"]*)"').Groups[1].Value
$verCode = [regex]::Match($content, 'version/code=(\d+)').Groups[1].Value
if (-not $verName) { throw 'export_presets.cfg 中未找到 version/name' }
$tag = "v$verName"
$apk = Join-Path $root "builds\a-word-game.apk"
if (-not (Test-Path $apk)) { throw "找不到 APK：$apk" }
$apkName = "a-word-game-$verName.apk"

# ---------- 3. 读取 GITHUB_TOKEN（env/.env） ----------
$envFile = Join-Path $root 'env\.env'
if (-not (Test-Path $envFile)) { throw "找不到 $envFile" }
$token = $null
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*GITHUB_TOKEN\s*=\s*(.+?)\s*$') { $token = $Matches[1] }
}
if (-not $token) { throw 'env/.env 中未找到 GITHUB_TOKEN' }
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }

if (-not $Notes) { $Notes = "自动化发布：版本 $verName (versionCode $verCode)。`n`n- 安卓安装包：下载下方 $apkName 直接安装`n- 源码：master 分支" }

# ---------- 4. 查询/创建 Release ----------
$existing = $null
try {
    $existing = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/tags/$tag" -Method Get
} catch { }

if ($existing) {
    Write-Host "Release $tag 已存在（id=$($existing.id)），更新资产" -ForegroundColor Cyan
    $releaseId = $existing.id
    foreach ($a in @($existing.assets)) {
        if ($a.name -eq $apkName) {
            Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/assets/$($a.id)" -Method Delete | Out-Null
            Write-Host "已删除旧资产 $($a.name)" -ForegroundColor DarkGray
        }
    }
} else {
    $body = @{ tag_name = $tag; target_commitish = 'master'; name = $tag; body = $Notes; draft = $false; prerelease = $false } | ConvertTo-Json
    $created = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases" -Method Post -Body $body -ContentType 'application/json; charset=utf-8'
    $releaseId = $created.id
    Write-Host "已创建 Release $tag" -ForegroundColor Cyan
}

# ---------- 5. 上传 APK ----------
$uploadUri = "https://uploads.github.com/repos/$Repo/releases/$releaseId/assets?name=$apkName"
$uploaded = Invoke-RestMethod -Headers @{ Authorization = $headers.Authorization; Accept = $headers.Accept; 'X-GitHub-Api-Version' = $headers['X-GitHub-Api-Version'] } `
    -Uri $uploadUri -Method Post -InFile $apk -ContentType 'application/vnd.android.package-archive'
$fi = Get-Item $apk

# 上传接口的返回体里 html_url 可能为空，按 tag 重查一次拿权威地址
$rel = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repo/releases/tags/$tag" -Method Get

Write-Host ""
Write-Host "================ 发布完成 ================" -ForegroundColor Green
Write-Host ("版本    : {0} (versionCode {1})" -f $verName, $verCode)
Write-Host ("Release : {0}" -f $rel.html_url)
Write-Host ("资产    : {0}（{1} MB）" -f $apkName, [math]::Round($fi.Length / 1MB, 1))
Write-Host "==========================================" -ForegroundColor Green

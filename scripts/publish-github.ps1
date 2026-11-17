<#
.SYNOPSIS
  把 giwifi-ios 工程推送成 GitHub 仓库，触发 macOS runner 构建，并把产物 ipa 拉回本地。

.DESCRIPTION
  不依赖 git / gh / Xcode：全部走 GitHub REST API（Git Data API 一次性提交整棵树），
  然后在 Actions 上跑 .github/workflows/build-unsigned-ipa.yml，最后下载 artifact。
  兼容 Windows PowerShell 5.1 与 PowerShell 7+。

  需要一个 Personal Access Token（classic，勾选 repo + workflow；或 fine-grained，含
  Contents: read/write、Actions: read/write、Workflows: write）。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\publish-github.ps1 -Token ghp_xxx
  $env:ZF_GITHUB_TOKEN = 'ghp_xxx'; powershell -ExecutionPolicy Bypass -File scripts\publish-github.ps1   # token 走环境变量，不落命令行
  powershell -ExecutionPolicy Bypass -File scripts\publish-github.ps1 -Token ghp_xxx -Repo my-zf -Public   # 默认私有
  powershell -ExecutionPolicy Bypass -File scripts\publish-github.ps1 -Token ghp_xxx -SkipWorkflow        # 只推代码
#>
param(
    [string]$Token = $env:ZF_GITHUB_TOKEN,
    [string]$Owner,
    [string]$Repo = 'pangguai-ios',
    [string]$Branch = 'main',
    [switch]$Public,
    [switch]$SkipWorkflow,
    [string]$WorkflowFile = 'build-unsigned-ipa.yml',
    [int]$TimeoutMinutes = 40
)

if ([string]::IsNullOrWhiteSpace($Token)) {
    throw "缺少 GitHub token。用 -Token ghp_xxx 传入，或先设置 `$env:ZF_GITHUB_TOKEN。"
}

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { Add-Type -AssemblyName System.Net.Http } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ApiRoot = 'https://api.github.com'

$Headers = @{
    Authorization          = "Bearer $Token"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'giwifi-ios-publisher'
}

function Get-RelPath {
    param([string]$Base, [string]$Full)
    $prefix = $Base.TrimEnd('\') + '\'
    if ($Full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $Full.Substring($prefix.Length) }
    return $Full
}

function Invoke-Gh {
    param([string]$Method, [string]$Path, $Body, [switch]$Allow404)
    $uri = if ($Path.StartsWith('http')) { $Path } else { "$ApiRoot$Path" }
    $json = $null
    if ($null -ne $Body) {
        $json = ($Body | ConvertTo-Json -Depth 20 -Compress)
        # PowerShell 5.1 可能把空数组序列化成 null，GitHub 会拒绝
        $json = $json -replace '"parents":\s*null', '"parents": []'
    }

    $resp = $null
    try {
        if ($null -ne $json) {
            $bytes = [Text.Encoding]::UTF8.GetBytes($json)
            $resp = Invoke-WebRequest -Uri $uri -Method $Method -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body $bytes -UseBasicParsing
        } else {
            $resp = Invoke-WebRequest -Uri $uri -Method $Method -Headers $Headers -UseBasicParsing
        }
    } catch {
        $ex = $_.Exception
        $rawResponse = $null
        if ($ex -is [System.Net.WebException]) { $rawResponse = $ex.Response }
        $code = 0
        $text = $ex.Message
        if ($rawResponse) {
            $code = [int]$rawResponse.StatusCode
            try {
                $stream = $rawResponse.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $text = $reader.ReadToEnd()
                $reader.Close()
            } catch {}
        }
        # 空仓库上 Git Data API 的 GET 会返回 409（Git Repository is empty），与 404 一样当作"不存在"
        if (($code -eq 404 -or $code -eq 409) -and $Allow404) { return $null }
        if ($text -match 'refusing to allow a Personal Access Token to create or update workflow') {
            throw "Token 缺少 workflow 权限。请用 classic PAT 勾选 repo + workflow，或 fine-grained token 加 Workflows: write。`n$text"
        }
        throw "GitHub API $Method $Path 失败：HTTP $code`n$text"
    }

    if ($resp.StatusCode -ge 400) {
        if (($resp.StatusCode -eq 404 -or $resp.StatusCode -eq 409) -and $Allow404) { return $null }
        throw "GitHub API $Method $Path 失败：HTTP $($resp.StatusCode)`n$($resp.Content)"
    }
    if ([string]::IsNullOrWhiteSpace($resp.Content)) { return $null }
    return $resp.Content | ConvertFrom-Json
}

# ---------- 1. 身份与仓库 ----------
if (-not $Owner) {
    $me = Invoke-Gh GET '/user'
    $Owner = $me.login
    Write-Host "· 使用 token 身份：$Owner"
}

$repoInfo = Invoke-Gh GET "/repos/$Owner/$Repo" -Allow404
if ($repoInfo) {
    Write-Host "· 仓库已存在：$($repoInfo.full_name)"
} else {
    Write-Host "· 创建仓库 $Owner/$Repo …"
    $body = @{
        name        = $Repo
        private     = (-not $Public)
        auto_init   = $false
        description = '新正方（ZFSoft）教务助手 iOS 客户端 · 对齐 zhengfang-apk v1.0.135'
    }
    $repoInfo = Invoke-Gh POST '/user/repos' $body
    Start-Sleep -Seconds 3
}

# ---------- 2. 收集文件 ----------
$skipDirs = @('.git', 'build', 'dist', 'DerivedData', '.build', '.swiftpm', 'node_modules')
$skipFiles = @('Support/Info.plist')   # 由 xcodegen 生成，等同 .gitignore

$files = Get-ChildItem -Path $RootDir -Recurse -File -Force | Where-Object {
    $rel = (Get-RelPath $RootDir $_.FullName) -replace '\\', '/'
    $parts = $rel -split '/'
    $inSkipDir = $false
    foreach ($d in $skipDirs) { if ($parts -contains $d) { $inSkipDir = $true; break } }
    -not $inSkipDir -and
    ($skipFiles -notcontains $rel) -and
    -not $rel.EndsWith('.xcodeproj') -and
    -not $rel.EndsWith('.xcworkspace') -and
    $_.Name -ne '.DS_Store'
}

Write-Host "· 待上传文件：$($files.Count) 个"

# ---------- 3. 空仓库引导 ----------
# GitHub 的 Git Data API 在完全没有提交的仓库上会返回 409（Git Repository is empty），
# 所以先用 Contents API 落一个种子文件，把默认分支建出来。
$existingRef = Invoke-Gh GET "/repos/$Owner/$Repo/git/ref/heads/$Branch" -Allow404
if (-not $existingRef) {
    Write-Host "· 仓库还没有提交，先建立默认分支"
    $seedBody = @{
        message = 'chore: bootstrap repository'
        content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("# bootstrap`n"))
    }
    Invoke-Gh PUT "/repos/$Owner/$Repo/contents/.gitignore" $seedBody | Out-Null
    Start-Sleep -Seconds 2
    $repoNow = Invoke-Gh GET "/repos/$Owner/$Repo"
    if ($repoNow.default_branch -and $repoNow.default_branch -ne $Branch) {
        Write-Host "  （仓库默认分支为 $($repoNow.default_branch)，改用该分支）"
        $Branch = $repoNow.default_branch
    }
}

# ---------- 4. 逐文件写入（Contents API，空仓库/已有仓库都适用）----------
$written = 0
$lastSha = $null
foreach ($f in $files) {
    $written++
    $rel = (Get-RelPath $RootDir $f.FullName) -replace '\\', '/'
    $uri = "/repos/$Owner/$Repo/contents/$rel"
    # 注意：PowerShell 变量名允许 '?'，所以必须写成 ${uri}?ref=... 否则会被当成 $uri?ref
    $existing = Invoke-Gh GET "${uri}?ref=$Branch" -Allow404
    $body = @{
        message = 'feat(ios): 新正方教务助手 iOS 客户端，对齐上游 v1.0.135'
        content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName))
        branch  = $Branch
    }
    if ($existing -and $existing.sha) { $body.sha = $existing.sha }
    $res = Invoke-Gh PUT $uri $body
    if ($res -and $res.commit) { $lastSha = $res.commit.sha }
    Write-Host ("  [{0}/{1}] {2}" -f $written, $files.Count, $rel)
}
if (-not $lastSha) { throw "所有文件都写入失败，没有产生提交。" }
Write-Host "· 已提交：$($lastSha.Substring(0,7))"

if ($SkipWorkflow) {
    Write-Host "· 已跳过 Actions（-SkipWorkflow）"
    Write-Host "  仓库地址：https://github.com/$Owner/$Repo"
    return
}

# ---------- 5. 触发 workflow ----------
Write-Host "· 触发 Actions：$WorkflowFile"
# 私有仓库有时默认关掉 Actions，显式开启；失败不阻断（可能只是权限不足）
try {
    Invoke-Gh PUT "/repos/$Owner/$Repo/actions/permissions" @{ enabled = $true; allowed_actions = 'all' } | Out-Null
} catch {
    Write-Host "  （Actions 权限接口跳过：$($_.Exception.Message.Split("`n")[0])）"
}
$dispatchedAt = (Get-Date).ToUniversalTime().AddSeconds(-5)
$dispatched = $false
for ($try = 1; $try -le 10; $try++) {
    try {
        Invoke-Gh POST "/repos/$Owner/$Repo/actions/workflows/$WorkflowFile/dispatches" @{ ref = $Branch } | Out-Null
        $dispatched = $true
        break
    } catch {
        Write-Host "  第 $try 次触发未成功（workflow 可能尚未索引），等 10 秒：$($_.Exception.Message.Split("`n")[0])"
        Start-Sleep -Seconds 10
    }
}
if (-not $dispatched) { throw "无法触发 workflow。可手动打开 https://github.com/$Owner/$Repo/actions 点 Run workflow。" }

# ---------- 6. 轮询 ----------
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$run = $null
do {
    Start-Sleep -Seconds 15
    $runs = Invoke-Gh GET "/repos/$Owner/$Repo/actions/runs?branch=$Branch&per_page=5"
    $run = $runs.workflow_runs | Where-Object {
        $_.path -like "*$WorkflowFile" -and ([datetime]$_.created_at).ToUniversalTime() -ge $dispatchedAt
    } | Select-Object -First 1
    if (-not $run) { continue }
    Write-Host ("  {0} · {1} · {2}" -f $run.status, $run.conclusion, (Get-Date -Format 'HH:mm:ss'))
} while ($run -and $run.status -ne 'completed' -and (Get-Date) -lt $deadline)

if (-not $run) { throw "没有找到 workflow run。" }
Write-Host "· 结果：$($run.conclusion)  $($run.html_url)"

if ($run.conclusion -ne 'success') {
    $jobs = Invoke-Gh GET "/repos/$Owner/$Repo/actions/runs/$($run.id)/jobs"
    foreach ($j in $jobs.jobs) {
        foreach ($s in $j.steps) { if ($s.conclusion -eq 'failure') { Write-Host "  失败步骤：$($s.name)" } }
    }
    throw "构建失败，日志见 $($run.html_url)"
}

# ---------- 7. 下载 artifact ----------
$arts = Invoke-Gh GET "/repos/$Owner/$Repo/actions/runs/$($run.id)/artifacts"
$art = $arts.artifacts | Where-Object { $_.name -like '*ipa*' -and $_.name -notlike '*log*' } | Select-Object -First 1
if (-not $art) { throw "这次运行没有 ipa artifact。" }

$dist = Join-Path $RootDir 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zipPath = Join-Path $dist "$($art.name).zip"

# artifact zip 会 302 到 S3，那里不接受 Authorization 头，手动跟跳转
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $false
$client = New-Object System.Net.Http.HttpClient($handler)
$client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $Token)
$client.DefaultRequestHeaders.Add('User-Agent', 'giwifi-ios-publisher')
$client.DefaultRequestHeaders.Accept.Add((New-Object System.Net.Http.Headers.MediaTypeWithQualityHeaderValue('application/vnd.github+json')))

$first = $client.GetAsync("$ApiRoot/repos/$Owner/$Repo/actions/artifacts/$($art.id)/zip").GetAwaiter().GetResult()
if ($first.StatusCode -ne [System.Net.HttpStatusCode]::Found -and $first.StatusCode -ne [System.Net.HttpStatusCode]::Redirect) {
    throw "artifact 下载失败：HTTP $([int]$first.StatusCode) $($first.Content.ReadAsStringAsync().GetAwaiter().GetResult())"
}
$location = $first.Headers.Location
$anon = New-Object System.Net.Http.HttpClient
$bytes = $anon.GetByteArrayAsync($location).GetAwaiter().GetResult()
[IO.File]::WriteAllBytes($zipPath, $bytes)

Expand-Archive -Path $zipPath -DestinationPath $dist -Force
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Get-ChildItem $dist | Select-Object Name, Length | Format-Table -AutoSize

$ipa = Get-ChildItem $dist -Filter *.ipa -Recurse | Select-Object -First 1
Write-Host ""
if ($ipa) {
    Write-Host "完成：$($ipa.FullName)  ($([math]::Round($ipa.Length / 1MB, 2)) MB)"
    Write-Host "侧载：Sideloadly / AltStore / TrollStore 任选，免费证书 7 天有效。"
} else {
    Write-Host "已下载但未找到 .ipa，请检查 dist 目录。"
}
Write-Host "仓库：https://github.com/$Owner/$Repo"

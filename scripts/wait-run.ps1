param(
    [string]$Token = $env:ZF_GITHUB_TOKEN,
    [string]$Owner = '233576',
    [string]$Repo = 'giwifi-ios',
    [long]$RunId = 0,
    [int]$TimeoutMinutes = 45,
    [string]$OutDir = 'dist'
)

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$headers = @{
    Authorization = "Bearer $Token"
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'zf'
}

function Invoke-Gh {
    param([string]$Method, [string]$Path, $Body)
    $uri = "https://api.github.com$Path"
    for ($i = 0; $i -lt 8; $i++) {
        try {
            $params = @{
                UseBasicParsing = $true
                Method = $Method
                Uri = $uri
                Headers = $headers
                TimeoutSec = 40
            }
            if ($null -ne $Body) {
                $json = $Body | ConvertTo-Json -Depth 6 -Compress
                $params['Body'] = [Text.Encoding]::UTF8.GetBytes($json)
                $params['ContentType'] = 'application/json; charset=utf-8'
            }
            return Invoke-WebRequest @params
        } catch {
            Start-Sleep -Seconds (3 * ($i + 1))
        }
    }
    throw "GitHub API $Method $Path 连续失败"
}

if ($RunId -eq 0) {
    $resp = Invoke-Gh -Method GET -Path "/repos/$Owner/$Repo/actions/runs?per_page=5"
    $run = ($resp.Content | ConvertFrom-Json).workflow_runs | Select-Object -First 1
} else {
    $resp = Invoke-Gh -Method GET -Path "/repos/$Owner/$Repo/actions/runs/$RunId"
    $run = $resp.Content | ConvertFrom-Json
}

Write-Host "run $($run.run_number) $($run.status)/$($run.conclusion) sha=$($run.head_sha.Substring(0,7))"

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while ($run.status -ne 'completed' -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15
    $resp = Invoke-Gh -Method GET -Path "/repos/$Owner/$Repo/actions/runs/$($run.id)"
    $run = $resp.Content | ConvertFrom-Json
    Write-Host "  $((Get-Date).ToString('HH:mm:ss')) $($run.status) / $($run.conclusion)"
}

if ($run.status -ne 'completed') { throw '超时：run 仍未完成' }
if ($run.conclusion -ne 'success') {
    Write-Host "run 失败：$($run.conclusion)"
    $jobs = (Invoke-Gh -Method GET -Path "/repos/$Owner/$Repo/actions/runs/$($run.id)/jobs").Content | ConvertFrom-Json
    foreach ($job in $jobs.jobs) {
        Write-Host "job $($job.name) -> $($job.conclusion)"
    }
    throw "构建失败：$($run.conclusion)"
}

$arts = (Invoke-Gh -Method GET -Path "/repos/$Owner/$Repo/actions/runs/$($run.id)/artifacts").Content | ConvertFrom-Json
if (-not $arts.artifacts -or $arts.artifacts.Count -eq 0) { throw '没有 artifact' }

$target = $arts.artifacts | Where-Object { $_.name -like '*ipa*' } | Select-Object -First 1
if (-not $target) { $target = $arts.artifacts[0] }
Write-Host "artifact: $($target.name) $($target.size_in_bytes) B"

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$zipPath = Join-Path $OutDir '_artifact.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$client = New-Object Net.Http.HttpClient
$client.DefaultRequestHeaders.Authorization = New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer', $Token)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('zf')
$url = "https://api.github.com/repos/$Owner/$Repo/actions/artifacts/$($target.id)/zip"
$downloadUrl = $url
for ($i = 0; $i -lt 6; $i++) {
    try {
        $resp2 = $client.GetAsync($url, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
        if ([int]$resp2.StatusCode -ge 300 -and [int]$resp2.StatusCode -lt 400) {
            $downloadUrl = $resp2.Headers.Location.AbsoluteUri
            break
        }
        if ($resp2.IsSuccessStatusCode) { $downloadUrl = $url; break }
    } catch { }
    Start-Sleep -Seconds 5
}

$bytes = $client.GetByteArrayAsync($downloadUrl).Result
[IO.File]::WriteAllBytes($zipPath, $bytes)

$extract = Join-Path $OutDir '_artifact'
if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
[IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extract)

$ipa = Get-ChildItem $extract -Recurse -Filter '*.ipa' | Select-Object -First 1
if (-not $ipa) { throw '压缩包里没有 ipa' }
$final = Join-Path $OutDir 'GiWiFi-unsigned.ipa'
Copy-Item $ipa.FullName $final -Force
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "完成：$((Resolve-Path $final).Path)  ($([math]::Round((Get-Item $final).Length / 1KB, 1)) KB)"

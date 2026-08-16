param(
    [Parameter(Mandatory = $true)]
    [string]$CreatorRoot
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CreatorRoot)) {
    throw "CreatorRoot が見つかりません: $CreatorRoot"
}

$appD = Join-Path $CreatorRoot "source\app.d"
if (-not (Test-Path -LiteralPath $appD)) {
    throw "source\app.d が見つかりません。inochi-creator のリポジトリルートを指定してください: $CreatorRoot"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$bridgeSrc = Join-Path $repoRoot "creator-bridge\mcp"
if (-not (Test-Path -LiteralPath (Join-Path $bridgeSrc "package.d"))) {
    throw "ブリッジソースが見つかりません: $bridgeSrc"
}

$destDir = Join-Path $CreatorRoot "source\creator\mcp"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
Copy-Item -LiteralPath (Join-Path $bridgeSrc "package.d") -Destination (Join-Path $destDir "package.d") -Force
Copy-Item -LiteralPath (Join-Path $bridgeSrc "handlers.d") -Destination (Join-Path $destDir "handlers.d") -Force

$marker = "inochi-creator-mcp"
$content = [System.IO.File]::ReadAllText($appD)

if ($content -notmatch [regex]::Escape("import creator.mcp; // $marker")) {
    if ($content -notmatch "import creator;") {
        throw "source\app.d に 'import creator;' が見つかりません。手動で import creator.mcp; を追加してください。"
    }
    $content = $content.Replace("import creator;", "import creator;`r`nimport creator.mcp; // $marker")
}

if ($content -notmatch [regex]::Escape("incMcpInit(); // $marker")) {
    if ($content -notmatch "incInitAtlassing\(\);") {
        throw "source\app.d に incInitAtlassing(); が見つかりません。手動で incMcpInit(); を追加してください。"
    }
    $content = $content.Replace("incInitAtlassing();", "incInitAtlassing();`r`n        incMcpInit(); // $marker")
}

if ($content -notmatch [regex]::Escape("incMcpPoll(); // $marker")) {
    $needle = "inUpdate();"
    $insert = "inUpdate();`r`n    incMcpPoll(); // $marker"
    $count = ([regex]::Matches($content, [regex]::Escape($needle))).Count
    if ($count -lt 1) {
        throw "source\app.d に inUpdate(); が見つかりません。手動で incMcpPoll(); を追加してください。"
    }
    $content = $content.Replace($needle, $insert)
}

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($appD, $content, $utf8)

Write-Host "ブリッジを適用しました: $destDir"
Write-Host "次の手順: $CreatorRoot で dub ビルドし、Inochi Creator を起動してください。"
Write-Host "確認: curl http://127.0.0.1:17320/health"

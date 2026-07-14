#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$testRoot = Join-Path $PSScriptRoot "runtime_cache\installer-test"
$resolvedWorkspace = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
$resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
if (-not $resolvedTestRoot.StartsWith($resolvedWorkspace, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "测试目录不在工作区内：$resolvedTestRoot"
}
if (Test-Path -LiteralPath $resolvedTestRoot) {
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}

$homePath = Join-Path $resolvedTestRoot "home"
$appDataPath = Join-Path $resolvedTestRoot "appdata"
$editorSettingsPath = Join-Path $appDataPath "Code\User\settings.json"
$extensionPath = Join-Path $homePath ".vscode\extensions\anthropic.claude-code-test"
$webviewPath = Join-Path $extensionPath "webview\index.js"
$installerPath = Join-Path $PSScriptRoot "Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1"

New-Item -ItemType Directory -Path (Split-Path -Parent $editorSettingsPath) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $webviewPath) -Force | Out-Null
[System.IO.File]::WriteAllText($editorSettingsPath, "{`n    // keep this comment`n    `"editor.fontSize`": 14`n}")
$originalWebview = 'Type something... | New conversation | Yes, allow all edits this session | Update(${path}) | Added 2 lines, removed 1 line'
[System.IO.File]::WriteAllText($webviewPath, $originalWebview)
[System.IO.File]::WriteAllText((Join-Path $extensionPath "extension.js"), "Computing...")

$oldUserProfile = $env:USERPROFILE
$oldHome = $env:HOME
$oldAppData = $env:APPDATA
try {
    $env:USERPROFILE = $homePath
    $env:HOME = $homePath
    $env:APPDATA = $appDataPath

    & powershell -NoProfile -ExecutionPolicy Bypass -File $installerPath -Target All -ExperimentalToolText
    if ($LASTEXITCODE -ne 0) { throw "首次安装失败" }

    $claudeSettings = [System.IO.File]::ReadAllText(
        (Join-Path $homePath ".claude\settings.json"),
        [System.Text.Encoding]::UTF8
    ) | ConvertFrom-Json
    if ($claudeSettings.language -ne "chinese") { throw "Claude language 未写入" }
    if ((Get-Content $editorSettingsPath -Raw) -notmatch '"chatgpt\.localeOverride"\s*:\s*"zh-CN"') {
        throw "Codex IDE locale 未写入"
    }
    if ([System.IO.File]::ReadAllText($webviewPath) -notmatch "输入内容") { throw "Claude IDE 补丁未生效" }
    if ([System.IO.File]::ReadAllText($webviewPath) -notmatch '更新\(\$\{path\}\)') {
        throw "Claude 实验性工具文字补丁未生效"
    }

    $firstClaudeRules = Get-Content (Join-Path $homePath ".claude\CLAUDE.md") -Raw
    $firstCodexRules = Get-Content (Join-Path $homePath ".codex\AGENTS.md") -Raw
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installerPath -Target All
    if ($LASTEXITCODE -ne 0) { throw "重复安装失败" }
    if ((Get-Content (Join-Path $homePath ".claude\CLAUDE.md") -Raw) -ne $firstClaudeRules) {
        throw "Claude 规则重复执行后发生变化"
    }
    if ((Get-Content (Join-Path $homePath ".codex\AGENTS.md") -Raw) -ne $firstCodexRules) {
        throw "Codex 规则重复执行后发生变化"
    }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $installerPath -Target All -Check
    if ($LASTEXITCODE -ne 0) { throw "配置检查失败" }

    & powershell -NoProfile -ExecutionPolicy Bypass -File $installerPath -RestoreIdePatch
    if ($LASTEXITCODE -ne 0) { throw "恢复失败" }
    if ((Get-Content $webviewPath -Raw) -ne $originalWebview) { throw "恢复内容不一致" }

    Write-Host "Installer test OK" -ForegroundColor Green
}
finally {
    $env:USERPROFILE = $oldUserProfile
    $env:HOME = $oldHome
    $env:APPDATA = $oldAppData
}

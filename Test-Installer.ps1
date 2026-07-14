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
$cliPath = Join-Path $appDataPath "npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe"
$installerPath = Join-Path $PSScriptRoot "Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1"

New-Item -ItemType Directory -Path (Split-Path -Parent $editorSettingsPath) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $webviewPath) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $cliPath) -Force | Out-Null
[System.IO.File]::WriteAllText($editorSettingsPath, "{`n    // keep this comment`n    `"editor.fontSize`": 14`n}")
$originalWebview = '"Type something..." | "New conversation" | "Yes, allow all edits this session" | "Waiting for permission…" | "Loading sessions…" | "Checking working directory" | "Connecting to browser…" | "Task Completed" | "Update(${path})" | "Added 2 lines, removed 1 line"'
[System.IO.File]::WriteAllText($webviewPath, $originalWebview)
[System.IO.File]::WriteAllText((Join-Path $extensionPath "extension.js"), "Computing...")
$originalCli = 'Tips for getting started | What''s new | Run /init to create a CLAUDE.md file with instructions for Claude | /release-notes for more | What''s new in Bun v: | (ctrl+o to expand) | HH=f?o?"Searching for":"searching for":o?"Searched for":"searched for" | HH=f?o?"Reading":"reading":o?"Read":"read" | m===1?"pattern":"patterns" | S===1?"file":"files" | HH=f?o?"Listing":"listing":o?"Listed":"listed" | F===1?"directory":"directories" | Y=$?f.length===0?"Searching for":"searching for":f.length===0?"Searched for":"searched for" | Y=$?f.length===0?"Reading":"reading":f.length===0?"Read":"read" | Y=$?f.length===0?"Listing":"listing":f.length===0?"Listed":"listed" | H===1?"pattern":"patterns" | q===1?"file":"files" | A===1?"directory":"directories" | status:"Idle",statusColor | status:"Working\u2026",statusColor | status:"Waiting",statusColor | function _x1(H){if(H>=Kx1)return"almost done thinking";if(H>=$x1)return"thinking some more";if(H>=qx1)return"thinking more";if(H>=Hx1)return"still thinking";return"thinking"}'
[System.IO.File]::WriteAllText($cliPath, $originalCli)

$oldUserProfile = $env:USERPROFILE
$oldHome = $env:HOME
$oldAppData = $env:APPDATA
try {
    $env:USERPROFILE = $homePath
    $env:HOME = $homePath
    $env:APPDATA = $appDataPath

    $scanReport = & powershell -NoProfile -ExecutionPolicy Bypass -File $installerPath -Target Claude -ScanEnglishText | Out-String
    if ($LASTEXITCODE -ne 0 -or $scanReport -notmatch "Waiting for permission") {
        throw "英文状态扫描报告未发现测试文案"
    }

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
    if ([System.IO.File]::ReadAllText($webviewPath) -notmatch "正在等待授权") { throw "Claude 状态文字补丁未生效" }
    if ([System.IO.File]::ReadAllText($webviewPath) -match "Task Completed") { throw "Claude 状态英文仍有残留" }
    if ([System.IO.File]::ReadAllText($cliPath) -match "Tips for getting started|What's new \|") {
        throw "Claude CLI 欢迎页补丁未生效"
    }
    if (-not [System.IO.File]::ReadAllText($cliPath).Contains("What's new in Bun v:")) {
        throw "Claude CLI 补丁误改了 Bun 内部文字"
    }
    if ([System.IO.File]::ReadAllText($cliPath) -match "ctrl\+o to expand|Searching for|patterns|Reading|files|Listing|directories|Working\\u2026|Waiting") {
        throw "Claude CLI 工具摘要补丁未生效"
    }
    foreach ($text in @("正在搜索", "个匹配项", "正在读取", "个文件", "正在列出", "个目录", "工作中…", "等待")) {
        if (-not [System.IO.File]::ReadAllText($cliPath).Contains($text)) {
            throw "Claude CLI 译文缺失：$text"
        }
    }
    if ([System.IO.File]::ReadAllText($cliPath) -match 'almost done thinking|thinking some more|thinking more|still thinking') {
        throw "Claude CLI 思考阶段补丁未生效"
    }
    if ([System.IO.File]::ReadAllText($webviewPath) -notmatch '更新\(\$\{path\}\)') {
        throw "Claude 实验性工具文字补丁未生效"
    }

    $firstClaudeRules = Get-Content (Join-Path $homePath ".claude\CLAUDE.md") -Raw
    $firstCodexRules = Get-Content (Join-Path $homePath ".codex\AGENTS.md") -Raw
    $partiallyRevertedCli = [System.IO.File]::ReadAllText($cliPath).Replace('(ctrl+o 展开)   ', '(ctrl+o to expand)')
    [System.IO.File]::WriteAllText($cliPath, $partiallyRevertedCli)
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
    if ([System.IO.File]::ReadAllText($webviewPath) -ne $originalWebview) { throw "恢复内容不一致" }
    if ([System.IO.File]::ReadAllText($cliPath) -ne $originalCli) { throw "CLI 恢复内容不一致" }

    Write-Host "Installer test OK" -ForegroundColor Green
}
finally {
    $env:USERPROFILE = $oldUserProfile
    $env:HOME = $oldHome
    $env:APPDATA = $oldAppData
}

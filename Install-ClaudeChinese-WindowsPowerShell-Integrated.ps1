#requires -Version 5.1
<#
.SYNOPSIS
    为 Windows 上的 Claude Code 和 Codex 配置简体中文。

.DESCRIPTION
    - Claude：配置 ~/.claude/settings.json、~/.claude/CLAUDE.md，并可选修补 IDE 固定英文。
    - Codex：配置 ~/.codex/AGENTS.md，并启用 IDE 扩展自带的 zh-CN 资源。
    - IDE 补丁修改前会创建 .zh-cn-backup，只对白名单文字做精确替换。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1 -Target Codex

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1 -Check

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1 -RestoreIdePatch

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1 -ScanEnglishText
#>

[CmdletBinding()]
param(
    [ValidateSet("All", "Claude", "Codex")]
    [string]$Target = "All",
    [switch]$SkipIdePatch,
    [switch]$ExperimentalToolText,
    [switch]$RestoreIdePatch,
    [switch]$ScanEnglishText,
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)

    Write-Host ""
    Write-Host ("=" * 64) -ForegroundColor DarkGray
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("=" * 64) -ForegroundColor DarkGray
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )

    $propertyNames = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    if ($propertyNames -contains $Name) {
        $Object.PSObject.Properties[$Name].Value = $Value
    }
    else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Set-MarkedBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    $beginMarker = "<!-- BEGIN $Name -->"
    $endMarker = "<!-- END $Name -->"
    $block = $beginMarker + [Environment]::NewLine + $Content.Trim() +
        [Environment]::NewLine + $endMarker
    $existing = if (Test-Path -LiteralPath $Path) {
        [System.IO.File]::ReadAllText($Path)
    }
    else {
        ""
    }
    $pattern = "(?s)" + [regex]::Escape($beginMarker) + ".*?" +
        [regex]::Escape($endMarker)

    if ([regex]::IsMatch($existing, $pattern)) {
        $updated = [regex]::Replace(
            $existing,
            $pattern,
            [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $block }
        )
    }
    elseif ([string]::IsNullOrWhiteSpace($existing)) {
        $updated = $block + [Environment]::NewLine
    }
    else {
        $updated = $existing.TrimEnd() + [Environment]::NewLine +
            [Environment]::NewLine + $block + [Environment]::NewLine
    }

    Write-Utf8NoBom -Path $Path -Content $updated
}

function Get-EditorProfiles {
    $appData = if ($env:APPDATA) {
        $env:APPDATA
    }
    else {
        [Environment]::GetFolderPath("ApplicationData")
    }

    @(
        [PSCustomObject]@{
            Name = "VS Code"
            ExtensionRoot = Join-Path $HOME ".vscode\extensions"
            SettingsPath = Join-Path $appData "Code\User\settings.json"
        }
        [PSCustomObject]@{
            Name = "VS Code Insiders"
            ExtensionRoot = Join-Path $HOME ".vscode-insiders\extensions"
            SettingsPath = Join-Path $appData "Code - Insiders\User\settings.json"
        }
        [PSCustomObject]@{
            Name = "Cursor"
            ExtensionRoot = Join-Path $HOME ".cursor\extensions"
            SettingsPath = Join-Path $appData "Cursor\User\settings.json"
        }
        [PSCustomObject]@{
            Name = "Windsurf"
            ExtensionRoot = Join-Path $HOME ".windsurf\extensions"
            SettingsPath = Join-Path $appData "Windsurf\User\settings.json"
        }
    )
}

function Get-ClaudeExtensionDirectories {
    param([switch]$AllVersions)

    foreach ($profile in Get-EditorProfiles) {
        if (-not (Test-Path -LiteralPath $profile.ExtensionRoot)) {
            continue
        }

        $directories = @(
            Get-ChildItem -LiteralPath $profile.ExtensionRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "anthropic.claude-code-*" } |
                Sort-Object LastWriteTime -Descending
        )

        if ($AllVersions) {
            $directories
        }
        elseif ($directories.Count -gt 0) {
            $directories[0]
        }
    }
}

function Get-ClaudeCliBinaryPaths {
    @(
        (Join-Path $HOME ".local\bin\claude.exe"),
        (Join-Path $env:APPDATA "npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe")
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique
}

function Backup-FileOnce {
    param([Parameter(Mandatory)][string]$Path)

    $backupPath = "$Path.zh-cn-backup"
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    }
}

function Set-JsoncStringProperty {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $content = if (Test-Path -LiteralPath $Path) {
        [System.IO.File]::ReadAllText($Path)
    }
    else {
        "{}"
    }

    $escapedName = [regex]::Escape($Name)
    $pattern = '(?m)(?<prefix>"' + $escapedName + '"\s*:\s*)"(?:\\.|[^"\\])*"'
    if ([regex]::IsMatch($content, $pattern)) {
        $updated = [regex]::Replace(
            $content,
            $pattern,
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($match)
                $match.Groups["prefix"].Value + '"' + $Value + '"'
            }
        )
    }
    else {
        $openingBrace = $content.IndexOf("{")
        if ($openingBrace -lt 0) {
            throw "无法识别 JSONC 设置文件：$Path"
        }

        $tail = $content.Substring($openingBrace + 1)
        $needsComma = -not [regex]::IsMatch($tail, '^\s*(?://[^\r\n]*(?:\r?\n|$)|/\*.*?\*/\s*)*}')
        $entry = [Environment]::NewLine + '    "' + $Name + '": "' + $Value + '"'
        if ($needsComma) {
            $entry += ","
        }
        $updated = $content.Insert($openingBrace + 1, $entry)
    }

    Write-Utf8NoBom -Path $Path -Content $updated
}

function Update-ClaudeSettings {
    Write-Section "配置 Claude Code 用户设置"

    $directory = Join-Path $HOME ".claude"
    $path = Join-Path $directory "settings.json"
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    if (Test-Path -LiteralPath $path) {
        $raw = [System.IO.File]::ReadAllText($path)
        $config = if ([string]::IsNullOrWhiteSpace($raw)) {
            [PSCustomObject]@{}
        }
        else {
            try { $raw | ConvertFrom-Json } catch { throw "settings.json 无法解析：$path`n$($_.Exception.Message)" }
        }
    }
    else {
        $config = [PSCustomObject]@{}
    }

    Set-JsonProperty $config '$schema' "https://json.schemastore.org/claude-code-settings.json"
    Set-JsonProperty $config "language" "chinese"
    Set-JsonProperty $config "spinnerTipsEnabled" $false
    Set-JsonProperty $config "spinnerVerbs" ([PSCustomObject]@{
        mode = "replace"
        verbs = @("思考中", "分析中", "规划中", "处理中", "搜索中", "读取中", "修改中", "构建中", "测试中", "执行中")
    })

    Write-Utf8NoBom -Path $path -Content ($config | ConvertTo-Json -Depth 30)
    Write-Host "已更新：$path" -ForegroundColor Green
}

function Update-ClaudeInstructions {
    Write-Section "配置 Claude Code 全局中文规则"

    $path = Join-Path $HOME ".claude\CLAUDE.md"
    $rules = @'
# 全局中文输出规则

- 所有面向用户的回答、计划、进度、提问、错误分析和最终总结使用简体中文。
- 文件路径、文件名、代码、命令、参数、技术标识符、配置字段、Git 引用和原始错误信息保持原样。
- 工具执行后用一句中文说明实际结果，不重复代码，不虚构修改内容或数量。
- 需要确认或选择时使用中文提问；可以使用产品提供的交互工具，但标题、问题和选项必须为中文。
'@

    Set-MarkedBlock -Path $path -Name "CHINESE-OUTPUT-RULES" -Content $rules
    Write-Host "已更新：$path" -ForegroundColor Green
}

function Update-CodexInstructions {
    Write-Section "配置 Codex 全局中文规则"

    $codexDir = Join-Path $HOME ".codex"
    $path = Join-Path $codexDir "AGENTS.md"
    $overridePath = Join-Path $codexDir "AGENTS.override.md"
    $rules = @'
# 全局中文输出规则

- 所有面向用户的回答、计划、进度、提问、错误分析和最终总结使用简体中文。
- 文件路径、文件名、代码、命令、参数、技术标识符、配置字段、Git 引用和原始错误信息保持原样。
'@

    Set-MarkedBlock -Path $path -Name "CHINESE-OUTPUT-RULES" -Content $rules
    Write-Host "已更新：$path" -ForegroundColor Green

    if (Test-Path -LiteralPath $overridePath) {
        Set-MarkedBlock -Path $overridePath -Name "CHINESE-OUTPUT-RULES" -Content $rules
        Write-Host "检测到 $overridePath，已同步写入中文规则（否则 AGENTS.md 会被它完全覆盖）。" -ForegroundColor Yellow
        Write-Host "已更新：$overridePath" -ForegroundColor Green
    }
}

function Test-CodexExtensionInstalled {
    param([Parameter(Mandatory)]$Profile)

    if (-not (Test-Path -LiteralPath $Profile.ExtensionRoot)) {
        return $false
    }

    Get-ChildItem -LiteralPath $Profile.ExtensionRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "openai.chatgpt-*" } |
        Select-Object -First 1
}

function Update-CodexIdeLocale {
    Write-Section "启用 Codex IDE 原生中文资源"
    $updated = 0
    $skipped = @()

    foreach ($profile in Get-EditorProfiles) {
        $extension = Test-CodexExtensionInstalled -Profile $profile
        if (-not $extension) {
            if (Test-Path -LiteralPath $profile.SettingsPath) {
                $skipped += "$($profile.Name)（未安装 Codex 扩展）"
            }
            continue
        }

        Set-JsoncStringProperty -Path $profile.SettingsPath -Name "chatgpt.localeOverride" -Value "zh-CN"
        Write-Host "已更新 $($profile.Name) [$($extension.Name)]：$($profile.SettingsPath)" -ForegroundColor Green
        $updated++
    }

    if ($skipped.Count -gt 0) {
        Write-Host "跳过：$($skipped -join '；')" -ForegroundColor Yellow
    }
    if ($updated -eq 0) {
        Write-Host "未找到安装了 Codex 扩展的编辑器，已跳过 IDE 设置。" -ForegroundColor Yellow
    }
}

function Restore-ClaudeIdeBackups {
    Write-Section "恢复 Claude Code 界面补丁备份"
    $restored = 0

    foreach ($path in Get-ClaudeCliBinaryPaths) {
        $backupPath = "$path.zh-cn-backup"
        if (Test-Path -LiteralPath $backupPath) {
            Copy-Item -LiteralPath $backupPath -Destination $path -Force
            Remove-Item -LiteralPath $backupPath -Force
            Write-Host "已恢复：$path" -ForegroundColor Green
            $restored++
        }
    }

    foreach ($directory in @(Get-ClaudeExtensionDirectories -AllVersions)) {
        $backups = Get-ChildItem -LiteralPath $directory.FullName -Recurse -File `
            -Filter "*.zh-cn-backup" -ErrorAction SilentlyContinue
        foreach ($backup in $backups) {
            $originalPath = $backup.FullName -replace '\.zh-cn-backup$', ""
            Copy-Item -LiteralPath $backup.FullName -Destination $originalPath -Force
            Remove-Item -LiteralPath $backup.FullName -Force
            Write-Host "已恢复：$originalPath" -ForegroundColor Green
            $restored++
        }
    }

    if ($restored -eq 0) {
        Write-Host "没有找到 Claude Code IDE 备份。" -ForegroundColor Yellow
    }
    else {
        Write-Host "已恢复 $restored 个文件，请重新启动编辑器。" -ForegroundColor Green
    }
}

function Get-ClaudeCliReplacements {
    [ordered]@{
        'title:"Tips for getting started"' = 'title:"\u5165\u95e8\u63d0\u793a"'
        'title:"What''s new",lines:q,footer:q.length>0?' = 'title:"\u65b0\u7248",lines:q,footer:q.length?'
        'text:"Run /init to create a CLAUDE.md file with instructions for Claude"' = 'text:"\u8fd0\u884c /init \u521b\u5efa CLAUDE.md"'
        'footer:q.length>0?"/release-notes for more":void 0' = 'footer:q[0]?"\u66f4\u591a /release-notes":void 0'
        '"Check the Claude Code changelog for updates"' = '"\u67e5\u770b\u66f4\u65b0\u65e5\u5fd7"'
        'HH=f?o?"Searching for":"searching for":o?"Searched for":"searched for"' = 'HH=f?"\u6b63\u5728\u641c\u7d22":"\u5df2\u641c\u7d22"'
        'HH=f?o?"Reading":"reading":o?"Read":"read"' = 'HH=f?"\u8bfb\u53d6":"\u5df2\u8bfb"'
        'm===1?"pattern":"patterns"' = '"\u4e2a\u5339\u914d\u9879"'
        'S===1?"file":"files"' = '"\u4e2a\u6587\u4ef6"'
        'HH=f?o?"Listing":"listing":o?"Listed":"listed"' = 'HH=f?"\u5217\u51fa":"\u5df2\u5217"'
        'F===1?"directory":"directories"' = '"\u4e2a\u76ee\u5f55"'
        'Y=$?f.length===0?"Searching for":"searching for":f.length===0?"Searched for":"searched for"' = 'Y=$?"\u6b63\u5728\u641c\u7d22":"\u5df2\u641c\u7d22"'
        'Y=$?f.length===0?"Reading":"reading":f.length===0?"Read":"read"' = 'Y=$?"\u8bfb\u53d6":"\u5df2\u8bfb"'
        'Y=$?f.length===0?"Listing":"listing":f.length===0?"Listed":"listed"' = 'Y=$?"\u5217\u51fa":"\u5df2\u5217"'
        'H===1?"pattern":"patterns"' = '"\u4e2a\u5339\u914d\u9879"'
        'q===1?"file":"files"' = '"\u4e2a\u6587\u4ef6"'
        'A===1?"directory":"directories"' = '"\u4e2a\u76ee\u5f55"'
        'function _x1(H){if(H>=Kx1)return"almost done thinking";if(H>=$x1)return"thinking some more";if(H>=qx1)return"thinking more";if(H>=Hx1)return"still thinking";return"thinking"}' = 'function _x1(H){return H>=Kx1?"\u5373\u5c06\u5b8c\u6210":H>=qx1?"\u6df1\u5165\u601d\u8003":"\u601d\u8003\u4e2d"}'
    }
}

function Patch-ClaudeCliText {
    Write-Section "修补 Claude Code CLI 固定文字"
    $paths = @(Get-ClaudeCliBinaryPaths)
    if ($paths.Count -eq 0) {
        Write-Host "没有找到 Claude Code CLI，已跳过界面补丁。" -ForegroundColor Yellow
        return
    }

    foreach ($path in $paths) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $searchable = [System.Text.Encoding]::ASCII.GetString($bytes)
        $count = 0

        $backupPath = "$path.zh-cn-backup"
        $baselineSearchable = if (Test-Path -LiteralPath $backupPath) {
            [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($backupPath))
        }
        else {
            $searchable
        }
        $driftedPatterns = @()

        foreach ($entry in (Get-ClaudeCliReplacements).GetEnumerator()) {
            if ([System.Text.Encoding]::ASCII.GetString([System.Text.Encoding]::ASCII.GetBytes([string]$entry.Value)) -ne [string]$entry.Value) {
                throw "CLI 译文必须使用 ASCII 转义：$($entry.Key)"
            }
            $source = [System.Text.Encoding]::UTF8.GetBytes([string]$entry.Key)
            $replacement = [System.Text.Encoding]::UTF8.GetBytes([string]$entry.Value)
            if ($replacement.Length -gt $source.Length) {
                throw "CLI 译文长度超过原文：$($entry.Key)"
            }

            $entryCount = 0
            $offset = 0
            while (($offset = $searchable.IndexOf([string]$entry.Key, $offset, [System.StringComparison]::Ordinal)) -ge 0) {
                [System.Array]::Copy($replacement, 0, $bytes, $offset, $replacement.Length)
                for ($index = $replacement.Length; $index -lt $source.Length; $index++) {
                    $bytes[$offset + $index] = 0x20
                }
                $offset += $source.Length
                $entryCount++
            }
            $searchable = [System.Text.Encoding]::ASCII.GetString($bytes)
            $count += $entryCount

            if ($entryCount -eq 0 -and
                $baselineSearchable.Contains([string]$entry.Key) -and
                -not $searchable.Contains([string]$entry.Value)) {
                $driftedPatterns += [string]$entry.Key
            }
        }

        if ($driftedPatterns.Count -gt 0) {
            Write-Host "警告：以下白名单在历史 backup 中存在，但当前 CLI 找不到原文与译文，疑似升级后变量名漂移：" -ForegroundColor Red
            $driftedPatterns | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        }

        if ($count -eq 0) {
            Write-Host "没有发现尚未替换的 CLI 白名单英文：$path" -ForegroundColor Yellow
            continue
        }

        $backupPath = "$path.zh-cn-backup"
        $needsBackup = -not (Test-Path -LiteralPath $backupPath)
        if (-not $needsBackup) {
            $current = Get-Item -LiteralPath $path
            $backup = Get-Item -LiteralPath $backupPath
            $currentVersion = $current.VersionInfo.FileVersion
            $backupVersion = $backup.VersionInfo.FileVersion
            $needsBackup = if ($currentVersion -and $backupVersion) {
                $currentVersion -ne $backupVersion
            }
            else {
                $current.Length -ne $backup.Length
            }
        }
        if ($needsBackup) {
            Copy-Item -LiteralPath $path -Destination $backupPath -Force
        }
        try {
            [System.IO.File]::WriteAllBytes($path, $bytes)
        }
        catch [System.IO.IOException] {
            throw "Claude Code CLI 正在运行，无法修改：$path。请关闭所有 Claude Code 窗口后重试。"
        }
        Write-Host "已修改：$path（$count 处）" -ForegroundColor Green
    }
}

function Get-ClaudeIdeScriptPaths {
    param([Parameter(Mandatory)]$Directory)

    $paths = @(
        (Join-Path $Directory.FullName "extension.js"),
        (Join-Path $Directory.FullName "webview\index.js")
    )
    $assetsPath = Join-Path $Directory.FullName "webview\assets"
    if (Test-Path -LiteralPath $assetsPath) {
        $paths += @(Get-ChildItem $assetsPath -File -Filter "*.js" | Select-Object -ExpandProperty FullName)
    }
    $paths | Select-Object -Unique
}

function Get-ClaudeIdeReplacements {
    [ordered]@{
        "Type something..." = "输入内容……"
        "Type something…" = "输入内容……"
        "Chat about this" = "讨论这段内容"
        "Computing..." = "计算中……"
        "Computing…" = "计算中……"
        "New conversation" = "新建对话"
        "Open a new conversation in a new tab" = "在新标签页中打开新对话"
        "Yes, allow all edits this session" = "是，本次会话允许所有修改"
        "Yes, return to normal mode" = "是，返回普通模式"
        "Yes, and don't ask again" = "是，不再询问"
        "Yes, allow access to " = "是，允许访问 "
        "Yes, allow " = "是，允许 "
        "User declined to answer questions" = "用户暂未回答该问题"
        "Waiting for permission…" = "正在等待授权……"
        "Loading MCP servers…" = "正在加载 MCP 服务器……"
        "Loading context usage…" = "正在加载上下文用量……"
        "Loading usage data…" = "正在加载用量数据……"
        "Loading sessions…" = "正在加载会话……"
        "Checking working directory" = "正在检查工作目录"
        "Connecting to browser…" = "正在连接浏览器……"
        "Browser connected" = "浏览器已连接"
        "Connecting to claude.ai/code…" = "正在连接 claude.ai/code……"
        "Loading available plugins…" = "正在加载可用插件……"
        "Loading marketplaces…" = "正在加载插件市场……"
        "Loading models…" = "正在加载模型……"
        "Loading plugins…" = "正在加载插件……"
        "Adding marketplace…" = "正在添加插件市场……"
        "Loading..." = "加载中……"
        "Connecting…" = "正在连接……"
        "Failed to reconnect" = "重新连接失败"
        "Action completed" = "操作已完成"
        "Login failed" = "登录失败"
        "Edit failed" = "编辑失败"
        "Navigation completed" = "导航已完成"
        "Rename failed to compute edits" = "重命名无法计算编辑内容"
        "Task Completed" = "任务已完成"
        "Task Failed" = "任务失败"
        "Notebook Cell Completed" = "笔记本单元格已完成"
        "Notebook Cell Failed" = "笔记本单元格执行失败"
        "Terminal Command Failed" = "终端命令失败"
        "Command Failed" = "命令失败"
        "Voice Recording Stopped" = "语音录制已停止"
    }
}

function Show-EnglishStatusReport {
    Write-Section "英文状态残留扫描报告"
    $statusPattern = '(?i)\b(loading|connecting|connected|working|waiting|checking|processing|computing|completed|failed|running|starting|stopped|finished|interrupt|retrying)\b'
    $literalPatterns = @(
        '"(?<text>[A-Za-z][A-Za-z0-9 ,.''…!?()/:+&-]{2,120})"',
        '''(?<text>[A-Za-z][A-Za-z0-9 ,.''…!?()/:+&-]{2,120})'''
    )

    if ($Target -in @("All", "Claude")) {
        $directories = @(Get-ClaudeExtensionDirectories)
        if ($directories.Count -eq 0) {
            Write-Host "Claude IDE：未找到扩展。" -ForegroundColor Yellow
        }
        foreach ($directory in $directories) {
            $allContent = ""
            $phrases = foreach ($path in Get-ClaudeIdeScriptPaths -Directory $directory) {
                if (-not (Test-Path -LiteralPath $path)) { continue }
                $content = [System.IO.File]::ReadAllText($path)
                $allContent += $content
                foreach ($pattern in $literalPatterns) {
                    foreach ($match in [regex]::Matches($content, $pattern)) {
                        $text = $match.Groups["text"].Value
                        $looksInternal = $text -match '^[A-Za-z]+$' -or $text -match '^[a-z]+(?:[._-][a-z]+)+$' -or $text -cmatch '^[A-Z_]+$'
                        if (-not $looksInternal -and $text -match $statusPattern -and $text -match '[a-z]{3}') { $text }
                    }
                }
            }
            $whitelistHits = foreach ($text in (Get-ClaudeIdeReplacements).Keys) {
                $count = ([regex]::Matches($allContent, [regex]::Escape([string]$text))).Count
                if ($count -gt 0) { "[$count] $text" }
            }
            Write-Host "Claude IDE：$($directory.Name)" -ForegroundColor Cyan
            Write-Host "  白名单待翻译：$(@($whitelistHits).Count) 条" -ForegroundColor Cyan
            $whitelistHits | ForEach-Object { Write-Host "    $_" }

            $whitelist = @((Get-ClaudeIdeReplacements).Keys)
            $groups = @($phrases | Where-Object { $whitelist -notcontains $_ } | Group-Object | Sort-Object Count -Descending)
            Write-Host "  待人工确认：$($groups.Count) 条（仅报告，不自动替换；最多显示 40 条）" -ForegroundColor Yellow
            $groups | Select-Object -First 40 | ForEach-Object {
                Write-Host "    [$($_.Count)] $($_.Name)"
            }
        }
    }

    if ($Target -in @("All", "Codex")) {
        $command = Get-Command codex -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            Write-Host "Codex CLI：检测到 $($command.Source)" -ForegroundColor Cyan
            Write-Host "  TUI 固定英文位于原生二进制；官方无 locale/language 配置，本安装器不修改二进制。" -ForegroundColor Yellow
        }
        else {
            Write-Host "Codex CLI：未找到命令。" -ForegroundColor Yellow
        }
        Write-Host "Codex IDE：继续使用扩展自带的 zh-CN 资源，不全局替换资源包或内部 ID。" -ForegroundColor Cyan
    }
}

function Patch-ClaudeIdeText {
    param([switch]$EnableExperimentalToolText)

    Write-Section "修补 Claude Code IDE 固定文字"
    $directories = @(Get-ClaudeExtensionDirectories)
    if ($directories.Count -eq 0) {
        Write-Host "没有找到 Claude Code IDE 扩展，已跳过界面补丁。" -ForegroundColor Yellow
        return
    }

    $replacements = Get-ClaudeIdeReplacements
    $changedFiles = 0
    $replacementCount = 0

    foreach ($directory in $directories) {
        foreach ($path in Get-ClaudeIdeScriptPaths -Directory $directory) {
            if (-not (Test-Path -LiteralPath $path)) {
                continue
            }

            $original = [System.IO.File]::ReadAllText($path)
            $updated = $original
            $fileCount = 0
            foreach ($entry in $replacements.GetEnumerator()) {
                $matches = ([regex]::Matches($updated, [regex]::Escape([string]$entry.Key))).Count
                if ($matches -gt 0) {
                    $updated = $updated.Replace([string]$entry.Key, [string]$entry.Value)
                    $fileCount += $matches
                }
            }

            if ($EnableExperimentalToolText) {
                $patterns = @(
                    @{ Pattern = 'Update\(\$\{(?<value>[^}]+)\}\)'; Prefix = '更新' },
                    @{ Pattern = 'Read\(\$\{(?<value>[^}]+)\}\)'; Prefix = '读取' },
                    @{ Pattern = 'Write\(\$\{(?<value>[^}]+)\}\)'; Prefix = '写入' },
                    @{ Pattern = 'Create\(\$\{(?<value>[^}]+)\}\)'; Prefix = '创建' },
                    @{ Pattern = 'Delete\(\$\{(?<value>[^}]+)\}\)'; Prefix = '删除' },
                    @{ Pattern = 'Search\(\$\{(?<value>[^}]+)\}\)'; Prefix = '搜索' }
                )
                foreach ($item in $patterns) {
                    $prefix = [string]$item.Prefix
                    $matches = ([regex]::Matches($updated, [string]$item.Pattern)).Count
                    if ($matches -gt 0) {
                        $updated = [regex]::Replace(
                            $updated,
                            [string]$item.Pattern,
                            [System.Text.RegularExpressions.MatchEvaluator]{
                                param($match)
                                $prefix + "(`${$($match.Groups['value'].Value)})"
                            }
                        )
                        $fileCount += $matches
                    }
                }

                $statsPattern = 'Added (?<added>\d+) lines?, removed (?<removed>\d+) lines?'
                $matches = ([regex]::Matches($updated, $statsPattern)).Count
                if ($matches -gt 0) {
                    $updated = [regex]::Replace(
                        $updated,
                        $statsPattern,
                        [System.Text.RegularExpressions.MatchEvaluator]{
                            param($match)
                            "新增 $($match.Groups['added'].Value) 行，删除 $($match.Groups['removed'].Value) 行"
                        }
                    )
                    $fileCount += $matches
                }
            }

            if ($updated -ne $original) {
                Backup-FileOnce -Path $path
                Write-Utf8NoBom -Path $path -Content $updated
                Write-Host "已修改：$path" -ForegroundColor Green
                $changedFiles++
                $replacementCount += $fileCount
            }
        }
    }

    if ($changedFiles -eq 0) {
        Write-Host "没有发现尚未替换的白名单英文。" -ForegroundColor Yellow
    }
    else {
        Write-Host "修改文件数：$changedFiles；替换文字数：$replacementCount" -ForegroundColor Green
    }
}

function Test-ChineseSetup {
    Write-Section "检查中文配置"
    $failures = 0

    if ($Target -in @("All", "Claude")) {
        $settingsPath = Join-Path $HOME ".claude\settings.json"
        $instructionsPath = Join-Path $HOME ".claude\CLAUDE.md"
        try {
            $settings = [System.IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
            if ($settings.language -ne "chinese" -or $settings.spinnerTipsEnabled -ne $false) {
                throw "关键设置不匹配"
            }
            if (-not ([System.IO.File]::ReadAllText($instructionsPath).Contains("<!-- BEGIN CHINESE-OUTPUT-RULES -->"))) {
                throw "缺少中文规则标记"
            }
            Write-Host "Claude 配置正常。" -ForegroundColor Green
        }
        catch {
            Write-Host "Claude 配置异常：$($_.Exception.Message)" -ForegroundColor Red
            $failures++
        }
    }

    if ($Target -in @("All", "Codex")) {
        $instructionsPath = Join-Path $HOME ".codex\AGENTS.md"
        $overridePath = Join-Path $HOME ".codex\AGENTS.override.md"
        try {
            if (-not ([System.IO.File]::ReadAllText($instructionsPath).Contains("<!-- BEGIN CHINESE-OUTPUT-RULES -->"))) {
                throw "缺少中文规则标记"
            }
            if ((Test-Path -LiteralPath $overridePath) -and
                -not ([System.IO.File]::ReadAllText($overridePath).Contains("<!-- BEGIN CHINESE-OUTPUT-RULES -->"))) {
                Write-Host "警告：$overridePath 存在但缺少中文规则，会完全屏蔽 AGENTS.md。" -ForegroundColor Yellow
            }
            $checkedEditors = 0
            foreach ($profile in Get-EditorProfiles) {
                if (-not (Test-CodexExtensionInstalled -Profile $profile)) {
                    continue
                }
                if (Test-Path -LiteralPath $profile.SettingsPath) {
                    $content = [System.IO.File]::ReadAllText($profile.SettingsPath)
                    if ($content -notmatch '"chatgpt\.localeOverride"\s*:\s*"zh-CN"') {
                        throw "$($profile.Name) 已装 Codex 扩展但未启用 zh-CN"
                    }
                    $checkedEditors++
                }
            }
            Write-Host "Codex 配置正常；已检查 $checkedEditors 个装了 Codex 扩展的编辑器。" -ForegroundColor Green
        }
        catch {
            Write-Host "Codex 配置异常：$($_.Exception.Message)" -ForegroundColor Red
            $failures++
        }
    }

    if ($failures -gt 0) {
        throw "中文配置检查失败：$failures 项"
    }
}

try {
    if ($RestoreIdePatch) {
        Restore-ClaudeIdeBackups
        exit 0
    }
    if ($Check) {
        Test-ChineseSetup
        exit 0
    }
    if ($ScanEnglishText) {
        Show-EnglishStatusReport
        exit 0
    }

    if ($Target -in @("All", "Claude")) {
        Update-ClaudeSettings
        Update-ClaudeInstructions
        Patch-ClaudeCliText
        if (-not $SkipIdePatch) {
            Patch-ClaudeIdeText -EnableExperimentalToolText:$ExperimentalToolText
        }
    }
    if ($Target -in @("All", "Codex")) {
        Update-CodexInstructions
        Update-CodexIdeLocale
    }

    Write-Section "处理完成"
    Write-Host "请彻底关闭并重新打开编辑器，然后新建会话测试。" -ForegroundColor Green
    Write-Host "检查命令：powershell -File `"$PSCommandPath`" -Target $Target -Check"
    if ($Target -in @("All", "Claude") -and -not $SkipIdePatch) {
        Write-Host "Claude CLI 或扩展升级后可能需要重新运行本脚本。" -ForegroundColor Yellow
    }
}
catch {
    Write-Host ""
    Write-Host "执行失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

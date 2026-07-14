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
#>

[CmdletBinding()]
param(
    [ValidateSet("All", "Claude", "Codex")]
    [string]$Target = "All",
    [switch]$SkipIdePatch,
    [switch]$ExperimentalToolText,
    [switch]$RestoreIdePatch,
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

    $path = Join-Path $HOME ".codex\AGENTS.md"
    $rules = @'
# 全局中文输出规则

- 所有面向用户的回答、计划、进度、提问、错误分析和最终总结使用简体中文。
- 文件路径、文件名、代码、命令、参数、技术标识符、配置字段、Git 引用和原始错误信息保持原样。
'@

    Set-MarkedBlock -Path $path -Name "CHINESE-OUTPUT-RULES" -Content $rules
    Write-Host "已更新：$path" -ForegroundColor Green
}

function Update-CodexIdeLocale {
    Write-Section "启用 Codex IDE 原生中文资源"
    $updated = 0

    foreach ($profile in Get-EditorProfiles) {
        $hasEditor = (Test-Path -LiteralPath $profile.ExtensionRoot) -or
            (Test-Path -LiteralPath (Split-Path -Parent $profile.SettingsPath))
        if (-not $hasEditor) {
            continue
        }

        Set-JsoncStringProperty -Path $profile.SettingsPath -Name "chatgpt.localeOverride" -Value "zh-CN"
        Write-Host "已更新 $($profile.Name)：$($profile.SettingsPath)" -ForegroundColor Green
        $updated++
    }

    if ($updated -eq 0) {
        Write-Host "未找到受支持的编辑器，已跳过 IDE 设置。" -ForegroundColor Yellow
    }
}

function Restore-ClaudeIdeBackups {
    Write-Section "恢复 Claude Code IDE 扩展备份"
    $restored = 0

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

function Patch-ClaudeIdeText {
    param([switch]$EnableExperimentalToolText)

    Write-Section "修补 Claude Code IDE 固定文字"
    $directories = @(Get-ClaudeExtensionDirectories)
    if ($directories.Count -eq 0) {
        Write-Host "没有找到 Claude Code IDE 扩展，已跳过界面补丁。" -ForegroundColor Yellow
        return
    }

    $replacements = [ordered]@{
        "Type something..." = "输入内容……"
        "Type something…" = "输入内容……"
        "Chat about this" = "讨论这段内容"
        "Computing..." = "处理中……"
        "Computing…" = "处理中……"
        "New conversation" = "新建对话"
        "Open a new conversation in a new tab" = "在新标签页中打开新对话"
        "Yes, allow all edits this session" = "是，本次会话允许所有修改"
        "Yes, return to normal mode" = "是，返回普通模式"
        "Yes, and don't ask again" = "是，不再询问"
        "Yes, allow access to " = "是，允许访问 "
        "Yes, allow " = "是，允许 "
        "User declined to answer questions" = "用户暂未回答问题"
    }
    $changedFiles = 0
    $replacementCount = 0

    foreach ($directory in $directories) {
        $candidatePaths = @(
            (Join-Path $directory.FullName "extension.js"),
            (Join-Path $directory.FullName "webview\index.js")
        )
        $assetsPath = Join-Path $directory.FullName "webview\assets"
        if (Test-Path -LiteralPath $assetsPath) {
            $candidatePaths += @(Get-ChildItem $assetsPath -File -Filter "*.js" | Select-Object -ExpandProperty FullName)
        }

        foreach ($path in $candidatePaths | Select-Object -Unique) {
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
        try {
            if (-not ([System.IO.File]::ReadAllText($instructionsPath).Contains("<!-- BEGIN CHINESE-OUTPUT-RULES -->"))) {
                throw "缺少中文规则标记"
            }
            $checkedEditors = 0
            foreach ($profile in Get-EditorProfiles) {
                if (Test-Path -LiteralPath $profile.SettingsPath) {
                    $content = [System.IO.File]::ReadAllText($profile.SettingsPath)
                    if ($content -notmatch '"chatgpt\.localeOverride"\s*:\s*"zh-CN"') {
                        throw "$($profile.Name) 未启用 zh-CN"
                    }
                    $checkedEditors++
                }
            }
            Write-Host "Codex 配置正常；已检查 $checkedEditors 个编辑器。" -ForegroundColor Green
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

    if ($Target -in @("All", "Claude")) {
        Update-ClaudeSettings
        Update-ClaudeInstructions
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
        Write-Host "Claude 扩展升级后可能需要重新运行本脚本。" -ForegroundColor Yellow
    }
}
catch {
    Write-Host ""
    Write-Host "执行失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

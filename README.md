# ClaudeChinese

为 Windows 上的 Claude Code 和 Codex 配置简体中文。

## 支持范围

- Claude Code CLI：中文回答、中文状态词。
- Claude Code IDE：安全白名单内的固定界面文字。
- Codex CLI：通过全局 `AGENTS.md` 使用中文回答。
- Codex IDE：启用扩展自带的 `zh-CN` 本地化资源。
- 编辑器：VS Code、VS Code Insiders、Cursor、Windsurf。

## 使用

```powershell
# 同时配置 Claude 和 Codex
powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1

# 只配置一种产品
powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1 -Target Claude
powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1 -Target Codex

# 检查配置
powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1 -Check

# 恢复 Claude CLI/IDE 文件补丁
powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1 -RestoreIdePatch

# 扫描 Claude/Codex 可见英文状态残留
powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1 -ScanEnglishText
```

Claude CLI/IDE 升级后，固定文字补丁可能被覆盖，重新运行脚本即可。CLI 补丁只做等字节长度的白名单替换，并保留备份。Codex IDE 使用扩展原生中文资源，不修改扩展文件。Codex CLI 的 TUI 固定英文位于原生二进制中，扫描报告会提示，但安装器不会不安全地修改二进制或内部工具 ID。

## 测试

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-Installer.ps1
```

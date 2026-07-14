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

# 恢复 Claude IDE 文件补丁
powershell -ExecutionPolicy Bypass -File .\Install-ClaudeChinese-WindowsPowerShell-Integrated.ps1 -RestoreIdePatch
```

Claude 扩展升级后，固定文字补丁可能被覆盖，重新运行脚本即可。Codex IDE 使用扩展原生中文资源，不修改扩展文件。

## 测试

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-Installer.ps1
```

# ClaudeChinese

为 Windows 上的 Claude Code 和 Codex 配置简体中文。

## 支持范围与限制

不同层的汉化效果不同，请先了解边界：

### Claude Code
| 层 | 效果 | 说明 |
|---|---|---|
| CLI 模型回答 | 中文 | 通过 `~/.claude/settings.json` 的 `language=chinese` 和 `~/.claude/CLAUDE.md` 全局规则 |
| CLI 框架文字（spinner、欢迎页、工具摘要） | 中文 | 等字节长度二进制补丁，仅替换白名单 |
| IDE 固定文字 | 中文 | 等字节长度补丁，仅替换白名单 |

### Codex
| 层 | 效果 | 说明 |
|---|---|---|
| IDE UI 文字（菜单、按钮、提示） | 中文 | 通过扩展官方配置 `chatgpt.localeOverride=zh-CN`，强制使用扩展自带的 `zh-CN` 字典 |
| CLI 模型回答 | 软约束 | 通过 `~/.codex/AGENTS.md` 注入中文规则；属于 user 角色消息，模型遵循度中等，英文提问/思维链/长上下文仍可能漂移回英文 |
| CLI TUI 框架文字（spinner、菜单、状态栏） | **无法汉化** | 文字硬编码在 Rust 二进制中，无配置项可改 |

### 兼容编辑器
VS Code、VS Code Insiders、Cursor、Windsurf。**只有真正安装了 Codex 扩展（`openai.chatgpt-*`）的编辑器**才会被写入 `localeOverride`，避免凭空创建未使用编辑器的用户配置目录。

## Codex CLI 的额外注意事项

- 如果存在 `~/.codex/AGENTS.override.md`，它会**完全屏蔽** `AGENTS.md`。安装器会检测并同步把中文规则写入 override 文件，但如果你手工编辑过该文件，请检查标记块是否完整。
- 大仓库中 `project_doc_max_bytes` 预算共享，全局规则可能被尾部截断；当前规则块很小，正常使用不会触发。
- 项目根的 `AGENTS.md` 会与全局的拼接，模型可能优先遵循项目级规则。

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

Claude CLI/IDE 升级后，固定文字补丁可能被覆盖，重新运行脚本即可。CLI 补丁只做等字节长度的白名单替换，并保留备份。**如果 CLI 升级后白名单变量名漂移**，重装时脚本会用红色警告列出"疑似升级后变量名漂移"的条目，提示白名单需要更新。

汉化范围仅限 Claude/Codex 的固定界面文字；命令、参数、路径、技术标识以及 Bash/Git 等工具的实际 stdout/stderr 保持原样。

## 测试

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-Installer.ps1
```

测试覆盖：首次安装、重复安装幂等性、`-Check` 校验、`-RestoreIdePatch` 还原、CLI 升级后变量名漂移检测、未装 Codex 扩展的编辑器不被凭空创建。

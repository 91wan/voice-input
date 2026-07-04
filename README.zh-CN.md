# VoiceInput

### 按住 `Fn` 听写，松开后自动输入

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

VoiceInput 是一个 macOS 菜单栏语音输入工具，适合中英混输、技术词较多、需要快速把语音变成可编辑文本的场景。按住 `Fn` 键说话，松开后识别结果会自动插入当前光标位置。

核心链路：

```text
音频 -> Apple Speech -> DictionaryFilter -> 可选 LLMRefiner -> TextInjector
```

## 为什么选择 VoiceInput？

- **按住说话，松开输入**：300 ms 防误触，适合日常高频使用。
- **原生 Apple Speech**：不强制依赖第三方语音云服务。
- **确定性字典纠错**：常见 ASR 误识别先由字典层修正，速度快、结果可控。
- **可选 LLM 润色**：支持 OpenAI 兼容接口，可做语法修正或 Prompt Builder。
- **模式快捷入口**：`Fn` 使用当前默认 LLM 模式；`Option + Fn` 只对本次听写使用 Prompt Builder。
- **Readiness 面板**：被动检查辅助功能、输入监控、麦克风、语音识别、LLM 配置和词典加载状态。
- **插入失败兜底**：如果无法注入当前光标，文本会保留在剪贴板，避免内容丢失。
- **最近结果回看**：查看当前会话最近 10 条 raw / 字典过滤 / LLM 润色 / 最终输出，支持复制、重试插入和快速保存字典规则。
- **Dictionary Workbench**：保存前用测试短句预览过滤结果和命中的词典规则。
- **菜单栏优先**：主流程轻量，不需要打开复杂窗口。

## 功能特性

### 字典纠错

内置词典覆盖常见技术词：

| 识别结果 | 输出 |
| --- | --- |
| `open claw` | `OpenClaw` |
| `type script` | `TypeScript` |
| `java script` | `JavaScript` |
| `data base` | `database` |
| `配森` / `派森` | `Python` |
| `迪克耳` | `Docker` |
| `库伯内坦斯` | `Kubernetes` |
| `杰森` | `JSON` |
| `拉姆达` | `Lambda` |

打开 **菜单栏 -> Dictionary...** 可以编辑自定义规则：

```text
# 每行一条规则
type script -> TypeScript
open claw -> OpenClaw
my project -> MyProject
```

用户词典保存位置：

```text
~/Library/Application Support/VoiceInput/dictionary.json
```

Dictionary 窗口包含 **Test Phrase** 输入框。输入一句示例文本后，可以立即看到字典过滤后的输出和命中的规则；也可以用 **Import...** 从文本文件导入规则进行检查，用 **Export...** 把当前规则导出为便携文本。导入后不会自动覆盖已保存词典，只有点击 **Save** 后才会写入；规则格式错误会阻止保存/导出并直接提示。

### LLM 润色

打开 **菜单栏 -> LLM Refinement -> Settings** 配置 OpenAI 兼容接口。

- API Key 保存到 macOS Keychain。
- API Base URL 和模型名留空时会使用默认值。
- 设置窗口会显示当前状态：`Not configured`、`Ready` 或 `Test failed`。
- 未配置 API Key 时，普通 `Fn` 听写仍会走 Apple Speech + DictionaryFilter，不制造额外 LLM 失败噪音。
- **Precise Dictation** 尽量保留原始听写内容。
- **Prompt Builder** 会把口语整理成适合 ChatGPT、Claude、Cursor 等工具的结构化提示词。
- 按住 `Fn` 使用当前默认模式；`Option + Fn` 只对本次听写使用 Prompt Builder，不会改变默认设置。
- 如果 LLM 关闭或没有配置 API key，普通 `Fn` 仍会使用 Apple Speech + DictionaryFilter，不制造额外错误噪音。

## 快速开始

1. 从 [Releases](../../releases/latest) 下载最新 `VoiceInput.dmg`。
2. 将 `VoiceInput.app` 拖入 `/Applications`。
3. 启动应用。
4. 按提示授权 macOS 权限：
   - 麦克风
   - 语音识别
   - 辅助功能
   - 输入监控
5. 把光标放到任意输入框，按住 `Fn` 说话，松开后自动输入；需要临时整理 Prompt 时使用 `Option + Fn`。

如果辅助功能已经开启但 VoiceInput 仍提示权限失败，请使用 **Readiness... -> Fix Permission**。权限提示会使用 **Failed / Next / Reopen** 格式，明确当前失败点、下一步恢复动作，以及是否需要重开 VoiceInput。若更新后仍失败，请在“辅助功能 / 输入监控”中移除旧的 VoiceInput 项，再重新添加 `/Applications/VoiceInput.app`。

> 当前 GitHub DMG 是 **未签名 / 未 notarized** 构建。因此即使下载文件正常，macOS Gatekeeper 首次打开时也可能拦截。

如果 macOS 显示“Apple could not verify VoiceInput”：

1. 确认 `VoiceInput.app` 已放在 `/Applications`。
2. 右键 `VoiceInput.app`，选择 **打开**。
3. 在系统弹窗中再次确认 **打开**。

替代路径：打开 **系统设置 -> 隐私与安全性**，在页面底部附近允许 VoiceInput 打开，然后重新启动应用。

## 菜单栏控制

- **Language**：切换识别语言。
- **Readiness...**：查看辅助功能、输入监控、麦克风、语音识别、当前听写模式、LLM 和词典状态，不会主动请求新权限。
- **Dictionary...**：编辑确定性纠错规则。
- **Recent Results...**：查看当前会话最近 10 条听写结果，并快速添加字典纠错。
- **LLM Refinement**：启用、关闭、配置、切换默认润色模式，并查看 `Fn` / `Option + Fn` 快捷入口。
- **Quit**：退出 VoiceInput。

## 支持语言

可在菜单栏切换识别语言：

- 简体中文
- 繁体中文
- 英文
- 日文
- 韩文

## 从源码构建

要求：

- macOS 14 Sonoma 或更新版本
- Xcode Command Line Tools
- `Resources/AppIcon.icns` 是必需的构建输入

运行 PR 和 main push 使用的本地 CI 门禁：

```bash
make ci
```

运行本地 release 门禁，包括 DMG 打包和验证：

```bash
make release-check VERSION=1.6.0 DMG_PATH=/tmp/VoiceInput-test.dmg
```

构建 App bundle：

```bash
make build
```

本地运行：

```bash
make run
```

仅运行单元测试：

```bash
swift test --parallel
```

## Release 规则

- 每次发版前必须在 `CHANGELOG.md` 添加对应版本条目，例如 `## [v1.1.0] - YYYY-MM-DD`。
- 执行 `make version-bump VERSION=v1.1.0` 会更新版本元数据、验证 release notes、运行 local release gate、stage `README.md`、`Info.plist` 和 `CHANGELOG.md`，然后创建 tag。
- 执行 `make version-bump` 前，only `CHANGELOG.md` may be dirty；所有 source/test/script/workflow changes must be committed first。
- 执行 `make version-bump` 前必须位于最新的 configured release branch（默认 `main`），且本地 HEAD 必须与 `origin/main` 一致，metadata mutation 前会 fail closed。
- 如需使用其他 remote/branch，可执行 `make version-bump VERSION=vX.Y.Z REMOTE=upstream RELEASE_BRANCH=main`。
- `make version-bump` 会在创建 tag 前检查 local and remote tag collisions。
- 推送 `v*` tag 后，CI 会构建 macOS App、打包 `VoiceInput.dmg`，并从 `CHANGELOG.md` 生成 GitHub Release notes。
- 稳定公开发布前仍必须执行 `docs/release-qa-checklist.md` 中的 manual QA；`make release-check` 不替代真实 `Fn`、权限、首次启动验证。
- 大版本应同步更新 README 和产品定位。
- 小版本也必须有清晰的 GitHub Release notes。

## 项目结构

```text
Sources/VoiceInput/
  AppDelegate.swift          菜单栏生命周期与主流程编排
  KeyMonitor.swift           Fn 键监听
  SpeechEngine.swift         Apple Speech 录音与识别
  DictionaryFilter.swift     确定性字典纠错层
  DictionaryDocument.swift   字典导入/导出规范化
  DictionaryWorkbench.swift  字典测试短句评估
  LLMRefiner.swift           可选 OpenAI 兼容润色
  TextInjector.swift         光标注入与剪贴板兜底
  DictionaryWindow.swift     用户词典编辑器
  LastResultWindow.swift     当前会话最近结果回看
  ReadinessWindow.swift      被动启动与就绪检查
  SettingsWindow.swift       LLM 设置窗口
```

## FAQ

### 必须配置 LLM 吗？

不需要。Apple Speech 和 DictionaryFilter 不依赖 LLM。

### API Key 存在哪里？

API Key 保存到 macOS Keychain，不会明文写入 `UserDefaults`。

### 文本插入失败怎么办？

VoiceInput 会把生成文本留在剪贴板，用户可以手动粘贴。

### 是否包含遥测？

项目没有内置遥测服务。

## License

MIT

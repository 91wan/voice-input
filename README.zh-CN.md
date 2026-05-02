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
- **插入失败兜底**：如果无法注入当前光标，文本会保留在剪贴板，避免内容丢失。
- **最近结果回看**：查看最近一次 raw / 字典过滤 / LLM 润色 / 最终输出，支持复制、重试插入和快速保存字典规则。
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

### LLM 润色

打开 **菜单栏 -> LLM Refinement -> Settings** 配置 OpenAI 兼容接口。

- API Key 保存到 macOS Keychain。
- API Base URL 和模型名留空时会使用默认值。
- 启用 LLM 但未填写 API Key 时，会自动打开设置窗口提示补全。
- **Precise Dictation** 尽量保留原始听写内容。
- **Prompt Builder** 会把口语整理成适合 ChatGPT、Claude、Cursor 等工具的结构化提示词。

## 快速开始

1. 从 [Releases](../../releases/latest) 下载最新 `VoiceInput.dmg`。
2. 将 `VoiceInput.app` 拖入 `/Applications`。
3. 启动应用。
4. 按提示授权 macOS 权限：
   - 麦克风
   - 语音识别
   - 辅助功能
5. 把光标放到任意输入框，按住 `Fn` 说话，松开后自动输入。

> 当前构建是轻量 macOS App bundle。若首次启动被系统拦截，可在 **系统设置 -> 隐私与安全性** 中允许打开，或右键 App 选择 **打开**。

## 菜单栏控制

- **Language**：切换识别语言。
- **Dictionary...**：编辑确定性纠错规则。
- **Last Result...**：查看最近一次听写结果，并快速添加字典纠错。
- **LLM Refinement**：启用、关闭、配置并切换润色模式。
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

构建 App：

```bash
make build
```

本地运行：

```bash
make run
```

运行测试：

```bash
swift test --parallel
```

## Release 规则

- 每次发版前必须在 `CHANGELOG.md` 添加对应版本条目，例如 `## [v1.0.2] - YYYY-MM-DD`。
- 执行 `make version-bump VERSION=v1.0.2` 会更新版本元数据并创建 tag。
- 推送 `v*` tag 后，CI 会构建 macOS App、打包 `VoiceInput.dmg`，并从 `CHANGELOG.md` 生成 GitHub Release notes。
- 大版本应同步更新 README 和产品定位。
- 小版本也必须有清晰的 GitHub Release notes。

## 项目结构

```text
Sources/VoiceInput/
  AppDelegate.swift          菜单栏生命周期与主流程编排
  KeyMonitor.swift           Fn 键监听
  SpeechEngine.swift         Apple Speech 录音与识别
  DictionaryFilter.swift     确定性字典纠错层
  LLMRefiner.swift           可选 OpenAI 兼容润色
  TextInjector.swift         光标注入与剪贴板兜底
  DictionaryWindow.swift     用户词典编辑器
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

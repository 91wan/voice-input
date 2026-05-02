# VoiceInput

> version-v1.0.1 | date-2026-05-02

macOS 菜单栏语音输入工具。按住 `Fn` 键说话，松开后自动将语音转为文字并注入当前光标位置。

## 功能

- **按住 Fn 说话，松开输出**：短于 300ms 的单次点按不触发，避免误激活
- **原生 Apple Speech 识别**：离线/在线混合，支持中英文多语言
- **字典层纠错**：内置专有名词词典（OpenClaw、Python、Docker 等），确定性替换，<1ms，零 GPU 消耗
- **LLM 二次润色**：可选接入 OpenAI 兼容 API，处理字典层无法覆盖的上下文语法纠错（的/地/得、长句重组）
- **Prompt Builder 模式**：可选把口语整理成适合 ChatGPT / Claude / Cursor 的结构化提示词，默认仍保持精准听写
- **用户自定义词典**：菜单栏 → Dictionary...，每行一条规则（`错误词 → 正确词`），保存即生效
- **插入失败兜底**：如果无法把文字插入当前光标，结果会保留在剪贴板，避免语音内容丢失
- **零外部依赖**：App bundle 仅依赖系统框架，可直接拖入 `/Applications` 使用

## 纠错管道

```
音频 → Apple Speech → 字典层（确定性）→ LLM 润色（概率性）→ 输出
```

字典层拦截高频专有名词和已知 ASR 误识别词，LLM 只处理无法用规则表达的上下文语法问题，延迟更低、token 消耗更少。

## 使用

1. 将 `VoiceInput.app` 拖入 `/Applications`
2. 首次启动授权：隐私与安全性 → 辅助功能 + 语音识别 + 麦克风
3. 按住 `Fn` 键说话，松开后文字自动注入光标位置

## 语言支持

菜单栏图标 → Language 切换：中文(简体/繁体)、英文、日语、韩语

## 字典层（内置 + 用户自定义）

内置词典已覆盖常见技术词 ASR 误识别：

| ASR 错误输出 | 正确结果 |
|-------------|---------|
| open claw | OpenClaw |
| type script | TypeScript |
| java script | JavaScript |
| data base | database |
| 配森 / 派森 | Python |
| 迪克耳 | Docker |
| 库伯内坦斯 | Kubernetes |
| 杰森 | JSON |
| 拉姆达 | Lambda |

**自定义词典**：菜单栏 → Dictionary... 打开编辑窗口，格式：

```
# 注释行
type script → TypeScript
open claw → OpenClaw
my project → MyProject
```

保存后立即生效，无需重启。词典文件存储于 `~/Library/Application Support/VoiceInput/dictionary.json`。

## LLM 润色（可选）

菜单栏 → LLM Refinement → Settings，填入 OpenAI 兼容接口地址、API Key 和模型名。

- API Key 会保存到 macOS Keychain，不再明文落在 `UserDefaults`
- 如果没填 API Key 就尝试启用 LLM，应用会直接打开设置窗口并提示补全
- 留空 API Base URL / Model 会自动回落到默认值（`https://api.openai.com/v1` / `gpt-4o-mini`）
- 菜单栏 → LLM Refinement → Mode 可切换 `Precise Dictation` / `Prompt Builder`

推荐搭配本地模型（如 LM Studio + Gemma）以获得最低延迟。字典层已处理专有名词，LLM 只需处理语法粘合，8B 模型完全够用。

## Release policy

- 每次发版前都必须在 `CHANGELOG.md` 添加对应版本条目，例如 `## [v1.0.2] - YYYY-MM-DD`
- `make version-bump VERSION=v1.0.2` 会更新 README 版本/日期、Info.plist，并在打 tag 前检查 changelog 条目是否存在
- GitHub Release 的正文由对应 `CHANGELOG.md` 条目生成，因此 patch/minor 版本也必须有 release notes

## 构建

需要 Xcode Command Line Tools + macOS 14+：

```bash
make build
```

## 系统要求

- macOS 14 Sonoma+
- Apple Silicon 或 Intel

## License

MIT

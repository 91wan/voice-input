# VoiceInput

macOS 菜单栏语音输入工具。按住 `Fn` 键说话，松开后自动将语音转为文字并注入当前光标位置。

## 功能

- **按住 Fn 说话，松开输出**：短于 300ms 的单次点按不触发，避免误激活
- **原生 Apple Speech 识别**：离线/在线混合，支持中英文多语言
- **LLM 二次润色**：可选接入 OpenAI 兼容 API，自动修正技术词同音字错误（如"配森"→Python）
- **零外部依赖**：App bundle 仅依赖系统框架，可直接拖入 `/Applications` 使用

## 使用

1. 将 `VoiceInput.app` 拖入 `/Applications`
2. 首次启动授权：隐私与安全性 → 辅助功能 + 语音识别 + 麦克风
3. 按住 `Fn` 键说话，松开后文字自动注入光标位置

## 语言支持

菜单栏图标 → Language 切换：中文(简体/繁体)、英文、日语、韩语

## LLM 润色（可选）

菜单栏 → LLM Refinement → Settings，填入 OpenAI 兼容接口地址、API Key 和模型名。

## 构建

需要 Xcode Command Line Tools + macOS 14+：

```bash
swift build -c release
cp .build/release/VoiceInput VoiceInput.app/Contents/MacOS/VoiceInput
```

## 系统要求

- macOS 14 Sonoma+
- Apple Silicon 或 Intel

## License

MIT

# Changelog

## [Unreleased]

---

## [v1.1.5] - 2026-05-03

### 修复
- 修复 `Fn + 普通按键` 仍可能启动听写的问题；现在只有纯 `Fn` 和纯 `Option + Fn` 会启动 VoiceInput，其他 Fn 组合键不会启动听写。

---

## [v1.1.4] - 2026-05-03

### 修复
- 修复 `VoiceInput.dmg` 的 Finder 默认布局问题：放大图标大小，并将 `VoiceInput.app` 固定在左侧、`Applications` 固定在右侧，形成更自然的拖拽安装方向。

---

## [v1.1.3] - 2026-05-03

### 修复
- 修复 `Fn + Control`、`Fn + Command`、`Fn + Shift` 等组合键会误触发 VoiceInput 的问题；现在只有纯 `Fn` 和纯 `Option + Fn` 会启动听写。

---

## [v1.1.2] - 2026-05-03

### 文档
- 明确 GitHub DMG 仍是 unsigned / not notarized build，并补充 Gatekeeper 首次打开说明：右键 `VoiceInput.app` 选择 **Open**，或在 **System Settings -> Privacy & Security** 中允许打开。

---

## [v1.1.1] - 2026-05-03

### 修复
- 修复 `VoiceInput.dmg` 缺少 `/Applications` 快捷方式的问题，使安装包支持常见的拖拽安装体验。

---

## [v1.1.0] - 2026-05-03

### 新增
- 新增 `Readiness...` 面板，被动展示 Accessibility、Microphone、Speech Recognition、LLM configured、Dictionary loaded 状态，并提供对应设置入口。
- `Last Result...` 升级为 `Recent Results...`，当前会话内保留最近 10 条听写结果，支持 raw / filtered / refined / final 回看、复制、重试插入和快速保存字典规则。
- Dictionary 窗口新增 `Test Phrase` workbench，保存前可实时预览字典过滤后的输出和命中的规则。
- LLM Settings 新增 `Not configured` / `Ready` / `Test failed` 状态文案，并显示当前 base URL、model、mode，不展示 API key。

### 修复
- 修复从较旧 Recent Result 执行 `Retry Insert` 时错误更新最新记录插入状态的问题。

### 文档
- README 英 / 中 / 日 / 韩同步更新 v1.1 功能说明、菜单入口和 release policy 示例。

---

## [v1.0.3] - 2026-05-03

### 变更
- GitHub Actions 升级到 Node 24 兼容版本：`actions/checkout@v6` 和 `softprops/action-gh-release@v3`，移除 Node.js 20 deprecation warning。
- 菜单栏新增 `Last Result...`，可查看最近一次 raw / filtered / refined / final 结果，并支持复制、重试插入和快速保存字典规则。
- 新增多模式快捷入口：`Fn` 使用当前默认 LLM 模式，`Option + Fn` 可对本次听写临时使用 Prompt Builder；Last Result 会显示本次 LLM 模式。
- 菜单栏新增 `Permissions...` 诊断入口，轻量查看辅助功能、麦克风、语音识别权限状态，便于定位 `Fn` 无响应或插入失败。

---

## [v1.0.2] - 2026-05-03

### 新增
- LLM Refinement 新增 `Prompt Builder` 模式，可把口语整理成适合 AI 助手的结构化提示词，默认仍保持精准听写。
- 文本插入失败时保留本次输出到剪贴板，避免语音内容丢失。
- 新增英 / 中 / 日 / 韩四套 README，面向公开仓库使用。

### 变更
- 公开发布前清理内置字典、README 和示例中的非通用专有样例。
- `make version-bump` 现在要求 `CHANGELOG.md` 中存在对应版本条目，确保 patch/minor 版本也生成明确 GitHub Release notes。

---

## [v1.0.1] - 2026-04-03

### 修复
- CI: release job 补充 `mkdir -p MacOS` 防止 GitHub Actions 环境缺失目录导致构建失败

### 变更
- GitHub Actions 工作流升级为统一 CI/CD（单 YAML）
  - `push main` → auto-doc（README 日期自动更新，`[skip ci]` 截断无限循环）
  - `push v* tag` → macOS 编译 + DMG 打包 + GitHub Release
- Makefile 新增 `version-bump` 目标，一键更新版本号+打 tag

---

## [v1.0.0] - 2026-04-03

### 新增
- **字典层纠错管道**：新增 `DictionaryFilter`，在 LLM 之前执行确定性专有名词替换，内置常见技术词条（OpenClaw、TypeScript、Python、Docker、Kubernetes 等）
- **用户自定义词典**：菜单栏 Dictionary... 窗口，支持 `错误词 → 正确词` 格式，保存即生效，词典持久化至 `~/Library/Application Support/VoiceInput/dictionary.json`

### 优化
- **LLM System Prompt 减脂**：从 ~800 tokens 降至 ~80 tokens，专有名词纠错上移至字典层，LLM 只处理语法/上下文粘合
- **纠错管道架构**：`Apple Speech → DictionaryFilter（确定性）→ LLMRefiner（概率性）→ 输出`

### 修复
- LLM 润色描述错误（"配森→Python"现由字典层处理，不再依赖 LLM）

---

## [初始版本]

- 按住 Fn 说话，松开后语音转文字注入光标位置
- 原生 Apple Speech 识别，支持中英文多语言切换
- 可选 LLM 润色（OpenAI 兼容 API）
- 300ms 防误触阈值

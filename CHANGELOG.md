# Changelog

## [Unreleased]

### 变更
- GitHub Actions 升级到 Node 24 兼容版本：`actions/checkout@v6` 和 `softprops/action-gh-release@v3`，移除 Node.js 20 deprecation warning。

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

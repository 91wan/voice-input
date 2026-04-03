# Changelog

## [v1.0.1] - 2026-04-03

### 修复
- CI: release job 补充 `mkdir -p MacOS` 防止 GitHub Actions 环境缺失目录导致构建失败

### 变更
- GitHub Actions 工作流升级为统一 CI/CD（单 YAML），对齐 project 全局标准
  - `push main` → auto-doc（README 日期自动更新，`[skip ci]` 截断无限循环）
  - `push v* tag` → macOS 编译 + DMG 打包 + GitHub Release
- Makefile 新增 `version-bump` 目标，一键更新版本号+打 tag

---

## [v1.0.0] - 2026-04-03

### 新增
- **字典层纠错管道**：新增 `DictionaryFilter`，在 LLM 之前执行确定性专有名词替换，内置 13 条词条（OpenClaw、ExampleApp、Python、Docker、Kubernetes 等）
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

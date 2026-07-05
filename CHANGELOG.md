# Changelog

## [Unreleased]

### 变更
- PR CI gate：pull requests targeting `main` now run `make ci` before merge, while release publishing keeps write permission scoped to the tag release job.
- Dictation lifecycle：new `Fn` presses are rejected while the previous dictation is resolving or injecting, preventing silent result loss.
- Busy overlay lifecycle：busy `Fn` rejections no longer overwrite or dismiss an active dictation overlay, and transient hints only dismiss their own presentation.
- Settings Test lifecycle：repeated Test runs and window close/save now cancel only the active Settings test request without touching dictation refinement.
- Settings Test early returns：new invalid or unconfigured Test attempts now cancel any previous in-flight Settings test before showing validation or API key status.
- LLM Settings Test：Test now clearly uses unsaved one-shot settings, while Save remains the only persistence action for API key, base URL, and model.
- LLM Settings Test freshness：editing API Base URL / API Key / model after a test now clears stale test results, so success/failure only applies to the fields that were actually tested.
- Clipboard injection ownership：consecutive fast dictations restore the user's original clipboard instead of a previous generated text.
- Release validation：local CI, `make build`, and DMG verification now require a non-empty bundled app icon, and tag releases fail when matching changelog notes are missing.
- Documentation：README build-from-source instructions now document `make ci` as the local CI gate and `swift test --parallel` as unit-test-only.
- Release gate：`make release-check` now packages and verifies the DMG locally, while GitHub release publishing reuses the Makefile artifact target.
- Release gate hardening：`release-artifact` now packages and verifies sequentially under `make -j`, quotes DMG paths, and `make ci` checks release scripts are executable.
- Release bump hardening：`make version-bump` now reuses the release-notes extractor, includes `CHANGELOG.md` in the bump commit, rejects existing tags, and runs the local release gate before tagging.
- Release tree invariant：`make version-bump` now requires a clean source/test/script/workflow tree, allows only pre-existing `CHANGELOG.md` release-note edits, checks local and remote tag collisions, and verifies only release metadata is dirty before tagging.
- Release branch invariant：`make version-bump` now requires the local release branch to match the configured remote branch before metadata mutation or tag creation.
- DMG install polish：Finder install window now uses larger app / Applications icons and adjusted positions so drag-to-install is more obvious.
- DMG layout verification：release gate now reads the mounted DMG Finder layout and fails if icon size, window bounds, or app / Applications positions regress.
- Retry Insert lifecycle：Recent Results retry insertion is now blocked while dictation is holding, recording, resolving, or injecting.
- Retry Insert final gate：retry insertion now rechecks dictation availability immediately before delayed insertion and again inside the AppDelegate injection boundary.
- Pasteboard ownership：injection restore ownership is now tied to pasteboard identity as well as change count.
- Pasteboard failure contract：paste-command failures intentionally leave generated text on the clipboard, while the next successful injection restores to the correct original or user-updated baseline.
- Release notes extraction：tag release notes now come from a testable fail-closed script.
- Release notes cleanup：extracted public release notes now drop trailing Markdown separator lines before publishing.
- Manual QA：added a lightweight manual QA log template for real app, Fn, and permission checks without claiming automated coverage.

### 工程
- Pasteboard test isolation：pasteboard-related XCTest fixtures now use explicit unique pasteboard names to avoid `swift test --parallel` runner-specific collisions.

---

## [v1.6.0] - 2026-05-03

### 变更
- Unsigned Distribution Hardening：发布流程在创建 GitHub Release 前会挂载并验证 DMG。
- 自动验证覆盖 `VoiceInput.app`、`Applications -> /Applications`、`.DS_Store`、版本号、ad-hoc codesign，以及当前 unsigned / not notarized 构建预期的 `spctl rejected` 结果。
- Release QA checklist 区分自动 release gates 与需要人工执行的权限 / Fn QA，避免把不可自动验证的 macOS 权限链路伪装成 CI 覆盖。

---

## [v1.5.0] - 2026-05-03

### 新增
- Dictation Workflow Clarity：菜单栏、Readiness 和 Recent Results 现在都会更明确展示当前听写模式。
- `Fn` 标记为当前默认模式，`Option + Fn` 标记为一次性 Prompt Builder，不改变默认设置。
- LLM disabled / no key 时，ordinary Fn still uses Apple Speech + DictionaryFilter，不再让普通听写产生额外 LLM 错误噪音。
- Recent Results 会保留本次请求的模式 metadata，即使本次没有实际使用 LLM。

---

## [v1.4.0] - 2026-05-03

### 变更
- First-Run / Permission Repair：权限恢复文案统一为 `Failed / Next / Reopen` 结构，覆盖 Readiness、权限 alert 和插入失败提示。
- Readiness 中缺失权限不再只显示 `Missing`，而是直接展示失败点、下一步动作和是否需要重开 VoiceInput。
- 麦克风、语音识别、Accessibility / Input Monitoring stale permission 场景都补充自动化覆盖。

---

## [v1.3.0] - 2026-05-03

### 新增
- Dictionary import/export：Dictionary 窗口新增 `Import...` 和 `Export...`，支持把可编辑规则导入为文本并导出为便携文本文件。
- 导入复用现有规则解析策略；格式错误会阻止导入，重复/覆盖规则会提示 warning。
- 导入后只更新编辑器内容，不会自动覆盖已保存词典，用户检查后点击 `Save` 才会写入 `dictionary.json`。

---

## [v1.2.0] - 2026-05-03

### 文档
- 补齐首次安装完整路径：下载 DMG、左侧拖拽 `VoiceInput.app` 到右侧 `Applications`、再从 `/Applications/VoiceInput.app` 启动。
- 补齐更新后权限失效恢复路径：覆盖安装后退出重开，必要时移除旧 Accessibility / Input Monitoring 条目并重新添加当前 `/Applications/VoiceInput.app`。
- 将 `docs/release-qa-checklist.md` 明确为 stable Release QA checklist，覆盖安装、首次启动、权限、`Fn` / `Option + Fn`、Recent Results、Dictionary 和 LLM disabled/enabled 路径。

---

## [v1.1.7] - 2026-05-03

### 修复
- Readiness 增加更明确的 `Fix Permission` 恢复入口，并在权限已开启但监听器仍未激活时显示 `Reopen App` 状态。
- 权限错误提示统一复用恢复指引，明确说明当前失败点、下一步动作，以及是否需要退出重开 VoiceInput。

### 文档
- 新增 `docs/release-qa-checklist.md`，固化 v1.2.0 前的安装、权限、Fn 快捷键、Recent Results、Dictionary 和 LLM 手动 QA 覆盖范围。

---

## [v1.1.6] - 2026-05-03

### 修复
- 修复 Accessibility 已开启但仍失败时提示过窄的问题：Readiness 现在会展示 `Input Monitoring` 状态，并提供对应系统设置入口。
- 粘贴失败提示现在会说明 unsigned/ad-hoc 构建更新后可能需要退出重开，或移除旧权限项后重新添加 `/Applications/VoiceInput.app`。

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

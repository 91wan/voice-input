# VoiceInput

### `Fn` を押して話し、離すと入力

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

VoiceInput は macOS のメニューバー常駐型音声入力アプリです。`Fn` キーを押して話し、キーを離すと認識されたテキストが現在のカーソル位置に挿入されます。自然言語と技術用語が混ざる入力に向いています。

基本パイプライン:

```text
Audio -> Apple Speech -> DictionaryFilter -> optional LLMRefiner -> TextInjector
```

## VoiceInput を選ぶ理由

- **押して話すだけ**：300 ms の誤操作防止により、日常的に素早く使えます。
- **Apple Speech を利用**：必須の外部音声クラウドはありません。
- **決定的な辞書補正**：よくある ASR の誤認識を LLM の前に高速に修正します。
- **任意の LLM 補正**：OpenAI 互換 API に対応し、文章整理や Prompt Builder に利用できます。
- **挿入失敗時の保護**：テキスト挿入に失敗しても、生成結果はクリップボードに残ります。
- **メニューバー中心**：重いウィンドウを開かずに主要操作を完結できます。

## 機能

### 辞書補正

内蔵辞書は一般的な技術用語を補正します:

| 認識結果 | 出力 |
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

**Menu Bar -> Dictionary...** からユーザー辞書を編集できます:

```text
# 1 行につき 1 ルール
type script -> TypeScript
open claw -> OpenClaw
my project -> MyProject
```

ユーザー辞書の保存場所:

```text
~/Library/Application Support/VoiceInput/dictionary.json
```

### LLM 補正

**Menu Bar -> LLM Refinement -> Settings** で OpenAI 互換 API を設定します。

- API キーは macOS Keychain に保存されます。
- API Base URL とモデル名が空の場合はデフォルト値に戻ります。
- API キーなしで LLM を有効化すると、設定画面を開いて入力を促します。
- **Precise Dictation** は発話に近い形を維持します。
- **Prompt Builder** は音声メモを ChatGPT、Claude、Cursor などに渡しやすい構造化プロンプトへ整えます。

## クイックスタート

1. [Releases](../../releases/latest) から最新の `VoiceInput.dmg` をダウンロードします。
2. `VoiceInput.app` を `/Applications` にドラッグします。
3. アプリを起動します。
4. macOS の権限を許可します:
   - マイク
   - 音声認識
   - アクセシビリティ
5. 任意の入力欄にカーソルを置き、`Fn` を押して話し、離します。

> 初回起動時に macOS がブロックする場合は、**システム設定 -> プライバシーとセキュリティ** で許可するか、アプリを右クリックして **開く** を選択してください。

## メニューバー操作

- **Language**：認識言語を切り替えます。
- **Dictionary...**：決定的な補正ルールを編集します。
- **LLM Refinement**：LLM 補正の有効化、設定、モード切替を行います。
- **Quit**：VoiceInput を終了します。

## 対応言語

メニューバーから認識言語を切り替えられます:

- 簡体字中国語
- 繁体字中国語
- 英語
- 日本語
- 韓国語

## ソースからビルド

必要環境:

- macOS 14 Sonoma 以降
- Xcode Command Line Tools

アプリをビルド:

```bash
make build
```

ローカル実行:

```bash
make run
```

テスト:

```bash
swift test --parallel
```

## リリース方針

- リリース前に `CHANGELOG.md` に対応するバージョン項目を追加します。例: `## [v1.0.2] - YYYY-MM-DD`
- `make version-bump VERSION=v1.0.2` でバージョン情報を更新し、tag を作成します。
- `v*` tag を push すると、CI が macOS アプリをビルドし、`VoiceInput.dmg` を作成し、`CHANGELOG.md` から GitHub Release notes を生成します。
- メジャーリリースでは README と製品説明を更新します。
- パッチ / マイナーリリースでも明確な GitHub Release notes を残します。

## プロジェクト構成

```text
Sources/VoiceInput/
  AppDelegate.swift          メニューバーのライフサイクルと主制御
  KeyMonitor.swift           Fn キー監視
  SpeechEngine.swift         Apple Speech の録音と認識
  DictionaryFilter.swift     決定的な辞書補正レイヤー
  LLMRefiner.swift           任意の OpenAI 互換補正
  TextInjector.swift         カーソル挿入とクリップボード保護
  DictionaryWindow.swift     ユーザー辞書エディタ
  SettingsWindow.swift       LLM 設定画面
```

## FAQ

### LLM は必須ですか？

いいえ。Apple Speech と DictionaryFilter は LLM なしで動作します。

### API キーはどこに保存されますか？

macOS Keychain に保存され、`UserDefaults` には平文で保存されません。

### テキスト挿入に失敗した場合は？

生成されたテキストはクリップボードに残るため、手動で貼り付けできます。

### テレメトリはありますか？

テレメトリサービスは含まれていません。

## License

MIT

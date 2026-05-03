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
- **モードショートカット**：`Fn` は選択中の LLM モードを使い、`Option + Fn` は今回だけ Prompt Builder を使います。
- **Readiness パネル**：アクセシビリティ、マイク、音声認識、LLM 設定、辞書読み込み状態を受動的に確認できます。
- **挿入失敗時の保護**：テキスト挿入に失敗しても、生成結果はクリップボードに残ります。
- **Recent Results**：現在のセッション内の最新 10 件について、raw / 辞書補正後 / LLM 補正後 / 最終テキストを確認し、コピー、再挿入、辞書ルール保存ができます。
- **Dictionary Workbench**：保存前にテスト文を入力し、補正結果と一致した辞書ルールを確認できます。
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

Dictionary ウィンドウには **Test Phrase** 入力があります。サンプル文を入力すると、辞書適用後の出力と一致したルールを即座に確認できます。ルール形式が不正な場合は保存前に表示されます。

### LLM 補正

**Menu Bar -> LLM Refinement -> Settings** で OpenAI 互換 API を設定します。

- API キーは macOS Keychain に保存されます。
- API Base URL とモデル名が空の場合はデフォルト値に戻ります。
- 設定画面は `Not configured`、`Ready`、`Test failed` の状態を表示します。
- API キー未設定でも、通常の `Fn` 入力は Apple Speech と DictionaryFilter で動作し、余計な LLM エラーを出しません。
- **Precise Dictation** は発話に近い形を維持します。
- **Prompt Builder** は音声メモを ChatGPT、Claude、Cursor などに渡しやすい構造化プロンプトへ整えます。
- `Fn` は選択中の既定モードを使います。`Option + Fn` は既定設定を変えずに今回だけ Prompt Builder を使います。

## クイックスタート

1. [Releases](../../releases/latest) から最新の `VoiceInput.dmg` をダウンロードします。
2. `VoiceInput.app` を `/Applications` にドラッグします。
3. アプリを起動します。
4. macOS の権限を許可します:
   - マイク
   - 音声認識
   - アクセシビリティ
5. 任意の入力欄にカーソルを置き、`Fn` を押して話し、離します。今回だけ Prompt Builder を使う場合は `Option + Fn` を使います。

> 初回起動時に macOS がブロックする場合は、**システム設定 -> プライバシーとセキュリティ** で許可するか、アプリを右クリックして **開く** を選択してください。

## メニューバー操作

- **Language**：認識言語を切り替えます。
- **Readiness...**：新しい権限要求を行わずに、アクセシビリティ、マイク、音声認識、LLM、辞書の状態を確認します。
- **Dictionary...**：決定的な補正ルールを編集します。
- **Recent Results...**：現在のセッション内の最新 10 件を確認し、素早く辞書補正を追加できます。
- **LLM Refinement**：LLM 補正の有効化、設定、既定モード切替、`Fn` / `Option + Fn` ショートカット確認を行います。
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

- リリース前に `CHANGELOG.md` に対応するバージョン項目を追加します。例: `## [v1.1.0] - YYYY-MM-DD`
- `make version-bump VERSION=v1.1.0` でバージョン情報を更新し、tag を作成します。
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
  DictionaryWorkbench.swift  辞書テスト文の評価
  LLMRefiner.swift           任意の OpenAI 互換補正
  TextInjector.swift         カーソル挿入とクリップボード保護
  DictionaryWindow.swift     ユーザー辞書エディタ
  LastResultWindow.swift     セッション内 Recent Results 表示
  ReadinessWindow.swift      受動的な起動 / 準備状態チェック
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

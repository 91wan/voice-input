# VoiceInput

### `Fn`을 누르고 말한 뒤, 놓으면 텍스트가 입력됩니다

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [한국어](README.ko.md)

VoiceInput은 macOS 메뉴 막대에 상주하는 음성 입력 앱입니다. `Fn` 키를 누른 채 말하고 키를 놓으면 인식된 텍스트가 현재 커서 위치에 삽입됩니다. 자연어와 기술 용어를 함께 사용하는 입력 흐름에 맞춰 설계되었습니다.

기본 파이프라인:

```text
Audio -> Apple Speech -> DictionaryFilter -> optional LLMRefiner -> TextInjector
```

## 왜 VoiceInput인가?

- **누르고 말하기**: 300 ms 오입력 방지 로직으로 일상적인 빠른 입력에 적합합니다.
- **Apple Speech 기반**: 필수 외부 음성 클라우드 서비스가 필요하지 않습니다.
- **결정적 사전 보정**: 자주 발생하는 ASR 오류를 LLM 전에 빠르고 예측 가능하게 수정합니다.
- **선택적 LLM 보정**: OpenAI 호환 API로 문장 정리 또는 Prompt Builder 모드를 사용할 수 있습니다.
- **모드 단축키**: `Fn`은 선택된 LLM 모드를 사용하고, `Option + Fn`은 이번 입력에만 Prompt Builder를 사용합니다.
- **Readiness 패널**: 손쉬운 사용, 마이크, 음성 인식, LLM 설정, 사전 로드 상태를 수동으로 권한 요청하지 않고 확인합니다.
- **입력 실패 보호**: 커서 삽입이 실패해도 생성된 텍스트는 클립보드에 남습니다.
- **Recent Results**: 현재 세션의 최근 10개 결과에서 raw / 사전 보정 / LLM 보정 / 최종 텍스트를 확인하고, 복사, 재삽입, 빠른 사전 규칙 저장을 할 수 있습니다.
- **Dictionary Workbench**: 저장 전에 테스트 문장을 입력해 보정 결과와 매칭된 사전 규칙을 확인할 수 있습니다.
- **메뉴 막대 중심**: 무거운 창을 열지 않고 핵심 기능을 사용할 수 있습니다.

## 기능

### 사전 보정

내장 사전은 일반적인 기술 용어를 보정합니다:

| 인식 결과 | 출력 |
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

**Menu Bar -> Dictionary...** 에서 사용자 규칙을 편집할 수 있습니다:

```text
# 한 줄에 하나의 규칙
type script -> TypeScript
open claw -> OpenClaw
my project -> MyProject
```

사용자 사전 저장 위치:

```text
~/Library/Application Support/VoiceInput/dictionary.json
```

Dictionary 창에는 **Test Phrase** 입력이 포함됩니다. 예시 문장을 입력하면 사전 적용 후 출력과 매칭된 규칙을 바로 확인할 수 있으며, 잘못된 규칙 형식은 저장 전에 표시됩니다.

### LLM 보정

**Menu Bar -> LLM Refinement -> Settings** 에서 OpenAI 호환 API를 설정합니다.

- API 키는 macOS Keychain에 저장됩니다.
- API Base URL과 모델명이 비어 있으면 기본값을 사용합니다.
- 설정 창은 `Not configured`, `Ready`, `Test failed` 상태를 표시합니다.
- API 키가 없어도 일반 `Fn` 입력은 Apple Speech와 DictionaryFilter로 계속 동작하며, 불필요한 LLM 실패 소음을 만들지 않습니다.
- **Precise Dictation** 은 말한 내용에 가까운 결과를 유지합니다.
- **Prompt Builder** 는 음성 메모를 ChatGPT, Claude, Cursor 등에 넣기 좋은 구조화된 프롬프트로 정리합니다.
- `Fn`은 선택된 기본 모드를 사용합니다. `Option + Fn`은 기본 설정을 바꾸지 않고 이번 입력에만 Prompt Builder를 사용합니다.

## 빠른 시작

1. [Releases](../../releases/latest) 에서 최신 `VoiceInput.dmg`를 다운로드합니다.
2. `VoiceInput.app`을 `/Applications`로 드래그합니다.
3. 앱을 실행합니다.
4. macOS 권한을 허용합니다:
   - 마이크
   - 음성 인식
   - 손쉬운 사용
5. 입력창에 커서를 둔 뒤 `Fn`을 누르고 말한 다음 키를 놓습니다. 이번 입력만 Prompt Builder로 처리하려면 `Option + Fn`을 사용합니다.

> 첫 실행 시 macOS가 앱을 차단하면 **시스템 설정 -> 개인정보 보호 및 보안** 에서 허용하거나, 앱을 우클릭한 뒤 **열기** 를 선택하세요.

## 메뉴 막대 제어

- **Language**: 인식 언어를 전환합니다.
- **Readiness...**: 새 권한 요청 없이 손쉬운 사용, 마이크, 음성 인식, LLM, 사전 상태를 확인합니다.
- **Dictionary...**: 결정적 보정 규칙을 편집합니다.
- **Recent Results...**: 현재 세션의 최근 10개 결과를 확인하고 빠르게 사전 보정을 추가합니다.
- **LLM Refinement**: LLM 보정 활성화, 설정, 기본 모드 전환, `Fn` / `Option + Fn` 단축키 확인을 관리합니다.
- **Quit**: VoiceInput을 종료합니다.

## 지원 언어

메뉴 막대에서 인식 언어를 전환할 수 있습니다:

- 중국어 간체
- 중국어 번체
- 영어
- 일본어
- 한국어

## 소스에서 빌드

요구 사항:

- macOS 14 Sonoma 이상
- Xcode Command Line Tools

앱 빌드:

```bash
make build
```

로컬 실행:

```bash
make run
```

테스트:

```bash
swift test --parallel
```

## 릴리스 정책

- 릴리스 전에 `CHANGELOG.md`에 해당 버전 항목을 추가합니다. 예: `## [v1.1.0] - YYYY-MM-DD`
- `make version-bump VERSION=v1.1.0` 로 버전 메타데이터를 업데이트하고 tag를 생성합니다.
- `v*` tag를 push하면 CI가 macOS 앱을 빌드하고 `VoiceInput.dmg`를 패키징하며, `CHANGELOG.md`에서 GitHub Release notes를 생성합니다.
- 메이저 릴리스는 README와 제품 포지셔닝을 함께 업데이트해야 합니다.
- 패치 / 마이너 릴리스도 명확한 GitHub Release notes를 남겨야 합니다.

## 프로젝트 구조

```text
Sources/VoiceInput/
  AppDelegate.swift          메뉴 막대 수명 주기와 주요 제어
  KeyMonitor.swift           Fn 키 감지
  SpeechEngine.swift         Apple Speech 녹음과 인식
  DictionaryFilter.swift     결정적 사전 보정 레이어
  DictionaryWorkbench.swift  사전 테스트 문장 평가
  LLMRefiner.swift           선택적 OpenAI 호환 보정
  TextInjector.swift         커서 삽입과 클립보드 보호
  DictionaryWindow.swift     사용자 사전 편집기
  LastResultWindow.swift     현재 세션 Recent Results 확인
  ReadinessWindow.swift      수동 권한 요청 없는 준비 상태 확인
  SettingsWindow.swift       LLM 설정 창
```

## FAQ

### LLM이 필수인가요?

아닙니다. Apple Speech와 DictionaryFilter는 LLM 없이 동작합니다.

### API 키는 어디에 저장되나요?

macOS Keychain에 저장되며 `UserDefaults`에 평문으로 저장되지 않습니다.

### 텍스트 삽입이 실패하면 어떻게 되나요?

생성된 텍스트가 클립보드에 남아 있어 직접 붙여 넣을 수 있습니다.

### 텔레메트리가 있나요?

텔레메트리 서비스는 포함되어 있지 않습니다.

## License

MIT

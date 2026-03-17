# CodeSolve

> 코딩 테스트 화면을 캡처해 Claude AI가 자동으로 풀어주는 macOS 메뉴바 앱

---

## 소개

CodeSolve는 Apple Silicon MacBook에서 동작하는 macOS 메뉴바 앱입니다.
백준, LeetCode 등 코딩 플랫폼의 문제를 화면 캡처로 읽고, OCR로 텍스트를 추출한 뒤, Claude AI가 풀이 코드를 생성합니다.
생성된 코드는 클립보드에 복사되거나, 에디터에 자동으로 타이핑됩니다.

**완벽한 Hide 모드**로 Dock과 Mission Control에 흔적을 남기지 않습니다. VDI(가상 데스크탑) 환경 지원은 향후 업데이트 예정입니다.

---

## 주요 기능

### 핵심 파이프라인
- **화면 캡처** — ScreenCaptureKit으로 특정 창을 선택해 캡처
- **OCR 텍스트 인식** — Apple Vision Framework로 한국어/영어 문제 텍스트 추출
- **AI 풀이 생성** — Claude Opus 4.6 API로 최적 풀이 코드를 실시간 스트리밍 생성
- **자동 입력** — CGEvent 기반 자동 타이핑 또는 클립보드 복사

### 지원 플랫폼
| 플랫폼 | 설명 |
|--------|------|
| 백준 | 표준 입출력(stdin/stdout) 방식 |
| LeetCode | 클래스/함수 시그니처 방식 |
| VDI | 향후 업데이트 예정 |

### 지원 언어
- Python, Java, C++

### Hide 모드
- 메뉴바 아이콘, Dock, Mission Control, Cmd+Tab 목록에서 완전히 숨김
- 전역 단축키(기본: `Cmd+Shift+Option+H`)로 진입/탈출
- Hide 모드에서 자동 스캔: 마지막으로 선택한 창을 자동으로 다시 스캔

### 기타
- 풀이 히스토리 저장 및 조회
- 전역 단축키 커스터마이징
- 절전 해제 후 단축키 자동 재등록
- API 키 Keychain 보안 저장

---

## 기본 단축키

| 단축키 | 동작 |
|--------|------|
| `Cmd+Shift+S` | 캡처 시작 (창 선택) |
| `Cmd+Shift+C` | 마지막 결과 클립보드 복사 |
| `Cmd+Shift+T` | 마지막 결과 자동 타이핑 |
| `Cmd+Shift+Option+H` | Hide 모드 진입/탈출 |

단축키는 설정 메뉴에서 자유롭게 변경할 수 있습니다.

---

## 요구 사항

- macOS 13.0 이상 (Apple Silicon 권장)
- [Anthropic API 키](https://console.anthropic.com)
- **화면 녹화 권한** — 시스템 설정 > 개인 정보 및 보안 > 화면 녹화
- **손쉬운 사용 권한** — 자동 타이핑 기능 사용 시 필요

---

## 설치 및 설정

1. Xcode에서 프로젝트를 열고 빌드합니다.
2. 앱을 처음 실행하면 화면 녹화 권한 요청이 표시됩니다.
3. 메뉴바의 `</>` 아이콘을 클릭하고 **설정** 을 엽니다.
4. Claude API 키를 입력합니다.
5. 풀이 언어를 선택합니다.
6. `Cmd+Shift+S`로 캡처를 시작합니다.

---

## 아키텍처

```
main.swift
└── AppDelegate
    └── MenuBarController          # 메뉴바 및 전체 파이프라인 조율
        ├── CaptureManager         # ScreenCaptureKit 화면 캡처
        ├── OCRProcessor           # Apple Vision OCR
        ├── ClaudeAPIClient        # Claude API SSE 스트리밍
        ├── InputController        # CGEvent 자동 타이핑
        ├── HideModeManager        # Hide 모드 상태 관리
        ├── AutoScanEngine         # Hide 모드 자동 스캔
        ├── HistoryManager         # UserDefaults 히스토리
        └── UI
            ├── FloatingResultPanel    # VDI용 플로팅 결과창
            ├── WindowPickerPanel      # 창 선택 UI
            ├── SettingsPanel          # API 키 / 언어 설정
            ├── HistoryPanel           # 히스토리 조회
            └── ShortcutSettingsPanel  # 단축키 설정
```

---

## 라이선스

개인 사용 목적으로 제작된 프로젝트입니다.

---

---

# CodeSolve

> A macOS menu bar app that captures your coding test screen and automatically solves it using Claude AI

---

## Overview

CodeSolve is a macOS menu bar app optimized for Apple Silicon MacBooks.
It captures a coding problem from platforms like Baekjoon or LeetCode, extracts the text via OCR, and generates a solution using Claude AI.
The result is either copied to the clipboard or auto-typed directly into your editor.

The **Perfect Hide Mode** leaves no trace in Dock or Mission Control. VDI (Virtual Desktop Infrastructure) support is planned for a future update.

---

## Features

### Core Pipeline
- **Screen Capture** — Select and capture any window using ScreenCaptureKit
- **OCR Text Recognition** — Extract Korean/English problem text via Apple Vision Framework
- **AI Solution Generation** — Stream optimal solution code in real time using Claude Opus 4.6
- **Auto Input** — Auto-type via CGEvent or copy to clipboard

### Supported Platforms
| Platform | Mode |
|----------|------|
| Baekjoon | stdin/stdout style |
| LeetCode | Class/function signature style |
| VDI | Coming in a future update |

### Supported Languages
- Python, Java, C++

### Hide Mode
- Completely hidden from menu bar, Dock, Mission Control, and Cmd+Tab
- Enter/exit with a global shortcut (default: `Cmd+Shift+Option+H`)
- Auto-scan mode: automatically re-scans the last selected window in Hide Mode

### Other
- Solution history with search
- Customizable global shortcuts
- Shortcut re-registration after sleep/wake
- API key stored securely in Keychain

---

## Default Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Shift+S` | Start capture (window picker) |
| `Cmd+Shift+C` | Copy last result to clipboard |
| `Cmd+Shift+T` | Auto-type last result |
| `Cmd+Shift+Option+H` | Toggle Hide Mode |

All shortcuts can be customized in the settings menu.

---

## Requirements

- macOS 13.0 or later (Apple Silicon recommended)
- [Anthropic API Key](https://console.anthropic.com)
- **Screen Recording permission** — System Settings > Privacy & Security > Screen Recording
- **Accessibility permission** — Required for auto-typing

---

## Installation & Setup

1. Open the project in Xcode and build it.
2. On first launch, grant Screen Recording permission when prompted.
3. Click the `</>` icon in the menu bar and open **Settings**.
4. Enter your Claude API key.
5. Select your preferred solution language.
6. Press `Cmd+Shift+S` to start.

---

## Architecture

```
main.swift
└── AppDelegate
    └── MenuBarController          # Menu bar & pipeline orchestration
        ├── CaptureManager         # ScreenCaptureKit screen capture
        ├── OCRProcessor           # Apple Vision OCR
        ├── ClaudeAPIClient        # Claude API SSE streaming
        ├── InputController        # CGEvent auto-typing
        ├── HideModeManager        # Hide mode state management
        ├── AutoScanEngine         # Auto-scan in Hide mode
        ├── HistoryManager         # UserDefaults-based history
        └── UI
            ├── FloatingResultPanel    # Floating result window (VDI)
            ├── WindowPickerPanel      # Window selection UI
            ├── SettingsPanel          # API key / language settings
            ├── HistoryPanel           # History viewer
            └── ShortcutSettingsPanel  # Shortcut customization
```

---

## License

Built for personal use.

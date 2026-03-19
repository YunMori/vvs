# CodeSolve

> 코딩 테스트 화면을 캡처해 Claude AI가 자동으로 풀어주는 macOS 메뉴바 앱

---

## 소개

CodeSolve는 Apple Silicon MacBook에서 동작하는 macOS 메뉴바 앱입니다.
백준, LeetCode 등 코딩 플랫폼의 문제 화면을 캡처하면, 이미지를 **Claude Vision API**에 직접 전송하여 풀이 코드를 실시간 스트리밍으로 생성합니다.
생성된 코드는 클립보드에 복사되거나, 에디터에 자동으로 타이핑됩니다.

**완벽한 Hide 모드**로 Dock과 Mission Control에 흔적을 남기지 않습니다.
**다중 이미지 캡처**로 문제가 여러 화면에 걸쳐 있어도 최대 5장까지 누적하여 한 번에 풀이합니다.

---

## 주요 기능

### 핵심 파이프라인
- **화면 캡처** — ScreenCaptureKit으로 특정 창을 선택해 캡처
- **Claude Vision API** — 이미지를 직접 Claude에 전송하여 OCR 없이 실시간 스트리밍 풀이 생성
- **다중 이미지 지원** — 최대 5장의 이미지를 누적 후 한 번에 전송 (문제가 여러 화면에 걸친 경우)
- **자동 플랫폼 감지** — 창 제목·URL로 백준/LeetCode/VDI 환경 자동 인식
- **자동 입력** — CGEvent 기반 자동 타이핑 또는 클립보드 복사

### 지원 플랫폼
| 플랫폼 | 설명 |
|--------|------|
| 백준 | 표준 입출력(stdin/stdout) 방식 |
| LeetCode | 클래스/함수 시그니처 방식 |
| VDI | 환경 감지 지원 (VMware, Citrix, Microsoft RDP 등) |

### 지원 언어
- Python, Java, C++

### Hide 모드
- 메뉴바 아이콘, Dock, Mission Control, Cmd+Tab 목록에서 완전히 숨김
- 전역 단축키(기본: `Cmd+Shift+Option+H`)로 진입/탈출
- Hide 모드에서 마지막으로 선택한 창을 자동 스캔

### 다중 이미지 캡처 (Multi-Capture)
- `Cmd+Shift+Option+S`로 이미지를 1장씩 누적 (최대 5장)
- 누적 중 **CaptureActionBar**가 표시되어 추가 캡처 / 풀이 시작 / 취소 선택
- 단일 이미지는 `generateSolutionFromImage()`, 복수 이미지는 `generateSolutionFromImages()` 분기 처리

### 자동 타이핑 (Human-like Typing)
- **자연스러운 타이핑** — CHI 2018 연구 기반 바이그램 IKI 테이블 + 가우시안 노이즈로 사람처럼 속도 변화
- **타이핑 프로필** — Slow / Average / Fast 세 가지 속도 프로필 지원
- **오타 시뮬레이션** — 약 1.2% 확률로 오타 후 자동 정정 (QWERTY 인접 키 기반)
- **IDE 자동 들여쓰기 모드** — VSCode, Xcode 등에서 `\n` 입력 시 에디터 자동 들여쓰기와의 충돌 방지

### 기타
- 풀이 히스토리 저장 및 조회
- 전역 단축키 커스터마이징
- 절전 해제 후 단축키 자동 재등록
- API 키 Keychain 보안 저장
- Toast 알림으로 상태 피드백 제공

---

## 단축키

| 단축키 | 동작 |
|--------|------|
| `Cmd+Shift+S` | 캡처 시작 (창 선택) |
| `Cmd+Shift+Option+S` | Hide 모드에서 다중 이미지 누적 캡처 |
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
        ├── CaptureSessionManager  # 다중 이미지 세션 관리 (최대 5장)
        ├── PlatformDetector       # 창 정보 기반 플랫폼 자동 감지
        ├── SolverEngine           # 문제 모델 → 프롬프트 → 스트리밍 풀이
        ├── ClaudeAPIClient        # Claude Vision API SSE 스트리밍
        │   ├── generateSolutionFromImage()    # 단일 이미지
        │   ├── generateSolutionFromImages()   # 다중 이미지
        │   └── executeStreamingRequest()      # 공통 SSE 파싱 (내부)
        ├── ResponseParser         # API 응답에서 코드 블록 추출
        ├── InputController        # CGEvent 자동 타이핑 (Human-like)
        ├── HideModeManager        # Hide 모드 상태 관리
        ├── AutoScanEngine         # Hide 모드 자동 스캔
        ├── HistoryManager         # UserDefaults 히스토리
        └── UI
            ├── CaptureActionBar       # 다중 캡처 세션 중 액션 바
            ├── FloatingResultPanel    # 플로팅 결과창
            ├── WindowPickerPanel      # 창 선택 UI
            ├── SettingsPanel          # API 키 / 언어 설정
            ├── HistoryPanel           # 히스토리 조회
            ├── ShortcutSettingsPanel  # 단축키 설정
            └── ToastView              # 상태 알림 토스트
```

---

## VDI 지원 계획

VDI(가상 데스크탑) 환경에서는 클립보드 공유와 CGEvent 자동 타이핑이 차단될 수 있습니다.
현재 VDI 환경 **감지**는 구현되어 있으며, 입력 대안 기능은 단계적으로 추가될 예정입니다.

| Phase | 내용 | 상태 |
|-------|------|------|
| 감지 | VMware / Citrix / Microsoft RDP 자동 인식 | ✅ 완료 |
| VDI-4 | VDIAssistWindow (화면에 코드 표시) | 계획 중 |
| VDI-1 | 클립보드 폴백 강화 | 계획 중 |
| VDI-2 | 강화 CGEvent (HID 레벨) | 계획 중 |

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
It captures a coding problem screen from platforms like Baekjoon or LeetCode, sends the image directly to the **Claude Vision API**, and streams the solution code in real time.
The result is either copied to the clipboard or auto-typed directly into your editor.

The **Perfect Hide Mode** leaves no trace in Dock or Mission Control.
**Multi-image capture** lets you accumulate up to 5 screenshots and solve them all at once — perfect for problems spanning multiple screens.

---

## Features

### Core Pipeline
- **Screen Capture** — Select and capture any window using ScreenCaptureKit
- **Claude Vision API** — Send images directly to Claude for streaming solutions without a separate OCR step
- **Multi-image Support** — Accumulate up to 5 images and send them together (for multi-page problems)
- **Auto Platform Detection** — Automatically identifies Baekjoon / LeetCode / VDI from window title and URL
- **Auto Input** — Auto-type via CGEvent or copy to clipboard

### Supported Platforms
| Platform | Mode |
|----------|------|
| Baekjoon | stdin/stdout style |
| LeetCode | Class/function signature style |
| VDI | Environment detection (VMware, Citrix, Microsoft RDP, etc.) |

### Supported Languages
- Python, Java, C++

### Hide Mode
- Completely hidden from menu bar, Dock, Mission Control, and Cmd+Tab
- Enter/exit with a global shortcut (default: `Cmd+Shift+Option+H`)
- Auto-scan mode: automatically re-scans the last selected window

### Multi-image Capture
- Press `Cmd+Shift+Option+S` to accumulate images one by one (up to 5)
- **CaptureActionBar** appears during accumulation — add more, solve, or cancel
- Automatically routes to `generateSolutionFromImage()` (1 image) or `generateSolutionFromImages()` (2–5 images)

### Auto-Typing (Human-like Typing)
- **Natural typing rhythm** — Bigram IKI table (CHI 2018 research) + Gaussian noise for human-like speed variation
- **Typing profiles** — Slow / Average / Fast speed presets
- **Typo simulation** — ~1.2% chance of a typo followed by auto-correction (QWERTY adjacent keys)
- **IDE auto-indent mode** — Prevents double indentation caused by editor auto-indent on `\n` in VSCode, Xcode, etc.

### Other
- Solution history with search
- Customizable global shortcuts
- Shortcut re-registration after sleep/wake
- API key stored securely in Keychain
- Toast notifications for status feedback

---

## Default Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Shift+S` | Start capture (window picker) |
| `Cmd+Shift+Option+S` | Multi-image capture in Hide Mode |
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
        ├── CaptureSessionManager  # Multi-image session (up to 5 images)
        ├── PlatformDetector       # Auto-detect platform from window info
        ├── SolverEngine           # Problem model → prompt → streaming solution
        ├── ClaudeAPIClient        # Claude Vision API SSE streaming
        │   ├── generateSolutionFromImage()    # Single image
        │   ├── generateSolutionFromImages()   # Multiple images
        │   └── executeStreamingRequest()      # Shared SSE parser (internal)
        ├── ResponseParser         # Extract code block from API response
        ├── InputController        # CGEvent auto-typing (Human-like)
        ├── HideModeManager        # Hide mode state management
        ├── AutoScanEngine         # Auto-scan in Hide mode
        ├── HistoryManager         # UserDefaults-based history
        └── UI
            ├── CaptureActionBar       # Action bar during multi-capture session
            ├── FloatingResultPanel    # Floating result window
            ├── WindowPickerPanel      # Window selection UI
            ├── SettingsPanel          # API key / language settings
            ├── HistoryPanel           # History viewer
            ├── ShortcutSettingsPanel  # Shortcut customization
            └── ToastView              # Status toast notifications
```

---

## VDI Support Roadmap

In VDI (Virtual Desktop Infrastructure) environments, clipboard sharing and CGEvent auto-typing may be blocked.
Platform **detection** for VDI is already implemented; input fallback features are planned in phases.

| Phase | Description | Status |
|-------|-------------|--------|
| Detection | VMware / Citrix / Microsoft RDP auto-recognition | ✅ Done |
| VDI-4 | VDIAssistWindow (display code on screen) | Planned |
| VDI-1 | Enhanced clipboard fallback | Planned |
| VDI-2 | Enhanced CGEvent (HID level) | Planned |

---

## License

Built for personal use.

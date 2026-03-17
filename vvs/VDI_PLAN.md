# VDI 환경 입력 대안 기능 계획서

## 배경
VDI(Virtual Desktop Infrastructure) 환경에서는 클립보드 공유와 CGEvent 자동 타이핑이 모두 차단되는 경우가 있다.
이 계획서는 그 상황에서도 Claude가 생성한 코드를 사용자가 효과적으로 활용할 수 있게 하는 대안을 정의한다.

---

## 폴백 체인 (Fallback Chain)

```
1차: NSPasteboard (클립보드) → VDI에서 막혀있으면 실패
2차: 강화 CGEvent (키코드 레벨 직접 입력) → VDI 레이어가 가로채면 실패
3차: IOHIDUserDevice (커널 레벨 가상 HID 키보드) → 가장 강력, 하지만 복잡
4차: OSD 폴백 (VDIAssistWindow) → 항상 동작. 화면에 코드 표시
```

---

## Phase VDI-1: 클립보드 폴백 강화 (1일)

**현재 상태**: `NSPasteboard.general.setString()` 사용 중

**개선**:
- `NSPasteboard` 실패 시 `pbcopy` 프로세스 폴백
- 클립보드 전송 성공/실패 확인 로직 추가
- 실패 시 자동으로 2차 폴백으로 전환

**파일**: `InputController.swift`

---

## Phase VDI-2: 강화 CGEvent (1~2일)

**현재 상태**: `CGEvent(keyboardEventSource:virtualKey:keyDown:)` 사용

**개선**:
- `CGEventSource` 타입을 `.combinedSessionState` → `.hidSystemState`로 변경
- 키 입력 간 지연을 동적으로 조정 (VDI 네트워크 레이턴시 대응)
- 특수 문자 처리: Unicode 직접 삽입 (`CGEventKeyboardSetUnicodeString`)
- 실패 감지: 타이핑 후 클립보드 내용 비교로 성공 여부 확인

**파일**: `InputController.swift`

---

## Phase VDI-3: IOHIDUserDevice 가상 키보드 (3~5일) ⚠️ 복잡

**목적**: 커널 레벨에서 물리적 키보드인 것처럼 위장

**구현**:
```swift
// IOHIDUserDevice로 가상 HID 키보드 디바이스 생성
// kIOHIDRequestTimeoutKey, kIOHIDTransportUSBValue 설정
// HID Usage: Generic Desktop / Keyboard (0x01, 0x06)
```

**필요 권한**: Entitlements에 `com.apple.hid.system.user-access-device` 추가

**리스크**:
- Sandbox 환경에서 동작 안 할 수 있음
- Notarization 시 추가 심사 가능성
- macOS 버전별 동작 차이

**파일**: 신규 `VDIKeyboardDevice.swift`

---

## Phase VDI-4: VDIAssistWindow (1~2일) ✅ 우선 구현 권장

**목적**: 위 방법들이 모두 실패해도 사용자가 코드를 보면서 직접 입력할 수 있게 지원

**구현**:
- FloatingResultPanel을 VDI 모드에서 특별히 활용
- 코드를 논리적 블록(함수, 클래스 등)으로 분할하여 한 섹션씩 크게 표시
- 각 줄에 줄번호 표시
- 이전/다음 섹션 네비게이션 (단축키 지원)
- 폰트 크기 조절 (보조 모니터에서 보기 편하게)
- **always-on-top 보장** (VDI 창 위에 항상 표시)

**UX 흐름**:
1. Claude가 코드 생성 완료
2. 클립보드/CGEvent 실패 감지
3. VDIAssistWindow 자동 팝업
4. 사용자가 코드를 보면서 VDI 에디터에 직접 입력
5. 완료 후 닫기

**파일**: 신규 `VDIAssistWindow.swift`, `FloatingResultView.swift` 수정

---

## Phase VDI-5: 자동 감지 및 폴백 체인 통합 (1일)

**목적**: 수동 설정 없이 환경에 맞는 방법을 자동 선택

**구현**:
```swift
class VDIInputFallbackChain {
    func tryInput(code: String) async -> InputResult {
        // 1. 클립보드 시도
        if await tryClipboard(code) { return .clipboard }
        // 2. CGEvent 시도 (테스트 키 입력 후 확인)
        if await tryEnhancedCGEvent(code) { return .cgevent }
        // 3. IOHIDUserDevice 시도
        if await tryIOHID(code) { return .iohid }
        // 4. VDIAssistWindow 폴백
        showVDIAssistWindow(code)
        return .visual
    }
}
```

**파일**: 신규 `VDIInputFallbackChain.swift`

---

## 우선순위 및 구현 순서

| Phase | 내용 | 예상 기간 | 우선순위 |
|-------|------|-----------|---------|
| VDI-4 | VDIAssistWindow | 1~2일 | **최우선** (항상 동작) |
| VDI-1 | 클립보드 폴백 강화 | 1일 | 높음 |
| VDI-2 | 강화 CGEvent | 1~2일 | 중간 |
| VDI-5 | 자동 감지 통합 | 1일 | 중간 |
| VDI-3 | IOHIDUserDevice | 3~5일 | 낮음 (복잡도 높음) |

**총 예상 기간**: 1~2주 (VDI-4만: 1~2일)

---

## VDIAssistWindow 상세 UI 설계

```
┌─────────────────────────────────────────────────────┐
│ [CodeSolve VDI 보조창]           [- □ x] [폰트 +/-] │
├─────────────────────────────────────────────────────┤
│ Python                           섹션 2/4            │
├─────────────────────────────────────────────────────┤
│  1  def solution(self, nums: List[int]) -> int:     │
│  2      seen = {}                                   │
│  3      for i, n in enumerate(nums):               │
│  4          if n in seen:                           │
│  5              return [seen[n], i]                 │
│  6          seen[n] = i                             │
├─────────────────────────────────────────────────────┤
│  ← 이전 섹션        [전체 복사]        다음 섹션 →   │
└─────────────────────────────────────────────────────┘
```

- 배경 반투명 (VDI 창 위에서도 내용 보임)
- 텍스트 선택 가능 (마우스로 일부 복사)
- ESC로 닫기

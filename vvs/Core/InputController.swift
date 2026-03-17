import AppKit
import Carbon.HIToolbox

/// CGEvent 기반 자동 타이핑 및 클립보드 관리 컨트롤러.
/// Accessibility 권한이 필요하며, 권한이 없으면 클립보드 모드로 자동 폴백한다.
@MainActor
final class InputController {

    static let shared = InputController()

    /// 타이핑 중단 플래그. ESC 키 감지 시 true로 설정된다.
    private(set) var isCancelled = false

    /// ESC 키 로컬 모니터
    private var escMonitor: Any?

    /// ESC 키 글로벌 모니터 (앱 비활성 상태용)
    private var escGlobalMonitor: Any?

    private init() {}

    // MARK: - Accessibility 권한 확인

    /// Accessibility 권한이 부여되었는지 확인한다.
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Accessibility 권한을 요청한다. 시스템 설정 다이얼로그가 표시된다.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 자동 타이핑

    /// 현재 커서 위치에 한 글자씩 텍스트를 입력한다.
    /// Accessibility 권한이 없으면 클립보드에 복사하고 false를 반환한다.
    /// - Parameters:
    ///   - text: 입력할 텍스트
    ///   - delay: 글자 간 딜레이 (기본 0.01초)
    /// - Returns: 자동 타이핑 성공 여부. false이면 클립보드 폴백이 사용됨.
    @discardableResult
    func typeText(_ text: String, delay: TimeInterval = 0.01) async -> Bool {
        // 권한 없으면 클립보드 폴백
        guard hasAccessibilityPermission else {
            copyToClipboard(text)
            return false
        }

        isCancelled = false
        startESCMonitor()

        defer {
            stopESCMonitor()
        }

        let source = CGEventSource(stateID: .hidSystemState)

        for character in text {
            guard !isCancelled else {
                break
            }

            if character == "\n" {
                // Enter 키
                postKeyEvent(keyCode: UInt16(kVK_Return), source: source)
            } else if character == "\t" {
                // Tab 키
                postKeyEvent(keyCode: UInt16(kVK_Tab), source: source)
            } else {
                // 일반 문자: UniChar 기반 입력
                typeCharacter(character, source: source)
            }

            // 딜레이
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        return !isCancelled
    }

    // MARK: - 클립보드 복사

    /// 텍스트를 클립보드에 복사한다.
    /// - Parameter text: 복사할 텍스트
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Private: 키 이벤트 발생

    /// 특정 keyCode로 keyDown/keyUp 이벤트를 발생시킨다.
    private func postKeyEvent(keyCode: UInt16, source: CGEventSource?, flags: CGEventFlags = []) {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// UniChar 기반으로 단일 문자를 입력한다.
    private func typeCharacter(_ char: Character, source: CGEventSource?) {
        let utf16 = Array(String(char).utf16)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - ESC 키 모니터

    /// ESC 키 감지 모니터를 시작한다. 타이핑 중 ESC를 누르면 즉시 중단된다.
    private func startESCMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.isCancelled = true
                return nil // 이벤트 소비
            }
            return event
        }

        // 글로벌 모니터도 추가 (앱이 비활성 상태일 때) - 참조 보관하여 누수 방지
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.isCancelled = true
            }
        }
    }

    /// ESC 키 모니터를 중지한다.
    private func stopESCMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        if let monitor = escGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            escGlobalMonitor = nil
        }
    }
}

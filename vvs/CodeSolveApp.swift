import AppKit

/// CodeSolve 앱 진입점.
/// AppDelegate 기반으로 Dock/Mission Control/Cmd+Tab에 완전히 숨겨진다.
/// WindowGroup을 사용하지 않으며, MenuBarController가 모든 UI를 관리한다.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide 모드 상태 복원
        if HideModeManager.shared.isPerfectHide {
            // Accessibility 권한 확인 - 없으면 Normal 모드로 fallback
            if !AXIsProcessTrusted() {
                HideModeManager.shared.currentState = .normal
                // 접근성 설정 창 오픈
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                AXIsProcessTrustedWithOptions(options)
                // Normal 모드로 진행
            } else {
                // Hide 모드 유지: 앱을 완전히 숨기기
                NSApp.setActivationPolicy(.prohibited)
            }
        }

        // MenuBarController는 항상 초기화 (단축키 등록 목적)
        // MenuBarController init 내부에서 isPerfectHide 확인 후 statusItem 생성 여부 결정
        menuBarController = MenuBarController()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 창이 없어도 앱 유지 (메뉴바 앱)
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

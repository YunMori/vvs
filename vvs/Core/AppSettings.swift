import Foundation

/// UserDefaults 키 상수 모음
enum AppSettings {
    static let defaultLanguage = "defaultLanguage"
    static let typingDelay = "typingDelay"
    static let floatingResultX = "FloatingResultX"
    static let floatingResultY = "FloatingResultY"
    static let floatingResultWidth = "FloatingResultWidth"
    static let floatingResultHeight = "FloatingResultHeight"

    /// 다중 캡처 즉시 풀이 단축키 (Hide 모드: Cmd+Shift+Option+S)
    static let multiCaptureSolveKeyCode = "multiCaptureSolveKeyCode"

    enum Shortcut {
        static let prefix = "Shortcut_"
        static let captureModifiers = prefix + "captureModifiers"
        static let captureKeyCode = prefix + "captureKeyCode"
        static let copyModifiers = prefix + "copyModifiers"
        static let copyKeyCode = prefix + "copyKeyCode"
        static let typeModifiers = prefix + "typeModifiers"
        static let typeKeyCode = prefix + "typeKeyCode"
    }
}

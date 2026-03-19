import Foundation

/// UserDefaults 키 상수 모음
enum AppSettings {
    static let defaultLanguage = "defaultLanguage"
    static let typingDelay = "typingDelay"
    static let humanLikeTypingEnabled = "humanLikeTypingEnabled"
    static let ideModeEnabled = "ideModeEnabled"
    static let typoSimulationEnabled = "typoSimulationEnabled"
    static let floatingResultX = "FloatingResultX"
    static let floatingResultY = "FloatingResultY"
    static let floatingResultWidth = "FloatingResultWidth"
    static let floatingResultHeight = "FloatingResultHeight"

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

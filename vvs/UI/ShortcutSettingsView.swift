import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - Shortcut Model

/// 단축키 설정을 나타내는 모델.
struct ShortcutConfig: Equatable {
    var captureModifiers: NSEvent.ModifierFlags
    var captureKeyCode: UInt16
    var copyModifiers: NSEvent.ModifierFlags
    var copyKeyCode: UInt16
    var typeModifiers: NSEvent.ModifierFlags
    var typeKeyCode: UInt16

    /// 기본 단축키 설정
    static let defaults = ShortcutConfig(
        captureModifiers: [.command, .shift],
        captureKeyCode: UInt16(kVK_ANSI_S),
        copyModifiers: [.command, .shift],
        copyKeyCode: UInt16(kVK_ANSI_C),
        typeModifiers: [.command, .shift],
        typeKeyCode: UInt16(kVK_ANSI_T)
    )

    // MARK: - UserDefaults 키

    private static let prefix = "Shortcut_"

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(captureModifiers.rawValue, forKey: Self.prefix + "captureModifiers")
        defaults.set(Int(captureKeyCode), forKey: Self.prefix + "captureKeyCode")
        defaults.set(copyModifiers.rawValue, forKey: Self.prefix + "copyModifiers")
        defaults.set(Int(copyKeyCode), forKey: Self.prefix + "copyKeyCode")
        defaults.set(typeModifiers.rawValue, forKey: Self.prefix + "typeModifiers")
        defaults.set(Int(typeKeyCode), forKey: Self.prefix + "typeKeyCode")
    }

    static func load() -> ShortcutConfig {
        let ud = UserDefaults.standard

        // 저장된 값이 없으면 기본값 반환
        guard ud.object(forKey: prefix + "captureKeyCode") != nil else {
            return .defaults
        }

        return ShortcutConfig(
            captureModifiers: NSEvent.ModifierFlags(rawValue: UInt(ud.integer(forKey: prefix + "captureModifiers"))),
            captureKeyCode: UInt16(ud.integer(forKey: prefix + "captureKeyCode")),
            copyModifiers: NSEvent.ModifierFlags(rawValue: UInt(ud.integer(forKey: prefix + "copyModifiers"))),
            copyKeyCode: UInt16(ud.integer(forKey: prefix + "copyKeyCode")),
            typeModifiers: NSEvent.ModifierFlags(rawValue: UInt(ud.integer(forKey: prefix + "typeModifiers"))),
            typeKeyCode: UInt16(ud.integer(forKey: prefix + "typeKeyCode"))
        )
    }

    static func resetToDefaults() {
        let ud = UserDefaults.standard
        let keys = [
            "captureModifiers", "captureKeyCode",
            "copyModifiers", "copyKeyCode",
            "typeModifiers", "typeKeyCode"
        ]
        for key in keys {
            ud.removeObject(forKey: prefix + key)
        }
    }
}

// MARK: - Shortcut Settings Panel

/// 단축키 설정을 호스팅하는 NSPanel.
final class ShortcutSettingsPanel: NSPanel {

    private var hostingView: NSHostingView<ShortcutSettingsView>?
    /// 단축키 변경 시 호출되는 콜백
    var onShortcutsChanged: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "단축키 설정"
        self.level = .floating
        self.isReleasedWhenClosed = false
        self.animationBehavior = .documentWindow

        let view = ShortcutSettingsView { [weak self] in
            self?.onShortcutsChanged?()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = self.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(hosting)
        self.hostingView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func showCentered() {
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - SwiftUI View

struct ShortcutSettingsView: View {

    var onShortcutsChanged: (() -> Void)?

    @State private var config: ShortcutConfig = .load()
    @State private var recordingAction: ShortcutAction? = nil
    @State private var statusMessage: String?
    @State private var eventMonitor: Any? = nil

    enum ShortcutAction: String, CaseIterable {
        case capture = "캡처 시작"
        case copy = "결과 복사"
        case type = "자동 타이핑"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            HStack {
                Text("전역 단축키 설정")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            VStack(spacing: 16) {
                // 각 단축키 행
                shortcutRow(
                    action: .capture,
                    label: "캡처 시작",
                    description: "창을 선택하여 캡처 및 풀이를 시작합니다",
                    modifiers: config.captureModifiers,
                    keyCode: config.captureKeyCode
                )

                Divider().padding(.horizontal, 8)

                shortcutRow(
                    action: .copy,
                    label: "결과 복사",
                    description: "마지막 풀이 결과를 클립보드에 복사합니다",
                    modifiers: config.copyModifiers,
                    keyCode: config.copyKeyCode
                )

                Divider().padding(.horizontal, 8)

                shortcutRow(
                    action: .type,
                    label: "자동 타이핑",
                    description: "마지막 풀이 결과를 자동 타이핑합니다",
                    modifiers: config.typeModifiers,
                    keyCode: config.typeKeyCode
                )
            }
            .padding(20)

            Divider()

            // 하단 버튼
            HStack {
                Button("기본값 복원") {
                    resetToDefaults()
                }

                Spacer()

                if let msg = statusMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 420, minHeight: 320)
        .onDisappear {
            removeEventMonitor()
        }
    }

    // MARK: - Row View

    @ViewBuilder
    private func shortcutRow(
        action: ShortcutAction,
        label: String,
        description: String,
        modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 현재 단축키 표시 / 녹화 버튼
            if recordingAction == action {
                Text("키를 입력하세요...")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )
                    .onKeyPress { press in
                        return .handled
                    }

                Button("취소") {
                    recordingAction = nil
                    removeEventMonitor()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: {
                    recordingAction = action
                    startRecording(for: action)
                }) {
                    Text(shortcutDisplayString(modifiers: modifiers, keyCode: keyCode))
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Recording

    /// 현재 이벤트 모니터를 해제하고 nil로 초기화
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func startRecording(for action: ShortcutAction) {
        // 기존 모니터가 있으면 먼저 해제
        removeEventMonitor()

        // 로컬 이벤트 모니터로 키 입력 캡처
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // 수정자 키만 있는 경우 무시
            guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else {
                return event
            }

            // ESC로 취소
            if event.keyCode == UInt16(kVK_Escape) {
                self.recordingAction = nil
                self.removeEventMonitor()
                return nil
            }

            // 단축키 저장
            switch action {
            case .capture:
                config.captureModifiers = flags
                config.captureKeyCode = event.keyCode
            case .copy:
                config.copyModifiers = flags
                config.copyKeyCode = event.keyCode
            case .type:
                config.typeModifiers = flags
                config.typeKeyCode = event.keyCode
            }

            config.save()
            recordingAction = nil
            removeEventMonitor()
            onShortcutsChanged?()

            statusMessage = "단축키가 저장되었습니다"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                statusMessage = nil
            }

            return nil
        }
    }

    private func resetToDefaults() {
        ShortcutConfig.resetToDefaults()
        config = .defaults
        onShortcutsChanged?()

        statusMessage = "기본값으로 복원되었습니다"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            statusMessage = nil
        }
    }

    // MARK: - Display Helpers

    private func shortcutDisplayString(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Opt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }

        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)

        return parts.joined(separator: "+")
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
            UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
            UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
            UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
            UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Return): "Return",
            UInt16(kVK_Tab): "Tab",
            UInt16(kVK_Delete): "Delete",
            UInt16(kVK_ForwardDelete): "Fwd Del",
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        ]
        return keyMap[keyCode] ?? "Key(\(keyCode))"
    }
}

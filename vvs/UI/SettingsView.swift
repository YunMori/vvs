import AppKit
import SwiftUI

/// 설정 화면을 호스팅하는 NSPanel.
final class SettingsPanel: NSWindow {

    private var hostingView: NSHostingView<SettingsView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "CodeSolve 설정"
        self.level = .floating
        self.isReleasedWhenClosed = false
        self.animationBehavior = .documentWindow

        let settingsView = SettingsView()
        let hosting = NSHostingView(rootView: settingsView)
        hosting.frame = self.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(hosting)
        self.hostingView = hosting
    }

    func showCentered() {
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - SwiftUI Settings View

struct SettingsView: View {

    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var selectedLanguage: SolveLanguage = .python
    @State private var typingDelay: Double = 0.01
    @State private var hasAccessibility: Bool = false
    @State private var saveMessage: String?
    @State private var humanLikeTypingEnabled: Bool = true
    @State private var ideModeEnabled: Bool = false
    @State private var typoSimulationEnabled: Bool = false

    var body: some View {
        Form {
            // MARK: - Claude API 설정
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Claude API 키")
                        .font(.headline)

                    HStack {
                        if showAPIKey {
                            TextField("sk-ant-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        } else {
                            SecureField("sk-ant-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        Button("저장") {
                            saveAPIKey()
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                        if KeychainManager.shared.hasAPIKey {
                            Button("삭제") {
                                KeychainManager.shared.deleteAPIKey()
                                apiKey = ""
                                saveMessage = "API 키가 삭제되었습니다"
                                clearMessage()
                            }
                            .foregroundColor(.red)
                        }

                        Spacer()

                        if let msg = saveMessage {
                            Text(msg)
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        }
                    }
                }
            }

            Divider()

            // MARK: - 기본 언어
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("기본 풀이 언어")
                        .font(.headline)

                    Picker("", selection: $selectedLanguage) {
                        ForEach(SolveLanguage.allCases, id: \.rawValue) { lang in
                            Text(lang.rawValue).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedLanguage) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: AppSettings.defaultLanguage)
                    }
                }
            }

            Divider()

            // MARK: - 자동 타이핑 설정
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("자동 타이핑 설정")
                        .font(.headline)

                    // 자연스러운 타이핑 토글
                    Toggle("자연스러운 타이핑", isOn: $humanLikeTypingEnabled)
                        .onChange(of: humanLikeTypingEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: AppSettings.humanLikeTypingEnabled)
                        }
                    Text("사람처럼 타이핑 속도에 변화를 줍니다. 비활성화 시 아래 딜레이 값이 균일하게 적용됩니다.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    // 딜레이 슬라이더
                    HStack {
                        Slider(value: $typingDelay, in: 0.001...0.1, step: 0.001)
                            .onChange(of: typingDelay) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: AppSettings.typingDelay)
                            }
                        Text(String(format: "%.3f초", typingDelay))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 60)
                    }
                    Text(humanLikeTypingEnabled
                         ? "자연 타이핑의 기본 속도 기준값입니다."
                         : "값이 작을수록 빠르게 타이핑됩니다.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Divider()

                    // IDE 자동 들여쓰기 모드 토글
                    Toggle("IDE 자동 들여쓰기 모드", isOn: $ideModeEnabled)
                        .onChange(of: ideModeEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: AppSettings.ideModeEnabled)
                        }
                    Text("VSCode, Xcode 등에서 이중 들여쓰기를 방지합니다. 탭을 공백으로 변환하고 들여쓰기를 에디터에 위임합니다.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Divider()

                    // 오타 시뮬레이션 토글
                    Toggle("오타 시뮬레이션", isOn: $typoSimulationEnabled)
                        .disabled(!humanLikeTypingEnabled)
                        .onChange(of: typoSimulationEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: AppSettings.typoSimulationEnabled)
                        }
                    Text("드물게 오타를 냈다가 자동 정정합니다. (확률 약 1.2%, 자연스러운 타이핑 활성 시에만 동작)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // MARK: - 전역 단축키
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("전역 단축키")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 4) {
                        shortcutRow(keys: "Cmd+Shift+S", description: "캡처 시작 (창 선택)")
                        shortcutRow(keys: "Cmd+Shift+C", description: "마지막 결과 클립보드 복사")
                        shortcutRow(keys: "Cmd+Shift+T", description: "마지막 결과 자동 타이핑")
                    }

                    Text("단축키는 현재 고정값이며 향후 커스터마이즈 기능이 추가될 예정입니다.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // MARK: - Accessibility 권한
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accessibility 권한")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Image(systemName: hasAccessibility ? "checkmark.shield.fill" : "xmark.shield.fill")
                            .foregroundColor(hasAccessibility ? .green : .red)
                            .font(.system(size: 18))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(hasAccessibility ? "권한 허용됨" : "권한 없음")
                                .font(.system(size: 13, weight: .medium))
                            Text(hasAccessibility
                                 ? "자동 타이핑 기능을 사용할 수 있습니다."
                                 : "자동 타이핑을 사용하려면 권한이 필요합니다. 권한이 없으면 클립보드 복사로 대체됩니다.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !hasAccessibility {
                            Button("권한 요청") {
                                InputController.shared.requestAccessibilityPermission()
                                // 딜레이 후 상태 재확인
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                                    hasAccessibility = InputController.shared.hasAccessibilityPermission
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 450, minHeight: 380)
        .onAppear {
            loadSettings()
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func shortcutRow(keys: String, description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func loadSettings() {
        if let key = KeychainManager.shared.loadAPIKey() {
            apiKey = key
        }

        if let langRaw = UserDefaults.standard.string(forKey: AppSettings.defaultLanguage),
           let lang = SolveLanguage(rawValue: langRaw) {
            selectedLanguage = lang
        }

        let saved = UserDefaults.standard.double(forKey: AppSettings.typingDelay)
        typingDelay = saved > 0 ? saved : 0.01

        hasAccessibility = InputController.shared.hasAccessibilityPermission
        humanLikeTypingEnabled = UserDefaults.standard.object(forKey: AppSettings.humanLikeTypingEnabled) as? Bool ?? true
        ideModeEnabled = UserDefaults.standard.object(forKey: AppSettings.ideModeEnabled) as? Bool ?? true
        typoSimulationEnabled = UserDefaults.standard.bool(forKey: AppSettings.typoSimulationEnabled)
    }

    private func saveAPIKey() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try KeychainManager.shared.saveAPIKey(key)
            saveMessage = "API 키가 저장되었습니다"
        } catch {
            saveMessage = "저장 실패: \(error.localizedDescription)"
        }
        clearMessage()
    }

    private func clearMessage() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            saveMessage = nil
        }
    }
}

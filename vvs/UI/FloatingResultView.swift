import AppKit
import SwiftUI
import Combine

/// Always-on-top 플로팅 결과 창 (VDI 모드용).
/// NSApp.activate 호출 없이 makeKeyAndOrderFront만 사용한다.
final class FloatingResultPanel: NSPanel {

    private var hostingView: NSHostingView<FloatingResultContentView>?
    private let viewModel: FloatingResultViewModel

    init() {
        self.viewModel = FloatingResultViewModel()

        // 저장된 위치/크기 복원 또는 기본값
        let savedFrame = Self.loadSavedFrame()

        super.init(
            contentRect: savedFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel,
                        .utilityWindow],
            backing: .buffered,
            defer: false
        )

        self.title = "CodeSolve - 풀이 결과"
        self.isFloatingPanel = true
        self.level = .floating
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.animationBehavior = .documentWindow
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.minSize = NSSize(width: 400, height: 300)

        let contentView = FloatingResultContentView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = self.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(hosting)
        self.hostingView = hosting

        // 창 위치 변경 감지
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// 결과를 표시하고 창을 전면으로 가져온다.
    /// 주의: NSApp.activate 절대 사용 금지. makeKeyAndOrderFront만 사용.
    func showResult(_ solution: SolutionModel) {
        guard UIGate.isAllowed else { return }
        viewModel.updateSolution(solution)
        makeKeyAndOrderFront(nil)
    }

    /// 여러 언어 솔루션을 한번에 설정한다.
    func showResults(_ solutions: [SolveLanguage: SolutionModel]) {
        guard UIGate.isAllowed else { return }
        viewModel.updateSolutions(solutions)
        makeKeyAndOrderFront(nil)
    }

    /// 스트리밍 텍스트를 추가한다.
    func appendStreamingText(_ text: String, language: SolveLanguage) {
        guard UIGate.isAllowed else { return }
        viewModel.appendText(text, for: language)
        if !isVisible {
            makeKeyAndOrderFront(nil)
        }
    }

    /// 스트리밍 시작 시 초기화
    func beginStreaming(language: SolveLanguage) {
        guard UIGate.isAllowed else { return }
        viewModel.beginStreaming(language: language)
        makeKeyAndOrderFront(nil)
    }

    // MARK: - 위치 저장/복원

    @objc private func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    @objc private func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    private func saveFrame() {
        let rect = frame
        UserDefaults.standard.set(rect.origin.x, forKey: "FloatingResultX")
        UserDefaults.standard.set(rect.origin.y, forKey: "FloatingResultY")
        UserDefaults.standard.set(rect.size.width, forKey: "FloatingResultWidth")
        UserDefaults.standard.set(rect.size.height, forKey: "FloatingResultHeight")
    }

    private static func loadSavedFrame() -> NSRect {
        let defaults = UserDefaults.standard
        let x = defaults.double(forKey: "FloatingResultX")
        let y = defaults.double(forKey: "FloatingResultY")
        let w = defaults.double(forKey: "FloatingResultWidth")
        let h = defaults.double(forKey: "FloatingResultHeight")

        if w > 0 && h > 0 {
            return NSRect(x: x, y: y, width: w, height: h)
        }
        // 기본값: 화면 오른쪽 중앙
        return NSRect(x: 100, y: 200, width: 520, height: 600)
    }
}

// MARK: - ViewModel

@MainActor
final class FloatingResultViewModel: ObservableObject {

    @Published var currentLanguage: SolveLanguage = .python
    @Published var codeTexts: [SolveLanguage: String] = [:]
    @Published var explanationTexts: [SolveLanguage: String] = [:]
    @Published var isStreaming = false
    @Published var copyMessage: String?

    func updateSolution(_ solution: SolutionModel) {
        codeTexts[solution.language] = solution.code
        explanationTexts[solution.language] = solution.explanation
        currentLanguage = solution.language
        isStreaming = false
    }

    func updateSolutions(_ solutions: [SolveLanguage: SolutionModel]) {
        for (lang, sol) in solutions {
            codeTexts[lang] = sol.code
            explanationTexts[lang] = sol.explanation
        }
        if let first = solutions.keys.first {
            currentLanguage = first
        }
        isStreaming = false
    }

    func beginStreaming(language: SolveLanguage) {
        codeTexts[language] = ""
        explanationTexts[language] = ""
        currentLanguage = language
        isStreaming = true
    }

    func appendText(_ text: String, for language: SolveLanguage) {
        codeTexts[language, default: ""] += text
    }

    func copyCurrentCode() {
        guard let code = codeTexts[currentLanguage], !code.isEmpty else { return }
        InputController.shared.copyToClipboard(code)
        copyMessage = "복사 완료"

        // 2초 후 메시지 제거
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.copyMessage == "복사 완료" {
                self.copyMessage = nil
            }
        }
    }
}

// MARK: - SwiftUI Content View

struct FloatingResultContentView: View {

    @ObservedObject var viewModel: FloatingResultViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 언어 탭
            HStack(spacing: 0) {
                ForEach(SolveLanguage.allCases, id: \.rawValue) { lang in
                    languageTab(lang)
                }
                Spacer()

                // 복사 버튼
                Button(action: { viewModel.copyCurrentCode() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text(viewModel.copyMessage ?? "복사")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .padding(.trailing, 10)
            }
            .padding(.top, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 코드 표시 영역
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let code = viewModel.codeTexts[viewModel.currentLanguage] ?? ""

                    if code.isEmpty && !viewModel.isStreaming {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("풀이 결과가 여기에 표시됩니다")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 80)
                    } else {
                        Text(code)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if viewModel.isStreaming {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("생성 중...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }

                    // 설명
                    let explanation = viewModel.explanationTexts[viewModel.currentLanguage] ?? ""
                    if !explanation.isEmpty {
                        Divider()
                            .padding(.horizontal, 12)

                        Text(explanation)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    @ViewBuilder
    private func languageTab(_ lang: SolveLanguage) -> some View {
        let isSelected = viewModel.currentLanguage == lang
        let hasContent = !(viewModel.codeTexts[lang]?.isEmpty ?? true)

        Button(action: { viewModel.currentLanguage = lang }) {
            Text(lang.rawValue)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .opacity(hasContent || isSelected ? 1.0 : 0.5)
    }
}

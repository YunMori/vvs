import AppKit
import SwiftUI
import ScreenCaptureKit
import Carbon.HIToolbox

/// 메뉴바 상태
enum MenuBarState {
    case idle
    case capturing
    case ocr
    case generating
    case done
    case error(String)

    var sfSymbolName: String {
        switch self {
        case .idle:       return "chevron.left.forwardslash.chevron.right"
        case .capturing:  return "camera.viewfinder"
        case .ocr:        return "doc.text.magnifyingglass"
        case .generating: return "brain"
        case .done:       return "checkmark.circle.fill"
        case .error:      return "exclamationmark.triangle.fill"
        }
    }

    var tooltip: String {
        switch self {
        case .idle:          return "CodeSolve - 대기 중"
        case .capturing:     return "CodeSolve - 캡처 중..."
        case .ocr:           return "CodeSolve - 텍스트 인식 중..."
        case .generating:    return "CodeSolve - 코드 생성 중..."
        case .done:          return "CodeSolve - 완료"
        case .error(let msg): return "CodeSolve - 오류: \(msg)"
        }
    }
}

/// NSStatusItem 기반 메뉴바 컨트롤러.
/// 캡처 → OCR → 코드 생성 → 결과 표시/자동 타이핑 전체 파이프라인을 구동한다.
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem!
    private var currentState: MenuBarState = .idle
    private var selectedLanguage: SolveLanguage = .python

    /// 현재 생성 작업의 Task (취소 가능)
    private var currentTask: Task<Void, Never>?

    /// UI 패널들
    private var windowPickerPanel: WindowPickerPanel?
    private var floatingResultPanel: FloatingResultPanel?
    private var settingsPanel: SettingsPanel?
    private var historyPanel: HistoryPanel?
    private var shortcutSettingsPanel: ShortcutSettingsPanel?
    private var captureActionBar: CaptureActionBar?

    /// 현재 단축키 설정
    private var shortcutConfig: ShortcutConfig = .load()

    /// 마지막 풀이 결과
    private var lastSolution: SolutionModel?

    /// 전역 단축키 핫키 모니터
    private var globalMonitor: Any?

    /// 절전 해제 감지용
    private var wakeObserver: NSObjectProtocol?

    override init() {
        super.init()
        loadSettings()

        // Hide 모드가 아닐 때만 StatusItem 생성
        if !HideModeManager.shared.isPerfectHide {
            setupStatusItem()
        }

        registerGlobalHotkeys()
        registerWakeNotification()
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - 설정 로드

    private func loadSettings() {
        if let langRaw = UserDefaults.standard.string(forKey: AppSettings.defaultLanguage),
           let lang = SolveLanguage(rawValue: langRaw) {
            selectedLanguage = lang
        }
    }

    // MARK: - StatusItem 설정

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: MenuBarState.idle.sfSymbolName,
                accessibilityDescription: "CodeSolve"
            )
            button.title = "CS"
            button.toolTip = MenuBarState.idle.tooltip
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        // 캡처 시작
        let captureItem = NSMenuItem(
            title: "캡처 시작",
            action: #selector(startCapture),
            keyEquivalent: "s"
        )
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(NSMenuItem.separator())

        // 마지막 결과 복사
        let copyItem = NSMenuItem(
            title: "마지막 결과 복사",
            action: #selector(copyLastResult),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = [.command, .shift]
        copyItem.target = self
        copyItem.isEnabled = lastSolution != nil
        menu.addItem(copyItem)

        // 마지막 결과 자동 타이핑
        let typeItem = NSMenuItem(
            title: "자동 타이핑",
            action: #selector(typeLastResult),
            keyEquivalent: "t"
        )
        typeItem.keyEquivalentModifierMask = [.command, .shift]
        typeItem.target = self
        typeItem.isEnabled = lastSolution != nil
        menu.addItem(typeItem)

        menu.addItem(NSMenuItem.separator())

        // 언어 선택 서브메뉴
        let languageItem = NSMenuItem(title: "풀이 언어", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()

        for lang in SolveLanguage.allCases {
            let item = NSMenuItem(
                title: lang.rawValue,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = lang
            if lang == selectedLanguage {
                item.state = .on
            }
            languageMenu.addItem(item)
        }

        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(NSMenuItem.separator())

        // Dock/Mission Control 숨기기 토글
        let isHidden = NSApp.activationPolicy() == .accessory
        let hideItem = NSMenuItem(
            title: isHidden ? "Dock에 표시" : "Dock에서 숨기기",
            action: #selector(toggleDockVisibility),
            keyEquivalent: "h"
        )
        hideItem.keyEquivalentModifierMask = [.command, .shift]
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(NSMenuItem.separator())

        // 히스토리
        let historyItem = NSMenuItem(
            title: "풀이 히스토리",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        // 설정
        let settingsItem = NSMenuItem(
            title: "설정...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 단축키 설정
        let shortcutItem = NSMenuItem(
            title: "단축키 설정...",
            action: #selector(openShortcutSettings),
            keyEquivalent: ""
        )
        shortcutItem.target = self
        menu.addItem(shortcutItem)

        menu.addItem(NSMenuItem.separator())

        // 완벽한 Hide 모드 (Normal 모드일 때만 표시)
        if !HideModeManager.shared.isPerfectHide {
            let hideModeItem = NSMenuItem(
                title: "완벽한 Hide 모드",
                action: #selector(activateHideMode),
                keyEquivalent: "h"
            )
            hideModeItem.keyEquivalentModifierMask = [.command, .shift, .option]
            hideModeItem.target = self
            menu.addItem(hideModeItem)

            menu.addItem(NSMenuItem.separator())
        }

        // 종료
        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - 전역 단축키 등록

    private func registerGlobalHotkeys() {
        // 기존 모니터 해제
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode
            let config = self.shortcutConfig

            // Cmd+Shift+Option+H: Hide 모드 토글 (keyCode 4 = kVK_ANSI_H)
            if flags == [.command, .shift, .option] && keyCode == 4 {
                DispatchQueue.main.async { self.togglePerfectHideMode() }
                return
            }

            // Hide 모드에서 Cmd+Shift+Option+S (keyCode 1 = kVK_ANSI_S): 즉시 풀이
            if HideModeManager.shared.isPerfectHide && flags == [.command, .shift, .option] && keyCode == 1 {
                DispatchQueue.main.async { self.startHideModeImmediateSolve() }
            } else if flags == config.captureModifiers && keyCode == config.captureKeyCode {
                DispatchQueue.main.async { self.startCapture() }
            } else if flags == config.copyModifiers && keyCode == config.copyKeyCode {
                DispatchQueue.main.async { self.copyLastResult() }
            } else if flags == config.typeModifiers && keyCode == config.typeKeyCode {
                DispatchQueue.main.async { self.typeLastResult() }
            }
        }
    }

    /// 단축키 설정이 변경되었을 때 호출된다.
    private func reloadShortcuts() {
        shortcutConfig = .load()
        registerGlobalHotkeys()
        buildMenu()
    }

    // MARK: - 절전 해제 감지

    /// 절전 해제 시 단축키 재등록을 보장한다.
    private func registerWakeNotification() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerGlobalHotkeys()
        }
    }

    // MARK: - 완벽한 Hide 모드

    /// Hide 모드 진입/탈출을 토글한다.
    private func togglePerfectHideMode() {
        if HideModeManager.shared.isPerfectHide {
            exitPerfectHideMode()
        } else {
            enterPerfectHideMode()
        }
    }

    /// 완벽한 Hide 모드에 진입한다.
    /// 단축키 등록이 확인된 후에만 진입하며, 실패 시 NSAlert로 차단한다.
    private func enterPerfectHideMode() {
        // 단축키 등록 확인: globalMonitor가 nil이면 등록 실패
        if globalMonitor == nil {
            registerGlobalHotkeys()
        }

        guard globalMonitor != nil else {
            // 진입 전이므로 NSAlert 표시 허용
            let alert = NSAlert()
            alert.messageText = "Hide 모드 진입 불가"
            alert.informativeText = "전역 단축키(Cmd+Shift+Option+H) 등록에 실패했습니다. 단축키 없이 Hide 모드에 진입하면 앱을 복구할 수 없습니다."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "확인")
            alert.runModal()
            return
        }

        // StatusItem 제거
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }

        // 모든 UI 패널 닫기
        windowPickerPanel?.orderOut(nil)
        floatingResultPanel?.orderOut(nil)
        settingsPanel?.orderOut(nil)
        historyPanel?.orderOut(nil)
        shortcutSettingsPanel?.orderOut(nil)
        captureActionBar?.close()
        captureActionBar = nil

        // 앱을 Dock/Cmd+Tab/Mission Control에서 완전히 숨기기
        NSApp.setActivationPolicy(.prohibited)

        // 상태 저장
        HideModeManager.shared.currentState = .perfectHide
    }

    /// 완벽한 Hide 모드에서 탈출한다.
    private func exitPerfectHideMode() {
        // 상태 복원
        HideModeManager.shared.currentState = .normal

        // 앱을 accessory 모드로 복원 (메뉴바 앱)
        NSApp.setActivationPolicy(.accessory)

        // StatusItem 재생성
        setupStatusItem()
    }

    // MARK: - 상태 업데이트

    private func updateState(_ newState: MenuBarState) {
        currentState = newState

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Hide 모드에서는 statusItem이 nil이므로 UI 업데이트 스킵
            guard let item = self.statusItem, let button = item.button else { return }
            button.image = NSImage(
                systemSymbolName: newState.sfSymbolName,
                accessibilityDescription: "CodeSolve"
            )
            button.toolTip = newState.tooltip
            // 메뉴 전체 재빌드 대신 필요한 항목만 업데이트
            self.updateMenuItems()
        }
    }

    /// 메뉴 항목의 활성화 상태만 업데이트한다 (전체 재빌드 방지).
    private func updateMenuItems() {
        guard let menu = statusItem?.menu else { return }
        for item in menu.items {
            if item.action == #selector(copyLastResult) || item.action == #selector(typeLastResult) {
                item.isEnabled = lastSolution != nil
            }
        }
    }

    // MARK: - 캡처 파이프라인

    @objc private func startCapture() {
        // Hide 모드이면 이미지 누적 스캔 실행
        if HideModeManager.shared.isPerfectHide {
            AutoScanEngine.shared.performAccumulatingCapture()
            return
        }

        // 이전 작업 취소 및 세션 초기화
        currentTask?.cancel()
        CaptureSessionManager.shared.reset()

        // 권한 확인
        guard CaptureManager.shared.hasScreenCapturePermission else {
            CaptureManager.shared.requestScreenCapturePermission()
            updateState(.error("화면 캡처 권한을 허용해주세요"))
            return
        }

        // API 키 확인
        guard KeychainManager.shared.hasAPIKey else {
            updateState(.error("API 키를 먼저 설정해주세요"))
            openSettings()
            return
        }

        // WindowPicker 표시
        showWindowPicker()
    }

    /// Hide 모드에서 Cmd+Shift+Option+S 단축키: 누적된 이미지로 즉시 풀이
    private func startHideModeImmediateSolve() {
        AutoScanEngine.shared.performImmediateSolve()
    }

    /// WindowPicker 팝업을 표시한다.
    private func showWindowPicker(forAdditional: Bool = false) {
        windowPickerPanel?.orderOut(nil)

        windowPickerPanel = WindowPickerPanel { [weak self] selectedWindow in
            guard let self = self else { return }
            self.addCaptureAndShowActionBar(window: selectedWindow)
        }

        windowPickerPanel?.showCentered()
    }

    /// 선택된 창에 대해 전체 파이프라인을 실행한다.
    private func runPipeline(for window: SCWindow) {
        currentTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                // Step 1: 화면 캡처
                self.updateState(.capturing)
                let image = try await CaptureManager.shared.captureWindow(window)

                // Step 2: Claude Vision으로 직접 전송 (OCR 단계 제거)
                self.updateState(.generating)
                await self.runVisionWithClipboard(image: image)

            } catch {
                self.updateState(.error(error.localizedDescription))
                await self.resetStateAfterDelay()
            }
        }
    }

    /// Claude Vision API로 이미지를 직접 전송하고 클립보드에 복사한다.
    private func runVisionWithClipboard(image: CGImage) async {
        var fullText = ""
        do {
            for try await chunk in ClaudeAPIClient.shared.generateSolutionFromImage(image, language: selectedLanguage) {
                fullText += chunk
            }
            let (code, explanation) = ResponseParser.parse(fullText)
            let solution = SolutionModel(code: code, language: selectedLanguage, explanation: explanation, problem: makePlaceholderProblem())
            self.lastSolution = solution
            await MainActor.run {
                InputController.shared.copyToClipboard(solution.code)
                ToastPanel.show(message: "코드 복사 완료. Cmd+Shift+T로 자동 입력하세요.")
                self.saveToHistory(solution: solution)
            }
            self.updateState(.done)
            await self.resetStateAfterDelay()
        } catch {
            self.updateState(.error(error.localizedDescription))
            await self.resetStateAfterDelay()
        }
    }

    // MARK: - 다중 캡처 파이프라인

    /// 창을 캡처해 세션에 추가하고 CaptureActionBar를 표시한다.
    private func addCaptureAndShowActionBar(window: SCWindow) {
        currentTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                self.updateState(.capturing)
                let image = try await CaptureManager.shared.captureWindow(window)

                let count = CaptureSessionManager.shared.addImage(image)
                if count == nil {
                    // 최대 장수 초과
                    await MainActor.run {
                        ToastPanel.show(message: "최대 \(CaptureSessionManager.maxImages)장까지 캡처할 수 있습니다")
                        self.updateState(.idle)
                    }
                    return
                }

                await MainActor.run {
                    self.updateState(.idle)
                    self.showCaptureActionBar()
                }
            } catch {
                self.updateState(.error(error.localizedDescription))
                await self.resetStateAfterDelay()
            }
        }
    }

    /// CaptureActionBar를 표시한다.
    private func showCaptureActionBar() {
        captureActionBar?.close()

        captureActionBar = CaptureActionBar(
            captureCount: CaptureSessionManager.shared.count,
            isFull: CaptureSessionManager.shared.isFull,
            onAddCapture: { [weak self] in
                guard let self else { return }
                self.captureActionBar?.close()
                self.captureActionBar = nil
                self.showWindowPicker(forAdditional: true)
            },
            onSolve: { [weak self] in
                guard let self else { return }
                self.captureActionBar?.close()
                self.captureActionBar = nil
                self.runMultiCapturePipeline()
            },
            onCancel: { [weak self] in
                guard let self else { return }
                self.captureActionBar?.close()
                self.captureActionBar = nil
                CaptureSessionManager.shared.reset()
                self.updateState(.idle)
            }
        )
        captureActionBar?.show()
    }

    /// 세션에 누적된 이미지로 전체 파이프라인을 실행한다.
    private func runMultiCapturePipeline() {
        currentTask?.cancel()
        let language = selectedLanguage
        currentTask = Task { [weak self] in
            guard let self else { return }
            self.updateState(.generating)

            var fullText = ""
            do {
                for try await chunk in CaptureSessionManager.shared.solve(language: language) {
                    guard !Task.isCancelled else { break }
                    fullText += chunk
                }

                let (code, explanation) = ResponseParser.parse(fullText)
                let solution = SolutionModel(
                    code: code,
                    language: language,
                    explanation: explanation,
                    problem: makePlaceholderProblem()
                )
                self.lastSolution = solution

                await MainActor.run {
                    InputController.shared.copyToClipboard(solution.code)
                    ToastPanel.show(message: "코드 복사 완료. Cmd+Shift+T로 자동 입력하세요.")
                    self.saveToHistory(solution: solution)
                }
                self.updateState(.done)
                CaptureSessionManager.shared.reset()
                await self.resetStateAfterDelay()
            } catch {
                CaptureSessionManager.shared.reset()
                self.updateState(.error(error.localizedDescription))
                await self.resetStateAfterDelay()
            }
        }
    }

    // MARK: - 결과 복사/타이핑

    @objc private func copyLastResult() {
        guard let solution = lastSolution else {
            ToastPanel.show(message: "복사할 결과가 없습니다")
            return
        }

        InputController.shared.copyToClipboard(solution.code)
        ToastPanel.show(message: "코드가 클립보드에 복사되었습니다")
    }

    @objc private func typeLastResult() {
        guard let solution = lastSolution else {
            ToastPanel.show(message: "타이핑할 결과가 없습니다")
            return
        }

        guard InputController.shared.hasAccessibilityPermission else {
            // 권한 없으면 클립보드 폴백
            InputController.shared.copyToClipboard(solution.code)
            ToastPanel.show(message: "Accessibility 권한 없음 - 클립보드에 복사되었습니다")
            return
        }

        let typingDelay = UserDefaults.standard.double(forKey: AppSettings.typingDelay)
        let delay = typingDelay > 0 ? typingDelay : 0.01

        currentTask = Task {
            // 1.5초 대기 (에디터 포커스 시간)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await InputController.shared.typeText(solution.code, delay: delay)
        }
    }

    // MARK: - 언어 선택

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? SolveLanguage else { return }
        selectedLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: AppSettings.defaultLanguage)
        buildMenu()
    }

    // MARK: - 설정

    @objc private func toggleDockVisibility() {
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        buildMenu()
    }

    @objc private func openSettings() {
        if settingsPanel == nil {
            settingsPanel = SettingsPanel()
        }
        settingsPanel?.showCentered()
    }

    @objc private func openHistory() {
        if historyPanel == nil {
            historyPanel = HistoryPanel()
        }
        historyPanel?.showCentered()
    }

    @objc private func openShortcutSettings() {
        if shortcutSettingsPanel == nil {
            shortcutSettingsPanel = ShortcutSettingsPanel()
            shortcutSettingsPanel?.onShortcutsChanged = { [weak self] in
                self?.reloadShortcuts()
            }
        }
        shortcutSettingsPanel?.showCentered()
    }

    @objc private func activateHideMode() {
        enterPerfectHideMode()
    }

    // MARK: - 히스토리 저장

    /// 풀이 결과를 HistoryManager에 저장한다.
    @MainActor
    private func saveToHistory(solution: SolutionModel) {
        HistoryManager.shared.save(
            title: solution.problem.title,
            platform: "",
            language: solution.language.rawValue,
            code: solution.code
        )
    }

    // MARK: - 종료

    @objc private func quitApp() {
        currentTask?.cancel()
        currentTask = nil

        // UI 패널 메모리 해제
        windowPickerPanel?.orderOut(nil)
        windowPickerPanel = nil
        floatingResultPanel?.orderOut(nil)
        floatingResultPanel = nil
        settingsPanel?.orderOut(nil)
        settingsPanel = nil
        historyPanel?.orderOut(nil)
        historyPanel = nil
        shortcutSettingsPanel?.orderOut(nil)
        shortcutSettingsPanel = nil
        captureActionBar?.close()
        captureActionBar = nil

        lastSolution = nil

        // SCShareableContent 캐시 해제
        CaptureManager.shared.invalidateCache()

        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func getOrCreateFloatingResultPanel() -> FloatingResultPanel {
        if let panel = floatingResultPanel {
            return panel
        }
        let panel = FloatingResultPanel()
        floatingResultPanel = panel
        return panel
    }

    /// Vision 모드에서 SolutionModel 생성을 위한 placeholder ProblemModel.
    private func makePlaceholderProblem() -> ProblemModel {
        ProblemModel(title: "Vision 캡처", description: "", inputCondition: "", outputCondition: "", examples: [])
    }

    /// Claude 응답에서 코드와 설명을 추출하여 SolutionModel을 생성한다.
    private func buildSolutionFromResponse(
        _ text: String,
        language: SolveLanguage,
        problem: ProblemModel
    ) -> SolutionModel {
        let (code, explanation) = ResponseParser.parse(text)
        return SolutionModel(code: code, language: language, explanation: explanation, problem: problem)
    }

    /// 지정 시간 후 idle 상태로 복귀한다.
    private func resetStateAfterDelay() async {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if !Task.isCancelled {
            updateState(.idle)
        }
    }
}

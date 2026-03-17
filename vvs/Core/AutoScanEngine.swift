import Foundation
import AppKit
import ScreenCaptureKit

/// Hide 모드 전용 자동 스캔 엔진.
/// 마지막으로 선택한 창을 자동으로 찾아 캡처 → 누적/풀이 파이프라인을 실행한다.
/// 모든 오류는 UI 없이 조용히 무시된다.
final class AutoScanEngine {

    static let shared = AutoScanEngine()

    private init() {}

    // MARK: - 다중 캡처 누적

    /// Hide 모드에서 Cmd+Shift+S: 마지막 창을 캡처해 세션에 누적한다.
    func performAccumulatingCapture() {
        Task { @MainActor in
            await _performAccumulatingCapture()
        }
    }

    @MainActor
    private func _performAccumulatingCapture() async {
        guard let lastWindow = HideModeManager.shared.loadLastWindow() else { return }

        do {
            let windows = try await CaptureManager.shared.getAvailableWindows()
            guard let targetWindow = findTargetWindow(in: windows, info: lastWindow) else { return }
            guard KeychainManager.shared.hasAPIKey else { return }

            let image = try await CaptureManager.shared.captureWindow(targetWindow)

            if let _ = CaptureSessionManager.shared.addImage(image) {
                // 누적 성공 → 조용히 완료
                // (최대치 도달 시 자동으로 즉시 풀이)
                if CaptureSessionManager.shared.isFull {
                    await _performImmediateSolve()
                }
            }
            // 최대치 초과는 조용히 무시
        } catch {
            // Hide 모드에서는 오류 조용히 무시
        }
    }

    // MARK: - 즉시 풀이

    /// Hide 모드에서 Cmd+Shift+Option+S: 누적된 이미지로 즉시 풀이한다.
    func performImmediateSolve() {
        Task { @MainActor in
            await _performImmediateSolve()
        }
    }

    @MainActor
    private func _performImmediateSolve() async {
        // 세션이 비어있으면 기존 단일 캡처 모드로 fallback
        if CaptureSessionManager.shared.isEmpty {
            await _performSingleCapture()
            return
        }

        let platformRaw = UserDefaults.standard.string(forKey: AppSettings.selectedPlatform) ?? Platform.baekjoon.rawValue
        let platform = Platform(rawValue: platformRaw) ?? .baekjoon
        let language: SolveLanguage
        if let langRaw = UserDefaults.standard.string(forKey: AppSettings.defaultLanguage),
           let lang = SolveLanguage(rawValue: langRaw) {
            language = lang
        } else {
            language = .python
        }

        do {
            var fullText = ""
            for try await chunk in CaptureSessionManager.shared.solve(platform: platform, language: language) {
                fullText += chunk
            }

            let code = ResponseParser.extractCode(from: fullText)
            guard !code.isEmpty else {
                CaptureSessionManager.shared.reset()
                return
            }

            InputController.shared.copyToClipboard(code)
            HistoryManager.shared.save(
                title: "Vision 캡처 (\(CaptureSessionManager.shared.count)장)",
                platform: platform.rawValue,
                language: language.rawValue,
                code: code
            )
            CaptureSessionManager.shared.reset()
        } catch {
            CaptureSessionManager.shared.reset()
        }
    }

    // MARK: - 단일 캡처 Fallback

    /// 세션이 없을 때 기존 단일 캡처 fallback
    @MainActor
    private func _performSingleCapture() async {
        guard let lastWindow = HideModeManager.shared.loadLastWindow() else { return }

        do {
            let windows = try await CaptureManager.shared.getAvailableWindows()
            guard let targetWindow = findTargetWindow(in: windows, info: lastWindow) else { return }
            guard KeychainManager.shared.hasAPIKey else { return }

            let platformRaw = UserDefaults.standard.string(forKey: AppSettings.selectedPlatform) ?? Platform.baekjoon.rawValue
            let platform = Platform(rawValue: platformRaw) ?? .baekjoon
            let language: SolveLanguage
            if let langRaw = UserDefaults.standard.string(forKey: AppSettings.defaultLanguage),
               let lang = SolveLanguage(rawValue: langRaw) {
                language = lang
            } else {
                language = .python
            }

            let image = try await CaptureManager.shared.captureWindow(targetWindow)

            var fullText = ""
            for try await chunk in ClaudeAPIClient.shared.generateSolutionFromImage(image, platform: platform, language: language) {
                fullText += chunk
            }

            let code = extractCode(from: fullText)
            guard !code.isEmpty else { return }

            InputController.shared.copyToClipboard(code)
            HistoryManager.shared.save(
                title: "Vision 캡처",
                platform: platform.rawValue,
                language: language.rawValue,
                code: code
            )
        } catch {}
    }

    // MARK: - 대상 창 찾기

    /// SCWindow 목록에서 마지막 선택 창 정보와 일치하는 창을 찾는다.
    /// bundleID로 우선 탐색하고, 실패하면 appName으로 fallback한다.
    private func findTargetWindow(in windows: [SCWindow], info: LastSelectedWindowInfo) -> SCWindow? {
        // 1차: bundleID + windowTitle 정확 매칭
        if let windowTitle = info.windowTitle {
            if let match = windows.first(where: {
                $0.owningApplication?.bundleIdentifier == info.bundleID &&
                $0.title == windowTitle
            }) {
                return match
            }
        }

        // 2차: bundleID만으로 매칭 (첫 번째 창)
        if let match = windows.first(where: {
            $0.owningApplication?.bundleIdentifier == info.bundleID
        }) {
            return match
        }

        // 3차: appName fallback
        if let match = windows.first(where: {
            $0.owningApplication?.applicationName == info.appName
        }) {
            return match
        }

        return nil
    }

    // MARK: - 코드 추출

    /// Claude 응답에서 코드 블록을 추출한다.
    private func extractCode(from text: String) -> String {
        ResponseParser.extractCode(from: text)
    }
}

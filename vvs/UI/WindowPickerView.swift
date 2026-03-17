import AppKit
import SwiftUI
import ScreenCaptureKit

/// 실행 중인 앱/창 목록을 표시하는 팝업 UI.
/// NSPanel 기반으로 메인 앱 활성화 없이 창 선택이 가능하다.
final class WindowPickerPanel: NSPanel {

    private var hostingView: NSHostingView<WindowPickerView>?
    private var onSelect: ((SCWindow) -> Void)?

    init(onSelect: @escaping (SCWindow) -> Void) {
        self.onSelect = onSelect

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.title = "캡처 대상 선택"
        self.isFloatingPanel = true
        self.level = .floating
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.animationBehavior = .utilityWindow

        let pickerView = WindowPickerView(onSelect: { [weak self] window in
            self?.handleSelection(window)
        })

        let hosting = NSHostingView(rootView: pickerView)
        hosting.frame = self.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(hosting)
        self.hostingView = hosting
    }

    func showCentered() {
        guard UIGate.isAllowed else { return }
        center()
        makeKeyAndOrderFront(nil)
    }

    private func handleSelection(_ window: SCWindow) {
        // 마지막 선택 창 정보 저장 (기존 UserDefaults 호환 유지)
        if let bundleID = window.owningApplication?.bundleIdentifier {
            UserDefaults.standard.set(bundleID, forKey: "lastSelectedWindowBundleID")
        }
        if let title = window.title {
            UserDefaults.standard.set(title, forKey: "lastSelectedWindowTitle")
        }

        // HideModeManager에도 저장 (자동 스캔용)
        if let bundleID = window.owningApplication?.bundleIdentifier {
            let appName = window.owningApplication?.applicationName ?? "Unknown"
            HideModeManager.shared.saveLastWindow(
                bundleID: bundleID,
                appName: appName,
                windowTitle: window.title
            )
        }

        orderOut(nil)
        onSelect?(window)
    }
}

// MARK: - SwiftUI View

struct WindowPickerView: View {

    let onSelect: (SCWindow) -> Void

    @State private var windows: [SCWindow] = []
    @State private var displays: [SCDisplay] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // 검색 바
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("창 검색...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if isLoading {
                Spacer()
                ProgressView("창 목록을 가져오는 중...")
                Spacer()
            } else if let errorMessage = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if displays.count > 1 {
                            // 멀티 모니터: 디스플레이별 섹션
                            ForEach(Array(displays.enumerated()), id: \.offset) { index, display in
                                let displayWindows = windowsForDisplay(display)
                                if !displayWindows.isEmpty {
                                    Section {
                                        ForEach(displayWindows, id: \.windowID) { window in
                                            windowRow(window)
                                        }
                                    } header: {
                                        Text("디스플레이 \(index + 1) (\(Int(display.width))x\(Int(display.height)))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(nsColor: .windowBackgroundColor))
                                    }
                                }
                            }
                        } else {
                            // 단일 모니터
                            ForEach(filteredWindows, id: \.windowID) { window in
                                windowRow(window)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 300)
        .task {
            await loadWindows()
        }
    }

    // MARK: - Window Row

    @ViewBuilder
    private func windowRow(_ window: SCWindow) -> some View {
        let isLastSelected = isLastSelectedWindow(window)

        Button(action: { onSelect(window) }) {
            HStack(spacing: 10) {
                // 앱 아이콘
                if let app = window.owningApplication,
                   let icon = NSRunningApplication(processIdentifier: app.processID)?.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "macwindow")
                        .font(.title2)
                        .frame(width: 28, height: 28)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title ?? "제목 없음")
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(window.owningApplication?.applicationName ?? "알 수 없는 앱")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 플랫폼 감지 배지
                let platform = PlatformDetector.detect(from: window)
                if platform != .unknown {
                    Text(platformBadge(platform))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(platformColor(platform).opacity(0.2))
                        .foregroundColor(platformColor(platform))
                        .clipShape(Capsule())
                }

                if isLastSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isLastSelected ? Color.accentColor.opacity(0.08) : Color.clear)

        Divider()
            .padding(.leading, 50)
    }

    // MARK: - Helpers

    private var filteredWindows: [SCWindow] {
        guard !searchText.isEmpty else { return windows }
        let query = searchText.lowercased()
        return windows.filter { window in
            let title = window.title?.lowercased() ?? ""
            let appName = window.owningApplication?.applicationName.lowercased() ?? ""
            return title.contains(query) || appName.contains(query)
        }
    }

    private func windowsForDisplay(_ display: SCDisplay) -> [SCWindow] {
        let displayFrame = CGRect(
            x: CGFloat(display.frame.origin.x),
            y: CGFloat(display.frame.origin.y),
            width: CGFloat(display.width),
            height: CGFloat(display.height)
        )

        let results = filteredWindows.filter { window in
            displayFrame.intersects(window.frame)
        }
        return results
    }

    private func isLastSelectedWindow(_ window: SCWindow) -> Bool {
        let savedBundle = UserDefaults.standard.string(forKey: "lastSelectedWindowBundleID")
        let savedTitle = UserDefaults.standard.string(forKey: "lastSelectedWindowTitle")

        let bundleMatch = window.owningApplication?.bundleIdentifier == savedBundle
        let titleMatch = window.title == savedTitle

        return bundleMatch && titleMatch
    }

    private func platformBadge(_ platform: Platform) -> String {
        switch platform {
        case .baekjoon: return "백준"
        case .leetcode: return "LeetCode"
        case .vdi: return "VDI"
        case .unknown: return ""
        }
    }

    private func platformColor(_ platform: Platform) -> Color {
        switch platform {
        case .baekjoon: return .blue
        case .leetcode: return .orange
        case .vdi: return .purple
        case .unknown: return .gray
        }
    }

    private func loadWindows() async {
        isLoading = true
        do {
            windows = try await CaptureManager.shared.getAvailableWindows()
            displays = try await CaptureManager.shared.getAvailableDisplays()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

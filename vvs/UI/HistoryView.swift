import AppKit
import SwiftUI

/// 히스토리 목록을 표시하는 NSPanel.
/// canBecomeKey/canBecomeMain을 override하여 붙여넣기 버그를 방지한다.
final class HistoryPanel: NSPanel {

    private var hostingView: NSHostingView<HistoryView>?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.title = "CodeSolve - 풀이 히스토리"
        self.level = .floating
        self.isReleasedWhenClosed = false
        self.animationBehavior = .documentWindow
        self.minSize = NSSize(width: 400, height: 300)

        let historyView = HistoryView()
        let hosting = NSHostingView(rootView: historyView)
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

// MARK: - SwiftUI History View

struct HistoryView: View {

    @State private var records: [SolutionRecordDTO] = []
    @State private var copiedId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text("풀이 히스토리")
                    .font(.headline)

                Spacer()

                Text("\(records.count)개")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Button(action: deleteAll) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("전체 삭제")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(records.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // 목록
            if records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("아직 풀이 기록이 없습니다")
                        .foregroundColor(.secondary)
                    Text("캡처 후 풀이가 완료되면 자동으로 저장됩니다")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(records) { record in
                        historyRow(record)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                copyCode(record)
                            }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(minWidth: 400, minHeight: 280)
        .onAppear {
            loadRecords()
        }
    }

    // MARK: - Row View

    @ViewBuilder
    private func historyRow(_ record: SolutionRecordDTO) -> some View {
        HStack(spacing: 12) {
            // 플랫폼 배지
            platformBadge(record.platform)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.title.isEmpty ? "(제목 없음)" : record.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // 언어 태그
                    Text(record.language)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(4)

                    // 시간
                    Text(relativeTime(record.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 복사 상태
            if copiedId == record.id {
                Text("복사됨")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func platformBadge(_ platform: String) -> some View {
        let (color, label) = platformInfo(platform)

        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color)
            .cornerRadius(4)
            .frame(width: 50)
    }

    private func platformInfo(_ platform: String) -> (Color, String) {
        switch platform.lowercased() {
        case "baekjoon":
            return (Color.blue, "BOJ")
        case "leetcode":
            return (Color.orange, "LC")
        case "vdi":
            return (Color.purple, "VDI")
        default:
            return (Color.gray, "ETC")
        }
    }

    // MARK: - Actions

    private func loadRecords() {
        records = HistoryManager.shared.loadAll()
    }

    private func copyCode(_ record: SolutionRecordDTO) {
        InputController.shared.copyToClipboard(record.code)

        withAnimation {
            copiedId = record.id
        }

        // 2초 후 복사 표시 제거
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedId == record.id {
                withAnimation {
                    copiedId = nil
                }
            }
        }
    }

    private func deleteAll() {
        HistoryManager.shared.deleteAll()
        withAnimation {
            records.removeAll()
        }
    }

    // MARK: - Helpers

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.unitsStyle = .full
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

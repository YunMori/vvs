import AppKit
import SwiftUI

/// 화면 하단에 잠깐 표시되는 토스트 알림.
/// NSPanel 기반으로 2초 후 자동으로 사라진다.
final class ToastPanel: NSPanel {

    private static var currentToast: ToastPanel?

    init(message: String) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.ignoresMouseEvents = true
        self.animationBehavior = .none

        let toastView = ToastContentView(message: message)
        let hosting = NSHostingView(rootView: toastView)
        hosting.frame = self.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(hosting)
    }

    // MARK: - 표시

    /// 토스트 메시지를 화면 하단 중앙에 표시한다.
    /// - Parameters:
    ///   - message: 표시할 메시지
    ///   - duration: 표시 시간 (기본 2.0초)
    @MainActor
    static func show(message: String, duration: TimeInterval = 2.0) {
        guard UIGate.isAllowed else { return }

        // 이전 토스트 제거
        currentToast?.orderOut(nil)
        currentToast = nil

        let toast = ToastPanel(message: message)

        // 메인 화면 하단 중앙에 위치
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let toastWidth: CGFloat = 320
            let toastHeight: CGFloat = 50
            let x = screenFrame.origin.x + (screenFrame.width - toastWidth) / 2
            let y = screenFrame.origin.y + 60 // 화면 하단에서 약간 위
            toast.setFrame(NSRect(x: x, y: y, width: toastWidth, height: toastHeight), display: true)
        }

        toast.alphaValue = 0
        toast.makeKeyAndOrderFront(nil)
        currentToast = toast

        // 페이드 인
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            toast.animator().alphaValue = 1.0
        }

        // 지정 시간 후 페이드 아웃 및 제거
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                toast.animator().alphaValue = 0
            }, completionHandler: {
                toast.orderOut(nil)
                if Self.currentToast === toast {
                    Self.currentToast = nil
                }
            })
        }
    }
}

// MARK: - SwiftUI Content

struct ToastContentView: View {

    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 16))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .darkGray).opacity(0.92))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import AppKit

/// 다중 캡처 세션 중 표시되는 액션 바.
/// 추가 캡처 / 풀이 시작 / 취소 버튼을 제공한다.
final class CaptureActionBar: NSPanel {

    var onAddCapture: (() -> Void)?
    var onSolve: (() -> Void)?
    var onCancel: (() -> Void)?

    private let captureCount: Int
    private let isFull: Bool

    init(captureCount: Int, isFull: Bool, onAddCapture: @escaping () -> Void, onSolve: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.captureCount = captureCount
        self.isFull = isFull
        self.onAddCapture = onAddCapture
        self.onSolve = onSolve
        self.onCancel = onCancel

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        setupUI()
    }

    private func setupUI() {
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 420, height: 52))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        // 캡처 수 레이블
        let countLabel = NSTextField(labelWithString: "캡처됨: \(captureCount)장")
        countLabel.font = .systemFont(ofSize: 13, weight: .medium)
        countLabel.textColor = .labelColor
        countLabel.frame = NSRect(x: 14, y: 16, width: 90, height: 20)
        container.addSubview(countLabel)

        // 추가 캡처 버튼
        if !isFull {
            let addButton = makeButton(title: "+ 추가", action: #selector(didTapAdd), x: 112, width: 80)
            container.addSubview(addButton)
        }

        // 풀이 시작 버튼
        let solveButton = makeButton(title: "▶ 풀이 시작", action: #selector(didTapSolve), x: isFull ? 112 : 200, width: 100)
        container.addSubview(solveButton)

        // 취소 버튼
        let cancelButton = makeButton(title: "✕ 취소", action: #selector(didTapCancel), x: isFull ? 220 : 308, width: 70)
        container.addSubview(cancelButton)

        contentView = container
    }

    private func makeButton(title: String, action: Selector, x: CGFloat, width: CGFloat) -> NSButton {
        let button = NSButton(frame: NSRect(x: x, y: 10, width: width, height: 32))
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        return button
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowFrame = NSRect(
            x: screenFrame.midX - frame.width / 2,
            y: screenFrame.maxY - frame.height - 20,
            width: frame.width,
            height: frame.height
        )
        setFrame(windowFrame, display: true)
        orderFrontRegardless()
    }

    override func close() {
        orderOut(nil)
    }

    @objc private func didTapAdd() { onAddCapture?() }
    @objc private func didTapSolve() { onSolve?() }
    @objc private func didTapCancel() { onCancel?() }
}

import Foundation
import os
import ScreenCaptureKit
import CoreGraphics
import CoreImage
import CoreMedia

/// ScreenCaptureKit 기반 화면 캡처 매니저.
/// 실행 중인 창 목록 열거, 특정 창 캡처, 권한 확인 기능을 제공한다.
final class CaptureManager: @unchecked Sendable {

    static let shared = CaptureManager()

    // MARK: - SCShareableContent 캐싱 (2초 TTL)

    private let cacheTTL: TimeInterval = 2.0

    private struct CacheState {
        var content: SCShareableContent?
        var timestamp: Date = .distantPast
    }
    private let cacheState = OSAllocatedUnfairLock(initialState: CacheState())

    private init() {}

    /// 캐시된 SCShareableContent를 반환한다. TTL 초과 시 새로 조회한다.
    private func getCachedContent(excludeDesktopWindows: Bool = true) async throws -> SCShareableContent {
        let (cached, timestamp) = cacheState.withLock { ($0.content, $0.timestamp) }

        if let cached, Date().timeIntervalSince(timestamp) < cacheTTL {
            return cached
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            excludeDesktopWindows,
            onScreenWindowsOnly: true
        )

        cacheState.withLock {
            $0.content = content
            $0.timestamp = Date()
        }

        return content
    }

    /// 캐시를 명시적으로 무효화한다.
    func invalidateCache() {
        cacheState.withLock {
            $0.content = nil
            $0.timestamp = Date.distantPast
        }
    }

    // MARK: - 권한 확인

    /// 화면 캡처 권한이 이미 부여되었는지 확인한다. UI를 차단하지 않는다.
    var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 화면 캡처 권한을 요청한다. 사용자에게 시스템 다이얼로그가 표시된다.
    @discardableResult
    func requestScreenCapturePermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - 창 목록 열거

    /// 현재 화면에 표시 중인 창 목록을 반환한다.
    /// - Parameter excludeDesktopWindows: 데스크톱 배경 창 제외 여부 (기본 true)
    /// - Returns: `SCShareableContent`에서 가져온 창 목록
    func getAvailableWindows(excludeDesktopWindows: Bool = true) async throws -> [SCWindow] {
        let content = try await getCachedContent(excludeDesktopWindows: excludeDesktopWindows)
        // 제목이 있고 크기가 유의미한 창만 필터링
        return content.windows.filter { window in
            guard let title = window.title, !title.isEmpty else { return false }
            return window.frame.width > 100 && window.frame.height > 100
        }
    }

    /// 실행 중인 디스플레이 목록을 반환한다 (멀티 모니터 지원).
    func getAvailableDisplays() async throws -> [SCDisplay] {
        let content = try await getCachedContent()
        return content.displays
    }

    // MARK: - 창 캡처

    /// 특정 SCWindow를 단독 캡처하여 CGImage로 반환한다.
    /// - Parameters:
    ///   - window: 캡처할 대상 창
    ///   - scaleFactor: 캡처 해상도 배율 (기본 2.0, Retina)
    /// - Returns: 캡처된 CGImage
    func captureWindow(_ window: SCWindow, scaleFactor: CGFloat = 1.5) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scaleFactor)
        configuration.height = Int(window.frame.height * scaleFactor)
        configuration.scalesToFit = false
        configuration.capturesAudio = false
        configuration.showsCursor = false

        if #available(macOS 14.0, *) {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return image
        } else {
            // macOS 13 폴백: SCStream으로 단일 프레임 캡처
            return try await captureWindowLegacy(filter: filter, configuration: configuration)
        }
    }


    // MARK: - macOS 13 Legacy Capture

    /// macOS 13 폴백: SCStream을 이용한 단일 프레임 캡처
    private func captureWindowLegacy(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        return try await withCheckedThrowingContinuation { continuation in
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            let output = LegacyCaptureOutput(continuation: continuation)
            do {
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global())
                stream.startCapture { error in
                    if let error {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Legacy SCStreamOutput

private final class LegacyCaptureOutput: NSObject, SCStreamOutput {
    private var continuation: CheckedContinuation<CGImage, Error>?
    private var captured = false

    init(continuation: CheckedContinuation<CGImage, Error>) {
        self.continuation = continuation
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !captured, type == .screen else { return }
        captured = true

        guard
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            continuation?.resume(throwing: CaptureError.captureFailure("프레임 버퍼 변환 실패"))
            continuation = nil
            stream.stopCapture(completionHandler: nil)
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            continuation?.resume(throwing: CaptureError.captureFailure("CGImage 변환 실패"))
            continuation = nil
            stream.stopCapture(completionHandler: nil)
            return
        }

        continuation?.resume(returning: cgImage)
        continuation = nil
        stream.stopCapture(completionHandler: nil)
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case captureFailure(String)

    var errorDescription: String? {
        switch self {
        case .captureFailure(let detail):
            return "화면 캡처 실패: \(detail)"
        }
    }
}

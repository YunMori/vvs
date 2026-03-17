import Foundation
import ScreenCaptureKit
import CoreGraphics

/// 다중 캡처 세션 상태
enum CaptureSessionState {
    case idle
    case collecting(count: Int)  // 이미지 누적 중
    case solving                 // API 전송 중
}

/// 다중 캡처 세션 관리자.
/// 이미지를 누적하고, CaptureSessionManager.solve()로 단일/다중 분기를 담당한다.
final class CaptureSessionManager {

    static let shared = CaptureSessionManager()

    private(set) var capturedImages: [CGImage] = []
    private(set) var state: CaptureSessionState = .idle

    static let maxImages = 5

    private init() {}

    /// 이미지를 세션에 추가한다. 최대 5장까지 허용.
    /// - Returns: 추가 후 누적 이미지 수. maxImages 초과 시 nil 반환.
    @discardableResult
    func addImage(_ image: CGImage) -> Int? {
        guard capturedImages.count < CaptureSessionManager.maxImages else { return nil }
        capturedImages.append(image)
        state = .collecting(count: capturedImages.count)
        return capturedImages.count
    }

    /// 세션을 초기화한다.
    func reset() {
        capturedImages = []
        state = .idle
    }

    /// 누적된 이미지로 Claude Vision API를 호출하는 스트림을 반환한다.
    /// 1장이면 기존 generateSolutionFromImage(), 2장 이상이면 generateSolutionFromImages()를 사용한다.
    func solve(platform: Platform, language: SolveLanguage) -> AsyncThrowingStream<String, Error> {
        let images = capturedImages
        guard !images.isEmpty else {
            return AsyncThrowingStream { $0.finish(throwing: CaptureSessionError.noImagesAvailable) }
        }
        state = .solving
        if images.count == 1 {
            return ClaudeAPIClient.shared.generateSolutionFromImage(images[0], platform: platform, language: language)
        } else {
            return ClaudeAPIClient.shared.generateSolutionFromImages(images, platform: platform, language: language)
        }
    }

    var isEmpty: Bool { capturedImages.isEmpty }
    var count: Int { capturedImages.count }
    var isFull: Bool { capturedImages.count >= CaptureSessionManager.maxImages }
}

enum CaptureSessionError: LocalizedError {
    case noImagesAvailable

    var errorDescription: String? {
        "캡처된 이미지가 없습니다. 먼저 화면을 캡처해주세요."
    }
}

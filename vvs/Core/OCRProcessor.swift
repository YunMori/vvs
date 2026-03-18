import Foundation
import Vision
import CoreGraphics

/// Apple Vision Framework 기반 OCR 프로세서.
/// CGImage에서 텍스트를 추출하고 ProblemModel로 구조화한다.
final class OCRProcessor: @unchecked Sendable {

    static let shared = OCRProcessor()

    /// confidence 임계값. 이 값 미만의 텍스트 블록은 무시한다.
    private let confidenceThreshold: Float = 0.7

    /// 재사용 가능한 VNRecognizeTextRequest 설정 (매 호출마다 새로 생성하지 않음)
    private let recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    private let recognitionLanguages: [String] = ["ko", "en-US"]
    private let minimumTextHeight: Float = 0.01

    private init() {}

    // MARK: - OCR 텍스트 추출

    /// CGImage에서 텍스트를 추출한다.
    /// - Parameter image: OCR 대상 이미지
    /// - Returns: 인식된 텍스트 줄 배열 (confidence 필터링 적용)
    func recognizeText(from image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            let request = VNRecognizeTextRequest { request, error in
                guard !hasResumed else { return }
                hasResumed = true

                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let confidenceThreshold = self.confidenceThreshold
                let lines = observations.compactMap { observation -> String? in
                    guard observation.confidence >= confidenceThreshold else { return nil }
                    return observation.topCandidates(1).first?.string
                }

                continuation.resume(returning: lines)
            }

            // 미리 설정된 값으로 request 구성 (재사용 패턴)
            request.recognitionLevel = self.recognitionLevel
            request.usesLanguageCorrection = true
            request.recognitionLanguages = self.recognitionLanguages
            request.minimumTextHeight = self.minimumTextHeight

            // VNImageRequestHandler에 불필요한 옵션 전달하지 않음
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - 문제 파싱

    /// OCR 결과 텍스트를 ProblemModel로 구조화한다.
    /// - Parameters:
    ///   - image: 캡처된 이미지
    /// - Returns: 구조화된 ProblemModel
    func extractProblem(from image: CGImage) async throws -> ProblemModel {
        let lines = try await recognizeText(from: image)

        guard !lines.isEmpty else {
            throw OCRError.noTextFound
        }

        let fullText = lines.joined(separator: "\n")
        return parseGenericProblem(from: fullText, lines: lines)
    }

    // MARK: - 일반 파서

    private func parseGenericProblem(from fullText: String, lines: [String]) -> ProblemModel {
        let title = lines.first ?? "Unknown Problem"
        return ProblemModel(
            title: title,
            description: fullText,
            inputCondition: "",
            outputCondition: "",
            examples: []
        )
    }
}

// MARK: - Errors

enum OCRError: LocalizedError {
    case noTextFound
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return "이미지에서 텍스트를 찾을 수 없습니다."
        case .recognitionFailed(let detail):
            return "텍스트 인식 실패: \(detail)"
        }
    }
}

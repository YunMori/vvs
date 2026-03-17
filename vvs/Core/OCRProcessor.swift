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
    ///   - platform: 감지된 플랫폼
    /// - Returns: 구조화된 ProblemModel
    func extractProblem(from image: CGImage, platform: Platform) async throws -> ProblemModel {
        let lines = try await recognizeText(from: image)

        guard !lines.isEmpty else {
            throw OCRError.noTextFound
        }

        let fullText = lines.joined(separator: "\n")

        switch platform {
        case .baekjoon:
            return parseBaekjoonProblem(from: fullText, lines: lines)
        case .leetcode:
            return parseLeetCodeProblem(from: fullText, lines: lines)
        case .vdi, .unknown:
            return parseGenericProblem(from: fullText, lines: lines, platform: platform)
        }
    }

    // MARK: - 백준 파서

    private func parseBaekjoonProblem(from fullText: String, lines: [String]) -> ProblemModel {
        var title = ""
        var description = ""
        var inputCondition = ""
        var outputCondition = ""
        var examples: [ProblemModel.Example] = []

        // 백준 문제 구조: 제목, 문제, 입력, 출력, 예제 입력/출력
        var currentSection = ""
        var sectionContent: [String] = []
        var exampleInputs: [String] = []
        var exampleOutputs: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("문제") && !trimmed.contains("예제") && title.isEmpty {
                if currentSection.isEmpty && sectionContent.isEmpty {
                    title = sectionContent.joined(separator: " ")
                }
                flushSection(
                    section: currentSection,
                    content: sectionContent,
                    description: &description,
                    inputCondition: &inputCondition,
                    outputCondition: &outputCondition
                )
                currentSection = "문제"
                sectionContent = []
                continue
            }

            // 섹션 헤더 감지
            if trimmed == "입력" || trimmed.hasPrefix("입력") && trimmed.count <= 4 {
                flushSection(
                    section: currentSection,
                    content: sectionContent,
                    description: &description,
                    inputCondition: &inputCondition,
                    outputCondition: &outputCondition
                )
                currentSection = "입력"
                sectionContent = []
                continue
            }

            if trimmed == "출력" || trimmed.hasPrefix("출력") && trimmed.count <= 4 {
                flushSection(
                    section: currentSection,
                    content: sectionContent,
                    description: &description,
                    inputCondition: &inputCondition,
                    outputCondition: &outputCondition
                )
                currentSection = "출력"
                sectionContent = []
                continue
            }

            if trimmed.hasPrefix("예제 입력") {
                flushSection(
                    section: currentSection,
                    content: sectionContent,
                    description: &description,
                    inputCondition: &inputCondition,
                    outputCondition: &outputCondition
                )
                currentSection = "예제입력"
                sectionContent = []
                continue
            }

            if trimmed.hasPrefix("예제 출력") {
                // 이전 예제 입력 저장
                if currentSection == "예제입력" {
                    exampleInputs.append(sectionContent.joined(separator: "\n"))
                }
                currentSection = "예제출력"
                sectionContent = []
                continue
            }

            // 제목 추출: 첫 번째 유의미한 줄
            if title.isEmpty && !trimmed.isEmpty && currentSection.isEmpty {
                title = trimmed
                continue
            }

            sectionContent.append(trimmed)
        }

        // 마지막 섹션 플러시
        if currentSection == "예제출력" {
            exampleOutputs.append(sectionContent.joined(separator: "\n"))
        } else if currentSection == "예제입력" {
            exampleInputs.append(sectionContent.joined(separator: "\n"))
        } else {
            flushSection(
                section: currentSection,
                content: sectionContent,
                description: &description,
                inputCondition: &inputCondition,
                outputCondition: &outputCondition
            )
        }

        // 예제 쌍 생성
        let pairCount = min(exampleInputs.count, exampleOutputs.count)
        for i in 0..<pairCount {
            examples.append(ProblemModel.Example(
                input: exampleInputs[i].trimmingCharacters(in: .whitespacesAndNewlines),
                output: exampleOutputs[i].trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        return ProblemModel(
            title: title,
            description: description.isEmpty ? fullText : description,
            inputCondition: inputCondition,
            outputCondition: outputCondition,
            examples: examples,
            platform: .baekjoon
        )
    }

    private func flushSection(
        section: String,
        content: [String],
        description: inout String,
        inputCondition: inout String,
        outputCondition: inout String
    ) {
        let joined = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        switch section {
        case "문제":
            description = joined
        case "입력":
            inputCondition = joined
        case "출력":
            outputCondition = joined
        default:
            break
        }
    }

    // MARK: - LeetCode 파서

    private func parseLeetCodeProblem(from fullText: String, lines: [String]) -> ProblemModel {
        var title = ""
        var description = ""
        var examples: [ProblemModel.Example] = []

        // LeetCode 문제 구조: 번호. 제목, Description, Example, Constraints
        var currentSection = "title"
        var sectionLines: [String] = []
        var currentExampleInput = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 제목: "1. Two Sum" 패턴
            if title.isEmpty {
                let pattern = /^\d+\.\s+(.+)$/
                if let match = trimmed.firstMatch(of: pattern) {
                    title = String(match.1)
                    continue
                }
                if title.isEmpty && !trimmed.isEmpty {
                    title = trimmed
                    continue
                }
            }

            if trimmed.hasPrefix("Example") {
                if !sectionLines.isEmpty && currentSection == "description" {
                    description = sectionLines.joined(separator: "\n")
                    sectionLines = []
                }
                currentSection = "example"
                continue
            }

            if trimmed.hasPrefix("Constraints") || trimmed.hasPrefix("제한") {
                currentSection = "constraints"
                continue
            }

            if currentSection == "example" {
                if trimmed.hasPrefix("Input:") || trimmed.hasPrefix("입력:") {
                    currentExampleInput = String(trimmed.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                } else if trimmed.hasPrefix("Output:") || trimmed.hasPrefix("출력:") {
                    let output = String(trimmed.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces)
                    examples.append(ProblemModel.Example(input: currentExampleInput, output: output))
                    currentExampleInput = ""
                }
            }

            if currentSection == "title" || currentSection == "description" {
                currentSection = "description"
                sectionLines.append(trimmed)
            }
        }

        if description.isEmpty {
            description = sectionLines.joined(separator: "\n")
        }

        return ProblemModel(
            title: title,
            description: description.isEmpty ? fullText : description,
            inputCondition: "",
            outputCondition: "",
            examples: examples,
            platform: .leetcode
        )
    }

    // MARK: - 일반 파서

    private func parseGenericProblem(from fullText: String, lines: [String], platform: Platform) -> ProblemModel {
        let title = lines.first ?? "Unknown Problem"
        return ProblemModel(
            title: title,
            description: fullText,
            inputCondition: "",
            outputCondition: "",
            examples: [],
            platform: platform
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

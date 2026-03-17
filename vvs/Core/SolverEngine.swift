import Foundation

/// 문제 풀이 엔진.
/// ProblemModel + SolveLanguage를 입력받아 프롬프트를 구성하고
/// ClaudeAPIClient를 호출하여 스트리밍 풀이를 생성한다.
@MainActor
final class SolverEngine {

    static let shared = SolverEngine()

    /// 현재 풀이 진행 상태
    enum SolveState: Sendable {
        case idle
        case solving
        case completed(SolutionModel)
        case failed(String)
    }

    /// 마지막 풀이 결과 (여러 언어 보관)
    private(set) var lastSolutions: [SolveLanguage: SolutionModel] = [:]

    /// 현재 상태
    private(set) var state: SolveState = .idle

    private init() {}

    // MARK: - 스트리밍 풀이 생성

    /// 문제와 언어를 입력받아 Claude API로 풀이를 스트리밍 생성한다.
    /// - Parameters:
    ///   - problem: OCR로 추출된 문제 모델
    ///   - language: 풀이 언어
    /// - Returns: 텍스트 청크를 방출하는 AsyncThrowingStream
    func solve(
        problem: ProblemModel,
        language: SolveLanguage
    ) -> AsyncThrowingStream<String, Error> {
        state = .solving

        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }

                var fullText = ""

                do {
                    for try await chunk in ClaudeAPIClient.shared.generateSolution(
                        for: problem,
                        language: language
                    ) {
                        fullText += chunk
                        continuation.yield(chunk)
                    }

                    let solution = self.buildSolution(
                        from: fullText,
                        language: language,
                        problem: problem
                    )
                    self.lastSolutions[language] = solution
                    self.state = .completed(solution)
                    continuation.finish()

                } catch {
                    self.state = .failed(error.localizedDescription)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// 스트리밍 없이 전체 풀이를 한번에 생성한다.
    func solveFull(
        problem: ProblemModel,
        language: SolveLanguage
    ) async throws -> SolutionModel {
        state = .solving

        var fullText = ""
        for try await chunk in ClaudeAPIClient.shared.generateSolution(
            for: problem,
            language: language
        ) {
            fullText += chunk
        }

        let solution = buildSolution(from: fullText, language: language, problem: problem)
        lastSolutions[language] = solution
        state = .completed(solution)
        return solution
    }

    /// 마지막 풀이 결과를 특정 언어로 가져온다.
    func lastSolution(for language: SolveLanguage) -> SolutionModel? {
        lastSolutions[language]
    }

    /// 가장 최근 풀이 결과 (언어 무관)
    var latestSolution: SolutionModel? {
        lastSolutions.values.first
    }

    /// 상태 초기화
    func reset() {
        state = .idle
        lastSolutions.removeAll()
    }

    // MARK: - 응답 파싱

    /// Claude 응답 텍스트에서 코드와 설명을 분리하여 SolutionModel로 변환한다.
    private func buildSolution(
        from text: String,
        language: SolveLanguage,
        problem: ProblemModel
    ) -> SolutionModel {
        let (code, explanation) = parseCodeAndExplanation(from: text)

        return SolutionModel(
            code: code,
            language: language,
            explanation: explanation,
            problem: problem
        )
    }

    /// ``` 코드 블록과 그 외 텍스트를 분리한다.
    private func parseCodeAndExplanation(from text: String) -> (code: String, explanation: String) {
        return ResponseParser.parse(text)
    }
}

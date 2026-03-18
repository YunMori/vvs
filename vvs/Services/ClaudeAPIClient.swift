import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Claude Text API 클라이언트.
/// SSE 스트리밍으로 코드 생성 응답을 실시간 수신한다.
final class ClaudeAPIClient: @unchecked Sendable {

    static let shared = ClaudeAPIClient()

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let modelID = "claude-opus-4-6"
    private let apiVersion = "2023-06-01"
    private let maxTokens = 8192

    /// 최적화된 URLSession (타임아웃, 버퍼 크기 설정)
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.urlCache = nil                    // API 응답 캐싱 불필요
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 2 // Anthropic API 동시 연결 제한
        self.session = URLSession(configuration: config)
    }

    // MARK: - 스트리밍 코드 생성

    /// 문제와 언어를 입력받아 Claude API로 풀이 코드를 스트리밍 생성한다.
    /// - Parameters:
    ///   - problem: OCR로 추출한 문제 모델
    ///   - language: 풀이 언어
    /// - Returns: 텍스트 청크를 순차적으로 방출하는 AsyncThrowingStream
    func generateSolution(
        for problem: ProblemModel,
        language: SolveLanguage
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = KeychainManager.shared.loadAPIKey() else {
                        throw ClaudeAPIError.apiKeyNotFound
                    }

                    let prompt = buildPrompt(for: problem, language: language)
                    let body = buildRequestBody(prompt: prompt)
                    let bodyData = try JSONSerialization.data(withJSONObject: body)

                    var request = URLRequest(url: apiURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                    request.httpBody = bodyData

                    let (asyncBytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw ClaudeAPIError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        // 에러 바디 읽기
                        var errorBody = ""
                        for try await line in asyncBytes.lines {
                            errorBody += line
                        }
                        throw ClaudeAPIError.httpError(
                            statusCode: httpResponse.statusCode,
                            body: errorBody
                        )
                    }

                    // SSE 스트림 파싱
                    for try await line in asyncBytes.lines {
                        guard !Task.isCancelled else {
                            continuation.finish()
                            return
                        }

                        // SSE 형식: "data: {...}"
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))

                        // [DONE] 시그널 또는 빈 데이터 무시
                        guard jsonString != "[DONE]",
                              let jsonData = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                        else { continue }

                        let eventType = json["type"] as? String ?? ""

                        switch eventType {
                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }

                        case "message_stop":
                            continuation.finish()
                            return

                        case "error":
                            if let error = json["error"] as? [String: Any],
                               let message = error["message"] as? String {
                                throw ClaudeAPIError.apiError(message)
                            }

                        default:
                            // ping, message_start, content_block_start 등 무시
                            break
                        }
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - CGImage → base64 PNG 변환

    private func encodeImageToBase64(_ image: CGImage) -> String? {
        let mutableData = CFDataCreateMutable(nil, 0)!
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (mutableData as Data).base64EncodedString()
    }

    // MARK: - Vision 기반 스트리밍 코드 생성

    /// 이미지를 Claude Vision API에 직접 전송하여 풀이 코드를 스트리밍 생성한다.
    /// - Parameters:
    ///   - image: 캡처한 화면 이미지
    ///   - platform: 문제 플랫폼 (백준/LeetCode)
    ///   - language: 풀이 언어
    /// - Returns: 텍스트 청크를 순차적으로 방출하는 AsyncThrowingStream
    func generateSolutionFromImage(
        _ image: CGImage,
        platform: Platform,
        language: SolveLanguage
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = KeychainManager.shared.loadAPIKey() else {
                        throw ClaudeAPIError.apiKeyNotFound
                    }
                    guard let base64 = encodeImageToBase64(image) else {
                        throw ClaudeAPIError.apiError("이미지 인코딩 실패")
                    }

                    let systemPrompt = loadPromptTemplate(for: platform)
                    let userText = """
                    위 이미지는 \(platform == .leetcode ? "LeetCode" : "백준") 코딩 문제 화면입니다.
                    풀이 언어: \(language.rawValue)

                    이미지에서 문제를 직접 읽고 풀이 코드를 작성해주세요.
                    """

                    let body: [String: Any] = [
                        "model": modelID,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "system": systemPrompt,
                        "messages": [
                            [
                                "role": "user",
                                "content": [
                                    [
                                        "type": "image",
                                        "source": [
                                            "type": "base64",
                                            "media_type": "image/png",
                                            "data": base64
                                        ]
                                    ],
                                    [
                                        "type": "text",
                                        "text": userText
                                    ]
                                ]
                            ]
                        ]
                    ]

                    let bodyData = try JSONSerialization.data(withJSONObject: body)
                    var request = URLRequest(url: apiURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                    request.httpBody = bodyData

                    let (asyncBytes, response) = try await self.session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw ClaudeAPIError.invalidResponse
                    }
                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in asyncBytes.lines { errorBody += line }
                        throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
                    }

                    for try await line in asyncBytes.lines {
                        guard !Task.isCancelled else { continuation.finish(); return }
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]",
                              let jsonData = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                        else { continue }

                        switch json["type"] as? String ?? "" {
                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        case "message_stop":
                            continuation.finish(); return
                        case "error":
                            if let error = json["error"] as? [String: Any],
                               let message = error["message"] as? String {
                                throw ClaudeAPIError.apiError(message)
                            }
                        default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - 다중 이미지 Vision 기반 스트리밍 코드 생성

    /// 여러 이미지를 다중 블록으로 Claude Vision API에 전송하여 풀이 코드를 스트리밍 생성한다.
    /// 이미지는 순서대로 한 문제의 연속된 화면으로 처리된다.
    /// - Parameters:
    ///   - images: 순서대로 누적된 캡처 이미지 배열 (최대 5장)
    ///   - platform: 문제 플랫폼
    ///   - language: 풀이 언어
    /// - Returns: 텍스트 청크를 순차적으로 방출하는 AsyncThrowingStream
    func generateSolutionFromImages(
        _ images: [CGImage],
        platform: Platform,
        language: SolveLanguage
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = KeychainManager.shared.loadAPIKey() else {
                        throw ClaudeAPIError.apiKeyNotFound
                    }

                    // 각 이미지를 base64로 인코딩
                    var imageBlocks: [[String: Any]] = []
                    for image in images {
                        guard let base64 = self.encodeImageToBase64(image) else {
                            throw ClaudeAPIError.apiError("이미지 인코딩 실패")
                        }
                        imageBlocks.append([
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": base64
                            ]
                        ])
                    }

                    let systemPrompt = self.loadPromptTemplate(for: platform)
                    let userText = """
                    위 \(images.count)장의 이미지는 \(platform == .leetcode ? "LeetCode" : "백준") 코딩 문제의 연속된 화면입니다.
                    풀이 언어: \(language.rawValue)

                    이미지를 순서대로 읽고 전체 문제를 파악하여 풀이 코드를 작성해주세요.
                    """

                    // 이미지 블록 + 텍스트 블록 합산
                    var contentBlocks: [[String: Any]] = imageBlocks
                    contentBlocks.append(["type": "text", "text": userText])

                    let body: [String: Any] = [
                        "model": self.modelID,
                        "max_tokens": self.maxTokens,
                        "stream": true,
                        "system": systemPrompt,
                        "messages": [
                            [
                                "role": "user",
                                "content": contentBlocks
                            ]
                        ]
                    ]

                    let bodyData = try JSONSerialization.data(withJSONObject: body)
                    var request = URLRequest(url: self.apiURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(self.apiVersion, forHTTPHeaderField: "anthropic-version")
                    request.httpBody = bodyData

                    let (asyncBytes, response) = try await self.session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw ClaudeAPIError.invalidResponse
                    }
                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in asyncBytes.lines { errorBody += line }
                        throw ClaudeAPIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
                    }

                    for try await line in asyncBytes.lines {
                        guard !Task.isCancelled else { continuation.finish(); return }
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))
                        guard jsonString != "[DONE]",
                              let jsonData = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                        else { continue }

                        switch json["type"] as? String ?? "" {
                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        case "message_stop":
                            continuation.finish(); return
                        case "error":
                            if let error = json["error"] as? [String: Any],
                               let message = error["message"] as? String {
                                throw ClaudeAPIError.apiError(message)
                            }
                        default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - 비스트리밍 (간편) 호출

    /// 스트리밍 없이 전체 응답을 한번에 받는다.
    func generateSolutionFull(
        for problem: ProblemModel,
        language: SolveLanguage
    ) async throws -> SolutionModel {
        var fullText = ""
        for try await chunk in generateSolution(for: problem, language: language) {
            fullText += chunk
        }

        let (code, explanation) = parseResponse(fullText)

        return SolutionModel(
            code: code,
            language: language,
            explanation: explanation,
            problem: problem
        )
    }

    // MARK: - 프롬프트 빌드

    private func buildPrompt(for problem: ProblemModel, language: SolveLanguage) -> String {
        let platformPrompt = loadPromptTemplate(for: problem.platform)

        var prompt = platformPrompt
        prompt += "\n\n## 문제 정보\n"
        prompt += "- 제목: \(problem.title)\n"
        prompt += "- 플랫폼: \(problem.platform.rawValue)\n"
        prompt += "- 풀이 언어: \(language.rawValue)\n\n"
        prompt += "## 문제 설명\n\(problem.description)\n\n"

        if !problem.inputCondition.isEmpty {
            prompt += "## 입력 조건\n\(problem.inputCondition)\n\n"
        }
        if !problem.outputCondition.isEmpty {
            prompt += "## 출력 조건\n\(problem.outputCondition)\n\n"
        }

        if !problem.examples.isEmpty {
            prompt += "## 예제\n"
            for (i, example) in problem.examples.enumerated() {
                prompt += "### 예제 \(i + 1)\n"
                prompt += "입력:\n```\n\(example.input)\n```\n"
                prompt += "출력:\n```\n\(example.output)\n```\n\n"
            }
        }

        return prompt
    }

    private func buildRequestBody(prompt: String) -> [String: Any] {
        [
            "model": modelID,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]
    }

    // MARK: - 프롬프트 템플릿 로드

    func loadPromptTemplate(for platform: Platform) -> String {
        guard let url = Bundle.main.url(forResource: "prompt", withExtension: "md", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return defaultPrompt(for: platform) // 번들 로드 실패 시 인라인 fallback
        }
        return content
    }

    private func defaultPrompt(for platform: Platform) -> String {
        // prompt.md 번들 로드 실패 시 사용하는 인라인 fallback
        return """
        You are a Competitive Programming Grandmaster. Solve the coding problem shown in the image.

        ## Algorithm Design
        1. Derive allowed complexity from constraints (N≤10⁶ → O(N log N), N≤10⁴ → O(N²), etc.)
        2. Select optimal algorithm and state why in one line.
        3. Check edge cases: N=1, N=max, empty input, negatives, overflow.
        4. Verify against all provided examples before writing code.

        ## Code Rules
        - If Baekjoon: complete standalone program, stdin/stdout, Python 3.7 uses input() and print() ONLY (no sys or other I/O), Java uses BufferedReader, C++ uses ios_base::sync_with_stdio(false)
        - If LeetCode: Solution class only, exact method signature, no main function

        ## Output Format
        ```(language)
        (complete solution — no omissions)
        ```
        Brief explanation with time/space complexity after the code block.
        """
    }

    // MARK: - 응답 파싱

    /// Claude 응답에서 코드 블록과 설명을 분리한다.
    private func parseResponse(_ text: String) -> (code: String, explanation: String) {
        return ResponseParser.parse(text)
    }
}

// MARK: - Errors

enum ClaudeAPIError: LocalizedError {
    case apiKeyNotFound
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyNotFound:
            return "Claude API 키가 설정되지 않았습니다. 설정에서 API 키를 입력해주세요."
        case .invalidResponse:
            return "서버 응답을 처리할 수 없습니다."
        case .httpError(let code, let body):
            return "HTTP 오류 \(code): \(body)"
        case .apiError(let message):
            return "Claude API 오류: \(message)"
        }
    }
}

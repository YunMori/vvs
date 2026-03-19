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
    ///   - language: 풀이 언어
    /// - Returns: 텍스트 청크를 순차적으로 방출하는 AsyncThrowingStream
    func generateSolutionFromImage(
        _ image: CGImage,
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

                    let systemPrompt = loadPromptTemplate()
                    let userText = """
                    위 이미지는 코딩 문제 화면입니다.
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

                    try await self.executeStreamingRequest(body: body, apiKey: apiKey, continuation: continuation)
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
    ///   - language: 풀이 언어
    /// - Returns: 텍스트 청크를 순차적으로 방출하는 AsyncThrowingStream
    func generateSolutionFromImages(
        _ images: [CGImage],
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

                    let systemPrompt = self.loadPromptTemplate()
                    let userText = """
                    위 \(images.count)장의 이미지는 코딩 문제의 연속된 화면입니다.
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

                    try await self.executeStreamingRequest(body: body, apiKey: apiKey, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - SSE 스트리밍 공통 처리

    /// API 요청을 실행하고 SSE 스트림을 파싱하여 텍스트 청크를 continuation으로 전달한다.
    private func executeStreamingRequest(
        body: [String: Any],
        apiKey: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData

        let (asyncBytes, response) = try await session.bytes(for: request)
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
    }

    // MARK: - 프롬프트 템플릿 로드

    func loadPromptTemplate() -> String {
        guard let url = Bundle.main.url(forResource: "prompt", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            print("[ClaudeAPIClient] ⚠️ prompt.md 번들 로드 실패 → fallback 프롬프트 사용")
            return defaultPrompt()
        }
        print("[ClaudeAPIClient] ✅ prompt.md 번들 로드 성공 (\(url.path))")
        return content
    }

    private func defaultPrompt() -> String {
        // prompt.md 번들 로드 실패 시 사용하는 인라인 fallback
        return """
        당신은 세계 최고 수준의 알고리즘 문제 해결(Competitive Programming) 전문가입니다. 당신의 목표는 단 한 번의 제출로 모든 테스트 케이스를 통과하는 무결점의 최적화된 코드를 작성하는 것입니다.

        아래의 엄격한 프로세스와 [절대 규칙]을 반드시 준수하여 코드를 작성하세요.

        ## 1단계 — 문제 완벽 파악
        제공된 이미지나 텍스트를 주의 깊게 분석하고 다음을 확인하세요:
        - 시간 제한 및 메모리 제한 (알고리즘 제약의 기준점)
        - 정확한 입출력 형식 및 타입
        - 모든 변수의 제약 조건 (N의 범위, 최댓값/최솟값 등)
        - 예제 테스트 케이스의 입출력 패턴

        ## 2단계 — 알고리즘 및 자료구조 설계
        1. **시간 복잡도 예산 산정**: 주어진 N의 제약 조건에 맞춰 허용되는 최대 시간 복잡도를 도출하세요.
        - N ≤ 10⁸ → O(N) 또는 O(N log N)
        - N ≤ 10⁶ → O(N log N)
        - N ≤ 10⁴ → O(N²)
        - N ≤ 500 → O(N³)
        2. **최적의 알고리즘 선택**: 산정된 예산 내에서 동작하는 가장 효율적인 알고리즘과 자료구조를 확정하세요.
        3. **엣지 케이스 검증**: N=1, 최댓값, 빈 입력, 음수, 자료형 오버플로우, 중복 데이터 등의 예외 상황을 설계에 반영하세요.

        ## 3단계 — 코드 작성 및 언어별 최적화
        문제의 요구 방식을 파악하고 알맞은 구조로만 작성하세요. 

        ### [중요] Python I/O 절대 규칙 (위반 시 오답 처리됨)
        - **`import sys` 사용을 엄격히 금지합니다.**
        - 입력은 반드시 파이썬 기본 내장 함수인 `input()`만을 사용해야 합니다. 
        - `sys.stdin.readline`, `sys.setrecursionlimit` 등 sys 모듈과 관련된 어떠한 코드도 절대 포함하지 마세요.
        - Python 버전은 3.7을 기준으로 작성합니다.

        ### A. 독립 실행 프로그램 (stdin/stdout 방식)
        - 모든 import(허용된 것만) 및 실행 진입점을 포함한 완전한 코드를 작성하세요.
        - **Java**: `BufferedReader`, `StringTokenizer`, `StringBuilder`를 사용하여 I/O 병목을 제거하세요.
        - **C++**: `main` 함수 최상단에 `ios_base::sync_with_stdio(false); cin.tie(NULL);`를 반드시 포함하세요.

        ### B. Solution 클래스 방식 (LeetCode, Programmers 등)
        - 문제에 제시된 메서드 시그니처를 그대로 가진 `Solution` 클래스만 작성하세요.
        - 테스트용 I/O 코드나 `main` 함수, 불필요한 import를 절대 포함하지 마세요.
        - **Java**: `Stack` 대신 `ArrayDeque`를 사용하고, 성능을 위해 래퍼 클래스(`Integer[]`) 대신 원시 타입(`int[]`)을 우선하세요.
        - **C++**: O(1) 조회를 위해 `std::map` 대신 `std::unordered_map` / `std::unordered_set`을 활용하세요.

        ## 4단계 — 최종 출력 형식 규칙
        - **주석 절대 금지**: 인라인 주석, 블록 주석, docstring 등 어떠한 형태의 설명도 코드 내에 쓰지 마세요.
        - 오직 실행 가능한 단일 코드 블록(```)만을 출력해야 합니다. 코드 블록 외부의 부연 설명도 생략하세요.

        """
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

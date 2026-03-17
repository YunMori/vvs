import Foundation

/// Claude API 응답에서 코드 블록과 설명을 추출하는 유틸리티
enum ResponseParser {
    /// 응답 전체 텍스트에서 첫 번째 코드 블록을 추출한다.
    /// - Returns: (code, explanation) 튜플. 코드 블록 없으면 전체 텍스트를 code로 반환.
    static func parse(_ text: String) -> (code: String, explanation: String) {
        let pattern = /```(?:\w+)?\s*\n([\s\S]*?)```/
        if let match = text.firstMatch(of: pattern) {
            let code = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            let afterCode = String(text[match.range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (code, afterCode)
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    /// 코드만 필요한 경우 사용
    static func extractCode(from text: String) -> String {
        parse(text).code
    }
}

import Foundation

// MARK: - Solve Language

enum SolveLanguage: String, CaseIterable, Sendable {
    case python = "Python"
    case java = "Java"
    case cpp = "C++"

    /// 파일 확장자
    var fileExtension: String {
        switch self {
        case .python: return "py"
        case .java: return "java"
        case .cpp: return "cpp"
        }
    }
}

// MARK: - Problem Model

struct ProblemModel: Sendable {
    let title: String
    let description: String
    let inputCondition: String
    let outputCondition: String
    let examples: [Example]

    struct Example: Sendable {
        let input: String
        let output: String
    }
}

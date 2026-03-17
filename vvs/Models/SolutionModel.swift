import Foundation

struct SolutionModel: Sendable {
    let code: String
    let language: SolveLanguage
    let explanation: String
    let problem: ProblemModel
}

import Foundation

/// 히스토리 저장에 사용되는 Codable 모델.
struct SolutionRecordDTO: Codable, Identifiable {
    let id: UUID
    var title: String
    var platform: String
    var language: String
    var code: String
    var createdAt: Date

    init(title: String, platform: String, language: String, code: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.platform = platform
        self.language = language
        self.code = code
        self.createdAt = createdAt
    }
}

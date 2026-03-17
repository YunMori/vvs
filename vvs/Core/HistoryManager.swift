import Foundation

/// 풀이 히스토리를 UserDefaults로 관리한다. 최대 20개 유지.
final class HistoryManager: @unchecked Sendable {

    static let shared = HistoryManager()

    private let maxRecords = 20
    private let storageKey = "SolutionHistory"

    private init() {}

    // MARK: - 저장

    func save(title: String, platform: String, language: String, code: String) {
        var records = loadAll()
        let dto = SolutionRecordDTO(
            title: title,
            platform: platform,
            language: language,
            code: code
        )
        records.insert(dto, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        persist(records)
    }

    // MARK: - 로드

    func loadAll() -> [SolutionRecordDTO] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([SolutionRecordDTO].self, from: data)) ?? []
    }

    // MARK: - 전체 삭제

    func deleteAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Private

    private func persist(_ records: [SolutionRecordDTO]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

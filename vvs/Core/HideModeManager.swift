import Foundation

// MARK: - App Visibility State

/// 앱의 가시성 상태를 나타낸다.
enum AppVisibilityState: String {
    case normal
    case perfectHide
}

// MARK: - UIGate

/// 모든 UI 표시 코드의 게이트.
/// Hide 모드에서는 모든 UI 표시를 차단한다.
struct UIGate {
    static var isAllowed: Bool {
        return !HideModeManager.shared.isPerfectHide
    }
}

// MARK: - LastSelectedWindowInfo

/// 자동 스캔용 마지막 선택 창 정보.
/// Hide 모드에서 WindowPicker 없이 이전에 선택한 창을 자동으로 찾는 데 사용된다.
struct LastSelectedWindowInfo: Codable {
    let bundleID: String
    let appName: String
    let windowTitle: String?
    let savedAt: Date
}

// MARK: - HideModeManager

/// Hide 모드 상태 관리 싱글톤.
/// UserDefaults를 통해 앱 재시작 시에도 상태를 유지한다.
final class HideModeManager {

    static let shared = HideModeManager()

    private let stateKey = "appVisibilityState"
    private let lastWindowKey = "lastSelectedWindowInfo"

    private init() {}

    // MARK: - 상태 관리

    /// 현재 앱 가시성 상태. UserDefaults에 영속화된다.
    var currentState: AppVisibilityState {
        get {
            if let raw = UserDefaults.standard.string(forKey: stateKey),
               let state = AppVisibilityState(rawValue: raw) {
                return state
            }
            return .normal
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: stateKey)
        }
    }

    /// 현재 완벽한 Hide 모드 여부
    var isPerfectHide: Bool {
        currentState == .perfectHide
    }

    // MARK: - 마지막 선택 창 정보

    /// 마지막으로 선택한 창 정보를 저장한다.
    func saveLastWindow(bundleID: String, appName: String, windowTitle: String?) {
        let info = LastSelectedWindowInfo(
            bundleID: bundleID,
            appName: appName,
            windowTitle: windowTitle,
            savedAt: Date()
        )

        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: lastWindowKey)
        }
    }

    /// 마지막으로 선택한 창 정보를 로드한다.
    func loadLastWindow() -> LastSelectedWindowInfo? {
        guard let data = UserDefaults.standard.data(forKey: lastWindowKey) else {
            return nil
        }
        return try? JSONDecoder().decode(LastSelectedWindowInfo.self, from: data)
    }
}

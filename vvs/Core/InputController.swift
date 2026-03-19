import AppKit
import Carbon.HIToolbox

// MARK: - TypingProfile

/// 타이핑 속도/패턴 프로파일. 자연스러운 자동 타이핑에 사용된다.
enum TypingProfile {
    case slow      // ~35 WPM, 노이즈 높음
    case average   // ~52 WPM
    case fast      // ~75 WPM
    case custom(wpm: Double, noiseRatio: Double, wordPauseMultiplier: Double)

    /// WPM (분당 단어 수)
    var wpm: Double {
        switch self {
        case .slow: return 35
        case .average: return 52
        case .fast: return 75
        case .custom(let wpm, _, _): return wpm
        }
    }

    /// 가우시안 노이즈 비율 (표준편차 = base * noiseRatio)
    var noiseRatio: Double {
        switch self {
        case .slow: return 0.35
        case .average: return 0.25
        case .fast: return 0.18
        case .custom(_, let noiseRatio, _): return noiseRatio
        }
    }

    /// 단어 경계 추가 지연 배율
    var wordPauseMultiplier: Double {
        switch self {
        case .slow: return 2.0
        case .average: return 1.7
        case .fast: return 1.5
        case .custom(_, _, let mult): return mult
        }
    }

    /// WPM 기준 스케일 팩터. average(52WPM) 기준 1.0
    var wpmScale: Double {
        52.0 / wpm
    }
}

// MARK: - Bigram IKI Table

/// 영어 알파벳 고빈도 bigram의 기준 지연 시간(ms).
/// 키보드 물리적 거리와 손가락 교대 패턴에 기반한 값이다.
private let bigramIKITable: [String: Double] = {
    var table: [String: Double] = [:]

    // 양손 교대 (80~110ms)
    let crossHand: [String: Double] = [
        "th": 85, "ht": 90, "he": 80, "eh": 95,
        "er": 90, "re": 88, "in": 95, "ni": 100,
        "on": 92, "no": 98, "an": 88, "na": 93,
        "it": 90, "ti": 95, "or": 85, "ro": 92,
        "at": 88, "ta": 95, "en": 90, "ne": 93,
        "is": 95, "si": 100, "ou": 92, "to": 85,
        "ot": 90, "ha": 88, "ah": 95, "al": 100,
        "la": 105, "le": 98, "el": 102, "ri": 95,
        "ir": 98, "ng": 105, "gn": 110,
    ]

    // 동일 손 다른 손가락 (120~160ms)
    let sameHand: [String: Double] = [
        "we": 125, "ew": 130, "ed": 120, "de": 128,
        "sd": 140, "ds": 145, "aw": 135, "wa": 130,
        "as": 132, "sa": 138, "fg": 150, "gf": 155,
        "rt": 125, "tr": 128, "ui": 130, "iu": 135,
        "op": 128, "po": 132, "qw": 145, "wq": 150,
        "df": 140, "fd": 145, "jk": 138, "kj": 142,
        "io": 130, "oi": 135, "kl": 135, "lk": 140,
        "gh": 148, "hg": 152, "ty": 132, "yt": 138,
        "yu": 135, "uy": 140, "cv": 145, "vc": 150,
        "bn": 148, "nb": 152, "pl": 140, "lp": 145,
        "se": 128, "es": 132, "sw": 138, "ws": 142,
    ]

    // 동일 손가락 반복 (180~250ms)
    let sameFinger: [String: Double] = [
        "ll": 190, "ss": 200, "ee": 185, "tt": 195,
        "nn": 200, "oo": 195, "rr": 210, "ff": 220,
        "cc": 215, "dd": 210, "gg": 225, "pp": 220,
        "mm": 215, "bb": 230, "aa": 200, "ii": 205,
        "uu": 210, "xx": 240, "vv": 235, "zz": 250,
        "yy": 230, "ww": 235, "hh": 225, "jj": 230,
        "kk": 235, "qq": 245,
        // 동일 손가락 다른 키 (수직 이동)
        "ec": 185, "ce": 190, "rv": 195, "vr": 200,
        "tf": 188, "ft": 192, "nu": 185, "un": 190,
        "my": 195, "ym": 200, "ij": 190, "ji": 195,
    ]

    for (k, v) in crossHand { table[k] = v }
    for (k, v) in sameHand { table[k] = v }
    for (k, v) in sameFinger { table[k] = v }

    return table
}()

/// bigram 기본 딜레이 (ms). 테이블에 없는 조합에 사용.
private let bigramDefaultIKI: Double = 130

/// CGEvent 기반 자동 타이핑 및 클립보드 관리 컨트롤러.
/// Accessibility 권한이 필요하며, 권한이 없으면 클립보드 모드로 자동 폴백한다.
@MainActor
final class InputController {

    static let shared = InputController()

    /// 타이핑 중단 플래그. ESC 키 감지 시 true로 설정된다.
    private(set) var isCancelled = false

    /// ESC 키 로컬 모니터
    private var escMonitor: Any?

    /// ESC 키 글로벌 모니터 (앱 비활성 상태용)
    private var escGlobalMonitor: Any?

    private init() {}

    // MARK: - Accessibility 권한 확인

    /// Accessibility 권한이 부여되었는지 확인한다.
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Accessibility 권한을 요청한다. 시스템 설정 다이얼로그가 표시된다.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 자동 타이핑

    /// 현재 커서 위치에 한 글자씩 텍스트를 입력한다.
    /// Accessibility 권한이 없으면 클립보드에 복사하고 false를 반환한다.
    /// - Parameters:
    ///   - text: 입력할 텍스트
    ///   - delay: 글자 간 딜레이 (기본 0.01초). 0.01이면 자연 타이핑 모드 사용.
    ///   - profile: 자연 타이핑 프로파일 (delay가 0.01일 때만 적용)
    /// - Returns: 자동 타이핑 성공 여부. false이면 클립보드 폴백이 사용됨.
    @discardableResult
    func typeText(_ text: String, delay: TimeInterval = 0.01, isHumanLike: Bool = true, profile: TypingProfile = .average) async -> Bool {
        // 권한 없으면 클립보드 폴백
        guard hasAccessibilityPermission else {
            copyToClipboard(text)
            return false
        }

        isCancelled = false
        startESCMonitor()

        defer {
            stopESCMonitor()
        }

        let source = CGEventSource(stateID: .hidSystemState)
        var prevChar: Character? = nil
        let isTypoEnabled = UserDefaults.standard.bool(forKey: AppSettings.typoSimulationEnabled)

        for character in text {
            guard !isCancelled else {
                break
            }

            if character == "\n" {
                postKeyEvent(keyCode: UInt16(kVK_Return), source: source)
            } else if character == "\t" {
                postKeyEvent(keyCode: UInt16(kVK_Tab), source: source)
            } else {
                // 오타 시뮬레이션
                if isTypoEnabled && character.isLetter && Double.random(in: 0..<1) < 0.012 {
                    if let wrongChar = adjacentKey(for: character) {
                        typeCharacter(wrongChar, source: source)
                        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.08...0.2) * 1_000_000_000))
                        postKeyEvent(keyCode: UInt16(kVK_Delete), source: source)
                        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.05...0.12) * 1_000_000_000))
                    }
                }
                typeCharacter(character, source: source)
            }

            // 딜레이
            if isHumanLike {
                let interval = naturalDelay(prev: prevChar, current: character, profile: profile)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } else {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            prevChar = character
        }

        return !isCancelled
    }

    // MARK: - Natural Typing Delay

    /// 이전/현재 문자 bigram과 프로파일을 기반으로 자연스러운 딜레이를 계산한다.
    /// - Parameters:
    ///   - prev: 직전에 입력된 문자 (nil이면 첫 문자)
    ///   - current: 현재 입력할 문자
    ///   - profile: 타이핑 프로파일
    /// - Returns: 딜레이 (초 단위, TimeInterval)
    private nonisolated func naturalDelay(prev: Character?, current: Character, profile: TypingProfile) -> TimeInterval {
        // 1) bigram IKI 조회 (ms)
        var baseMs = bigramDefaultIKI
        if let p = prev {
            let key = String(p).lowercased() + String(current).lowercased()
            if let iki = bigramIKITable[key] {
                baseMs = iki
            }
        }

        // 1.5) 코드 특수문자 맥락 딜레이 (bigram 미적중 시 문자 유형별 기준값 적용)
        if prev == nil || bigramIKITable[String(prev!).lowercased() + String(current).lowercased()] == nil {
            switch current {
            case "{", "}":
                baseMs = 180
            case "(", ")":
                baseMs = 155
            case "[", "]":
                baseMs = 160
            case ";", ":":
                baseMs = 145
            case ",", ".":
                baseMs = 140
            case "=", "!", "|", "&":
                baseMs = 150
            case "<", ">":
                baseMs = 158
            default:
                break
            }
        }

        // 2) WPM 스케일링
        baseMs *= profile.wpmScale

        // 3) 단어 경계: 공백, 줄바꿈이면 추가 지연
        if current == " " || current == "\n" || current == "\t" {
            let pauseMultiplier = Double.random(in: 1.5...profile.wordPauseMultiplier)
            baseMs *= pauseMultiplier
        }

        // 4) 5% 확률 "멈칫" (hesitation)
        if Double.random(in: 0..<1) < 0.05 {
            baseMs *= Double.random(in: 2.0...4.0)
        }

        // 5) 가우시안 노이즈 (Box-Muller 변환)
        let u1 = max(Double.random(in: 0..<1), 1e-10) // log(0) 방지
        let u2 = Double.random(in: 0..<1)
        let gaussian = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
        let noise = gaussian * baseMs * profile.noiseRatio
        baseMs += noise

        // 6) 클램핑: 최소 base의 30%, 최대 2000ms
        let minMs = bigramDefaultIKI * profile.wpmScale * 0.3
        baseMs = max(baseMs, minMs)
        baseMs = min(baseMs, 2000.0)

        // ms → 초 변환
        return baseMs / 1000.0
    }

    // MARK: - 클립보드 복사

    /// 텍스트를 클립보드에 복사한다.
    /// - Parameter text: 복사할 텍스트
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Private: 키 이벤트 발생

    /// 특정 keyCode로 keyDown/keyUp 이벤트를 발생시킨다.
    private func postKeyEvent(keyCode: UInt16, source: CGEventSource?, flags: CGEventFlags = []) {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// UniChar 기반으로 단일 문자를 입력한다.
    private func typeCharacter(_ char: Character, source: CGEventSource?) {
        let utf16 = Array(String(char).utf16)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// QWERTY 키보드 기준 인접 키를 랜덤 반환. 알파벳 이외 문자는 nil 반환.
    private nonisolated func adjacentKey(for char: Character) -> Character? {
        let adjacentKeys: [Character: [Character]] = [
            "q": ["w","a","s"], "w": ["q","e","a","s","d"], "e": ["w","r","s","d","f"],
            "r": ["e","t","d","f","g"], "t": ["r","y","f","g","h"], "y": ["t","u","g","h","j"],
            "u": ["y","i","h","j","k"], "i": ["u","o","j","k","l"], "o": ["i","p","k","l"],
            "p": ["o","l"],
            "a": ["q","w","s","z"], "s": ["a","w","e","d","z","x"], "d": ["s","e","r","f","x","c"],
            "f": ["d","r","t","g","c","v"], "g": ["f","t","y","h","v","b"], "h": ["g","y","u","j","b","n"],
            "j": ["h","u","i","k","n","m"], "k": ["j","i","o","l","m"], "l": ["k","o","p"],
            "z": ["a","s","x"], "x": ["z","s","d","c"], "c": ["x","d","f","v"],
            "v": ["c","f","g","b"], "b": ["v","g","h","n"], "n": ["b","h","j","m"],
            "m": ["n","j","k"]
        ]
        let lower = Character(char.lowercased())
        guard let neighbors = adjacentKeys[lower], !neighbors.isEmpty else { return nil }
        let picked = neighbors.randomElement()!
        return char.isUppercase ? Character(picked.uppercased()) : picked
    }

    // MARK: - ESC 키 모니터

    /// ESC 키 감지 모니터를 시작한다. 타이핑 중 ESC를 누르면 즉시 중단된다.
    private func startESCMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.isCancelled = true
                return nil // 이벤트 소비
            }
            return event
        }

        // 글로벌 모니터도 추가 (앱이 비활성 상태일 때) - 참조 보관하여 누수 방지
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.isCancelled = true
            }
        }
    }

    /// ESC 키 모니터를 중지한다.
    private func stopESCMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
        if let monitor = escGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            escGlobalMonitor = nil
        }
    }
}

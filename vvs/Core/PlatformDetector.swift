import Foundation
import ScreenCaptureKit

/// 창 이름 및 앱 이름 패턴 매칭으로 코딩 플랫폼을 감지한다.
struct PlatformDetector {

    /// SCWindow의 title과 owningApplication 정보를 분석하여 Platform을 반환한다.
    static func detect(from window: SCWindow) -> Platform {
        let windowTitle = window.title?.lowercased() ?? ""
        let _ = window.owningApplication?.applicationName.lowercased() ?? ""
        let bundleID = window.owningApplication?.bundleIdentifier.lowercased() ?? ""

        // 브라우저 기반 판별: 창 제목에 URL 패턴이 포함되어 있는지 확인
        if windowTitle.contains("acmicpc.net") || windowTitle.contains("백준") {
            return .baekjoon
        }

        if windowTitle.contains("leetcode.com") || windowTitle.contains("leetcode") {
            return .leetcode
        }

        // VDI 환경 감지 (VMware, Citrix, Microsoft Remote Desktop 등)
        let vdiIdentifiers = [
            "com.vmware.horizon",
            "com.citrix.receiver",
            "com.citrix.XenAppViewer",
            "com.microsoft.rdc",
            "com.microsoft.rdc.macos",
            "com.parallels.desktop",
        ]
        if vdiIdentifiers.contains(where: { bundleID.contains($0.lowercased()) }) {
            return .vdi
        }

        return .unknown
    }

    /// 복수의 SCWindow에서 가장 유력한 코딩 플랫폼 창을 찾는다.
    static func detectBestMatch(from windows: [SCWindow]) -> (window: SCWindow, platform: Platform)? {
        for window in windows {
            let platform = detect(from: window)
            if platform != .unknown {
                return (window, platform)
            }
        }
        return nil
    }
}

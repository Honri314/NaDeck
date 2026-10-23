import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// 앱 내 업데이트 확인/다운로드 지원.
/// 서버의 releases/VERSION 파일(예: "1.1.0")과 현재 앱 빌드 버전을 비교한다.
enum AppUpdate {
    static let releasesBase = "https://ubuntu.tail543772.ts.net/nadeck/releases"

    static var currentVersion: String {
        #if canImport(AppKit)
        if let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !ver.isEmpty {
            return ver
        }
        #endif
        return "1.0.0"
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
        }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    struct CheckResult {
        let latest: String
    }

    /// releases/VERSION 파일을 확인해 (최신버전, 존재여부) 반환. 오류는 throws로 전달.
    static func checkLatest() async throws -> String {
        guard let url = URL(string: releasesBase + "/VERSION") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.contains("."), cleaned.count <= 32,
              cleaned.allSatisfy({ $0.isNumber || $0 == "." }) else {
            throw URLError(.cannotParseResponse)
        }
        return cleaned
    }

    #if canImport(AppKit)
    /// DMG 다운로드 페이지(서버 /nadeck/)를 기본 브라우저로 연다.
    static func openDownloadPage() {
        guard let url = URL(string: "https://ubuntu.tail543772.ts.net/nadeck/") else { return }
        NSWorkspace.shared.open(url)
    }
    #endif
}

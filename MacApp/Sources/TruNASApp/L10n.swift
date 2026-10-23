import Foundation

// MARK: - 언어 설정 / 현지화

enum AppLanguage {
    static let korean = "ko"
    static let english = "en"
    private static let key = "truenas.language.v1"

    static var current: String {
        get {
            UserDefaults.standard.string(forKey: key) ?? korean
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }

    static var isEnglish: Bool { current == english }
}

/// UI 문구 선택: 한국어가 기본이고, 설정에서 English 선택 시 영어로 표시
func T(_ korean: String, _ english: String) -> String {
    AppLanguage.isEnglish ? english : korean
}

/// TrueNAS에서 반환하는 내부(Python) 오류 문구를 쉬운 한국어로 안내
func errMessage(_ ko: String, _ en: String, _ detail: String = "") -> String {
    let base = AppLanguage.isEnglish ? en : ko
    return detail.isEmpty ? base : "\(base)\n(\(detail))"
}

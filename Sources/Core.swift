import UIKit
import CryptoKit

// MARK: - 配置

enum AppConfig {
    static let site = "https://123av.com"
    static let rec = "https://rec2.123av.com"
    static let recKey = "e8bcc533-bc38-4a33-af0e-678d38237754"
    static let cdn = "https://icdn.123av.me"
    static let locale = "zh-CN"
    static let urlLocale = "cn"

    /// 必须与请求头 UA 完全一致（rec2 的签名把 UA 算进去了）
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// 本机用户标识（推荐服务用，随便给个 UUID 即可）
    static var userId: String {
        let key = "user.id"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    static let coverWidth = "s360"
}

// MARK: - 模型

struct VideoItem: Hashable {
    let code: String
    let title: String
    let duration: String
    var coverURL: URL?
    var views: String = ""
    var rank: Int?
    var recommID: String?

    init(code: String, title: String, duration: String = "", cover: String = "", views: String = "", rank: Int? = nil) {
        let lower = code.lowercased()
        self.code = lower
        self.title = title.isEmpty ? code.uppercased() : title
        self.duration = duration
        self.views = views
        self.rank = rank
        if cover.isEmpty {
            self.coverURL = URL(string: "\(AppConfig.cdn)/img2/\(AppConfig.coverWidth)/\(MD5.prefix2(of: lower))/\(lower)/cover.jpg")
        } else {
            self.coverURL = URL(string: cover)
        }
    }
}

struct Genre: Hashable {
    let slug: String
    let name: String
    var count: Int = 0
}

struct Episode {
    let name: String
    let url: URL
}

struct VideoDetail {
    var code: String = ""
    var title: String = ""
    var poster: URL?
    var stats: [String] = []
    var info: [(String, String)] = []
    var genres: [Genre] = []
    var episodes: [Episode] = []
    var recBase: String = ""
    var recKey: String = ""
}

// MARK: - 工具

enum MD5 {
    static func prefix2(of text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(2))
    }
}

enum Fmt {
    /// 秒 → 1:23:45 / 23:45
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// "6668" → 1:51:08
    static func duration(fromSecondsString value: String) -> String {
        guard let seconds = Double(value) else { return value }
        return duration(seconds)
    }
}

enum Store {
    static let watchKey = "recent.watch"

    static func recent() -> [VideoItem] {
        guard let raw = UserDefaults.standard.array(forKey: watchKey) as? [[String: String]] else { return [] }
        return raw.compactMap { dict in
            guard let code = dict["code"] else { return nil }
            return VideoItem(code: code, title: dict["title"] ?? code, duration: dict["duration"] ?? "", cover: dict["cover"] ?? "")
        }
    }

    static func addRecent(_ item: VideoItem) {
        var list = recent().filter { $0.code != item.code }
        list.insert(item, at: 0)
        list = Array(list.prefix(20))
        let raw: [[String: String]] = list.map {
            ["code": $0.code, "title": $0.title, "duration": $0.duration, "cover": $0.coverURL?.absoluteString ?? ""]
        }
        UserDefaults.standard.set(raw, forKey: watchKey)
    }

    static func clearRecent() {
        UserDefaults.standard.removeObject(forKey: watchKey)
    }
}

// MARK: - 主题

enum ThemeMode: String {
    case system, light, dark

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class ThemeManager {
    static let shared = ThemeManager()
    private let key = "appearance.mode"

    private(set) var mode: ThemeMode = .system

    private init() {
        if let raw = UserDefaults.standard.string(forKey: key), let saved = ThemeMode(rawValue: raw) {
            mode = saved
        }
    }

    func set(_ newMode: ThemeMode) {
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: key)
        apply()
    }

    func cycle() -> ThemeMode {
        switch mode {
        case .system: set(.light)
        case .light: set(.dark)
        case .dark: set(.system)
        }
        return mode
    }

    func apply() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = mode.interfaceStyle
            }
        }
    }
}

enum Palette {
    static var background: UIColor { UIColor { trait in
        trait.userInterfaceStyle == .light ? UIColor(red: 0.96, green: 0.965, blue: 0.973, alpha: 1)
                                           : UIColor(red: 0.055, green: 0.059, blue: 0.067, alpha: 1)
    } }

    static var surface: UIColor { UIColor { trait in
        trait.userInterfaceStyle == .light ? .white
                                           : UIColor(red: 0.106, green: 0.114, blue: 0.129, alpha: 1)
    } }

    static var surfaceAlt: UIColor { UIColor { trait in
        trait.userInterfaceStyle == .light ? UIColor(red: 0.925, green: 0.933, blue: 0.945, alpha: 1)
                                           : UIColor(red: 0.129, green: 0.137, blue: 0.157, alpha: 1)
    } }

    static var separator: UIColor { UIColor { trait in
        trait.userInterfaceStyle == .light ? UIColor(red: 0.886, green: 0.898, blue: 0.914, alpha: 1)
                                           : UIColor(red: 0.165, green: 0.176, blue: 0.2, alpha: 1)
    } }

    static var text: UIColor { UIColor { trait in
        trait.userInterfaceStyle == .light ? UIColor(red: 0.09, green: 0.1, blue: 0.12, alpha: 1)
                                           : UIColor(red: 0.953, green: 0.957, blue: 0.965, alpha: 1)
    } }

    static var secondaryText: UIColor { UIColor { trait in
        trait.userInterfaceStyle == .light ? UIColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1)
                                           : UIColor(red: 0.6, green: 0.63, blue: 0.68, alpha: 1)
    } }

    static let accent = UIColor(red: 0.909, green: 0.243, blue: 0.549, alpha: 1)
}

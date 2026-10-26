import Foundation

// MARK: - 正则小工具

enum Regex {
    /// 返回所有匹配，每项是 [整体, 分组1, 分组2…]
    static func all(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        return re.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let r = match.range(at: index)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    static func first(_ pattern: String, in text: String) -> [String]? {
        return all(pattern, in: text).first
    }

    static func capture(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let match = first(pattern, in: text), match.count > group else { return nil }
        let value = match[group]
        return value.isEmpty ? nil : value
    }
}

// MARK: - HTML 解析

enum HTMLParser {

    static func strip(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (key, value) in entities {
            text = text.replacingOccurrences(of: key, with: value)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
            var mutable = text
            for match in matches {
                let digits = ns.substring(with: match.range(at: 1))
                if let code = UInt32(digits), let scalar = Unicode.Scalar(code) {
                    let full = ns.substring(with: match.range)
                    mutable = mutable.replacingOccurrences(of: full, with: String(Character(scalar)))
                }
            }
            text = mutable
        }
        return text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 解析 JS 字符串转义（\u0022 之类）
    static func unescape(_ raw: String) -> String {
        var output = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let ch = raw[index]
            if ch != "\\" {
                output.append(ch)
                index = raw.index(after: index)
                continue
            }
            let next = raw.index(after: index)
            guard next < raw.endIndex else { break }
            let marker = raw[next]
            switch marker {
            case "u":
                let end = raw.index(next, offsetBy: 5, limitedBy: raw.endIndex) ?? raw.endIndex
                let hex = String(raw[raw.index(after: next)..<end])
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
                    output.append(Character(scalar))
                    index = end
                } else {
                    output.append(marker)
                    index = raw.index(after: next)
                }
            case "n": output.append("\n"); index = raw.index(after: next)
            case "t": output.append("\t"); index = raw.index(after: next)
            case "r": output.append("\r"); index = raw.index(after: next)
            default: output.append(marker); index = raw.index(after: next)
            }
        }
        return output
    }

    /// 列表页的卡片
    static func cards(from html: String) -> [VideoItem] {
        var items: [VideoItem] = []
        var seen = Set<String>()
        for part in html.components(separatedBy: "<div class=\"card\"").dropFirst() {
            guard let code = Regex.capture("href=\"/cn/v/([^\"#?]+)\"", in: part) else { continue }
            if seen.contains(code) { continue }
            seen.insert(code)

            let image = Regex.capture("class=\"card__img\"[^>]*src=\"([^\"]+)\"", in: part) ?? ""
            let duration = (Regex.capture("class=\"card__dur\">([^<]*)<", in: part) ?? "")
                .trimmingCharacters(in: .whitespaces)
            let rawTitle = Regex.capture("class=\"card__link\"[^>]*>(.*?)</a>", in: part) ?? code
            var views = ""
            if let rawViews = Regex.capture("class=\"card__views\"[^>]*>.*?</svg>([^<]{0,24})", in: part) {
                views = strip(rawViews)
            }

            items.append(VideoItem(code: code,
                                   title: strip(rawTitle),
                                   duration: duration,
                                   cover: image,
                                   views: views))
        }
        return items
    }

    /// 分类索引页：slug + 中文名 + 影片数
    static func genres(from html: String) -> [Genre] {
        var result: [Genre] = []
        var seen = Set<String>()
        let pattern = "<a[^>]+href=\"/cn/genres/([^\"?#]+)\"[^>]*>(.{0,120}?)</a>"
        for match in Regex.all(pattern, in: html) where match.count > 2 {
            let slug = match[1]
            if seen.contains(slug) { continue }
            let raw = strip(match[2])
            if raw.isEmpty { continue }

            var name = raw
            var count = 0
            if let range = raw.range(of: "[0-9][0-9,]*$", options: .regularExpression) {
                name = String(raw[raw.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                count = Int(raw[range].replacingOccurrences(of: ",", with: "")) ?? 0
            }
            if name.isEmpty || name.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil {
                continue
            }
            seen.insert(slug)
            result.append(Genre(slug: slug, name: name, count: count))
        }
        return result
    }

    /// 详情页
    static func detail(from html: String, code: String) -> VideoDetail {
        var detail = VideoDetail()
        detail.code = code.uppercased()

        if let title = Regex.capture("<h1 class=\"watch__title\">(.*?)</h1>", in: html) {
            detail.title = strip(title)
        }

        if let poster = Regex.capture("class=\"player\"[^>]*background-image:url\\('([^']+)'\\)", in: html),
           let url = URL(string: poster) {
            detail.poster = url
        }

        for match in Regex.all("class=\"watch__metaitem\"[^>]*>.*?</svg>([^<]{0,40})", in: html) where match.count > 1 {
            let text = strip(match[1])
            if !text.isEmpty { detail.stats.append(text) }
        }

        for match in Regex.all("<div class=\"watch__info-row\">\\s*<dt>([^<]*)</dt>\\s*<dd[^>]*>(.*?)</dd>", in: html)
        where match.count > 2 {
            let key = strip(match[1])
            let value = strip(match[2])
            if !key.isEmpty && !value.isEmpty {
                detail.info.append((key, value))
            }
        }

        for match in Regex.all("<a class=\"chip\" href=\"/cn/genres/([^\"]+)\"[^>]*>(.*?)</a>", in: html)
        where match.count > 2 {
            detail.genres.append(Genre(slug: match[1], name: strip(match[2])))
        }

        if let raw = Regex.capture("player\\(JSON\\.parse\\('((?:[^'\\\\]|\\\\.)*)'\\)", in: html) {
            let json = unescape(raw)
            if let data = json.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for dict in array {
                    guard let urlString = dict["url"] as? String, let url = URL(string: urlString) else { continue }
                    let name = (dict["name"] as? String) ?? ""
                    detail.episodes.append(Episode(name: name, url: url))
                }
            }
        }

        if let recBase = Regex.capture("player\\(JSON\\.parse\\('(?:[^'\\\\]|\\\\.)*'\\),\\s*\\d+,\\s*'[^']*',\\s*'([^']*)'", in: html) {
            detail.recBase = recBase.replacingOccurrences(of: "\\/", with: "/")
        }
        if let recKey = Regex.capture("player\\(JSON\\.parse\\('(?:[^'\\\\]|\\\\.)*'\\),\\s*\\d+,\\s*'[^']*',\\s*'[^']*',\\s*'([^']*)'", in: html) {
            detail.recKey = recKey
        }

        return detail
    }
}

// MARK: - 接口

final class APIClient {

    static let shared = APIClient()

    private let session: URLSession
    private let queue = DispatchQueue(label: "api.client")

    private var labelsCache: [String: String]?
    private var genresCache: [Genre]?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    // MARK: 基础请求

    private func request(_ url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://123av.com/", forHTTPHeaderField: "Referer")
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func text(_ urlString: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        session.dataTask(with: request(url)) { data, _, error in
            guard error == nil, let data = data else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { completion(text) }
        }.resume()
    }

    // MARK: 推荐服务（带签名）

    private func simpleHash(_ input: String) -> String {
        var hash: Int32 = 0
        for scalar in input.unicodeScalars {
            hash = (hash &<< 5) &- hash &+ Int32(truncatingIfNeeded: scalar.value)
            hash = Int32(truncatingIfNeeded: hash)
        }
        return String(UInt32(bitPattern: hash), radix: 16)
    }

    private func signedURL(_ path: String) -> URL? {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signature = simpleHash(AppConfig.recKey + timestamp + AppConfig.userAgent)
        return URL(string: "\(AppConfig.rec)\(path)?timestamp=\(timestamp)&signature=\(signature)")
    }

    private func recPost(_ path: String, body: [String: Any], completion: @escaping ([String: Any]?) -> Void) {
        guard let url = signedURL(path),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil)
            return
        }
        session.dataTask(with: request(url, method: "POST", body: data)) { payload, _, error in
            guard error == nil, let payload = payload,
                  let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(json) }
        }.resume()
    }

    private func mapItems(_ json: [String: Any]?) -> ([VideoItem], String?) {
        guard let json = json,
              let list = json["recomms"] as? [[String: Any]] else {
            return ([], nil)
        }
        let items = list.compactMap { dict -> VideoItem? in
            guard let code = dict["code"] as? String else { return nil }
            let title = (dict["title_cn"] as? String) ?? (dict["title_en"] as? String) ?? code
            let duration = Fmt.duration(fromSecondsString: (dict["duration"] as? String) ?? "")
            return VideoItem(code: code, title: title, duration: duration)
        }
        return (items, json["recomm_id"] as? String)
    }

    private var itemProperties: [String] { ["code", "title_cn", "duration"] }

    func recommendations(count: Int = 18, completion: @escaping ([VideoItem]) -> Void) {
        let path = "/users/\(AppConfig.userId)/items"
        let body: [String: Any] = [
            "count": count,
            "scenario": "home-recommended",
            "included_properties": itemProperties
        ]
        recPost(path, body: body) { json in
            completion(self.mapItems(json).0)
        }
    }

    func segments(completion: @escaping ([String]) -> Void) {
        let path = "/users/\(AppConfig.userId)/segments"
        recPost(path, body: ["count": 3]) { json in
            let list = (json?["recomms"] as? [String]) ?? []
            completion(list)
        }
    }

    func items(genre: String, count: Int = 24, completion: @escaping ([VideoItem], String?) -> Void) {
        let path = "/users/\(AppConfig.userId)/items"
        let body: [String: Any] = [
            "count": count,
            "scenario": "home-segments-items",
            "genre": genre,
            "included_properties": itemProperties
        ]
        recPost(path, body: body) { json in
            let result = self.mapItems(json)
            completion(result.0, result.1)
        }
    }

    func nextItems(recommID: String, count: Int = 24, completion: @escaping ([VideoItem], String?) -> Void) {
        let path = "/next/items/\(recommID)"
        recPost(path, body: ["count": count]) { json in
            let result = self.mapItems(json)
            completion(result.0, result.1)
        }
    }

    func similar(code: String, count: Int = 12, completion: @escaping ([VideoItem]) -> Void) {
        let path = "/items/\(code.lowercased())/items"
        let body: [String: Any] = [
            "count": count,
            "target_user": AppConfig.userId,
            "included_properties": itemProperties
        ]
        recPost(path, body: body) { json in
            completion(self.mapItems(json).0)
        }
    }

    // MARK: 站点接口 / 页面

    func genreLabels(completion: @escaping ([String: String]) -> Void) {
        if let cached = labelsCache {
            completion(cached)
            return
        }
        let url = "\(AppConfig.site)/api/v1/genre-labels?locale=\(AppConfig.locale)"
        text(url) { raw in
            let map = (raw.flatMap { $0.data(using: .utf8) })
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
            self.labelsCache = map
            completion(map)
        }
    }

    func allGenres(completion: @escaping ([Genre]) -> Void) {
        if let cached = genresCache {
            completion(cached)
            return
        }
        text("\(AppConfig.site)/cn/genres") { raw in
            let list = raw.map { HTMLParser.genres(from: $0).sorted { $0.count > $1.count } } ?? []
            self.genresCache = list
            completion(list)
        }
    }

    func genrePage(slug: String, page: Int, completion: @escaping ([VideoItem]) -> Void) {
        let escaped = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        let url = "\(AppConfig.site)/cn/genres/\(escaped)?page=\(page)"
        text(url) { raw in
            completion(raw.map { HTMLParser.cards(from: $0) } ?? [])
        }
    }

    func listPage(path: String, page: Int, completion: @escaping ([VideoItem]) -> Void) {
        let separator = path.contains("?") ? "&" : "?"
        let url = "\(AppConfig.site)\(path)\(separator)page=\(page)"
        text(url) { raw in
            completion(raw.map { HTMLParser.cards(from: $0) } ?? [])
        }
    }

    func search(keyword: String, page: Int, completion: @escaping ([VideoItem]) -> Void) {
        let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        text("\(AppConfig.site)/cn/search?keyword=\(escaped)&page=\(page)") { raw in
            completion(raw.map { HTMLParser.cards(from: $0) } ?? [])
        }
    }

    func detail(code: String, completion: @escaping (VideoDetail?) -> Void) {
        let escaped = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        text("\(AppConfig.site)/cn/v/\(escaped)") { raw in
            guard let raw = raw, raw.contains("watch__title") else {
                completion(nil)
                return
            }
            completion(HTMLParser.detail(from: raw, code: code))
        }
    }
}

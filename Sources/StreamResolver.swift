import Foundation

/// 把站点 embed 播放页解析成真正的 HLS 直链。
///
/// embed 页（https://sadie-shop.site/e/{id}?poster=…）里的 JS 会请求：
///   GET {origin}/stream?{embed 的所有 query}&id={id}
///   → {"status":"ok","media":{"stream":"https://…/video.m3u8","vtt":"…"}}
/// 拿到 m3u8 后交给 LocalHLSProxy（本地 HTTP 代理，负责补 Referer 与改写播放列表）再喂给 AVPlayer。
enum StreamResolver {

    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    enum ResolveError: LocalizedError {
        case badEmbedURL
        case badResponse
        case noStream

        var errorDescription: String? {
            switch self {
            case .badEmbedURL: return "播放地址无效"
            case .badResponse: return "取流失败"
            case .noStream: return "没有可用的播放源"
            }
        }
    }

    /// 由 embed 地址推导 /stream 接口地址
    static func streamEndpoint(for embedURL: URL) -> URL? {
        guard let comps = URLComponents(url: embedURL, resolvingAgainstBaseURL: false) else { return nil }
        let id = embedURL.pathComponents.last(where: { $0 != "/" && !$0.isEmpty })
        guard let hashId = id else { return nil }

        var query = comps.queryItems ?? []
        query.removeAll { $0.name == "id" }
        query.append(URLQueryItem(name: "id", value: hashId))

        var out = URLComponents()
        out.scheme = comps.scheme
        out.host = comps.host
        out.port = comps.port
        out.path = "/stream"
        out.queryItems = query
        return out.url
    }

    /// 解析出 m3u8 地址
    static func resolve(embedURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let endpoint = streamEndpoint(for: embedURL) else {
            completion(.failure(ResolveError.badEmbedURL))
            return
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(embedURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("application/json, */*;q=0.8", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let media = json["media"] as? [String: Any],
                  let stream = media["stream"] as? String,
                  let url = URL(string: stream) else {
                DispatchQueue.main.async { completion(.failure(ResolveError.noStream)) }
                return
            }
            DispatchQueue.main.async { completion(.success(url)) }
        }.resume()
    }
}

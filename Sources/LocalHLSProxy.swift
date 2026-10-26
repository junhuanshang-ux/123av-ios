import Foundation
import Network

/// App 内置的本地 HLS 代理。
///
/// 为什么不用 AVAssetResourceLoader：它在 HLS 场景下并不可靠（播放列表/分片经常根本不进代理），
/// 实测就是"点了不播"。这里改成业界通行的做法：在 127.0.0.1 起一个极小 HTTP 服务，
/// AVPlayer 播放 `http://127.0.0.1:<port>/p?r=<referer>&u=<目标>`，
/// 由代理去上游取数据（补 Referer/UA），并把播放列表里的相对地址改写成代理地址。
final class LocalHLSProxy {

    static let shared = LocalHLSProxy()

    private let queue = DispatchQueue(label: "com.yidian.hlsproxy")
    private let urlSession: URLSession
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var started = false

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlSession = URLSession(configuration: cfg)
    }

    // MARK: - 生命周期

    /// 启动代理，返回监听端口（0 表示启动失败）
    @discardableResult
    func startIfNeeded() -> UInt16 {
        if started { return port }
        started = true

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .loopback

            let listener = try NWListener(using: params, on: .any)
            let semaphore = DispatchSemaphore(value: 0)

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let p = listener.port { self?.port = p.rawValue }
                    semaphore.signal()
                case .failed, .cancelled:
                    semaphore.signal()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
            _ = semaphore.wait(timeout: .now() + 3)
        } catch {
            self.port = 0
        }
        return port
    }

    func stop() {
        listener?.cancel()
        listener = nil
        started = false
        port = 0
    }

    // MARK: - 地址编解码

    static func encode(_ string: String) -> String {
        Data(string.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> String? {
        var value = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        guard let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 上游地址 → 本地代理地址
    func localURL(for remote: URL, referer: String) -> URL? {
        guard port > 0 else { return nil }
        let u = LocalHLSProxy.encode(remote.absoluteString)
        let r = LocalHLSProxy.encode(referer)
        return URL(string: "http://127.0.0.1:\(port)/p?r=\(r)&u=\(u)")
    }

    // MARK: - 连接处理

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receive(connection, accumulated: Data())
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buffer = accumulated
            if let data = data { buffer.append(data) }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                self.handle(head, connection: connection)
                return
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receive(connection, accumulated: buffer)
        }
    }

    private func handle(_ head: String, connection: NWConnection) {
        guard let requestLine = head.components(separatedBy: "\r\n").first else {
            respond(connection, status: 400, body: Data())
            return
        }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: parts[1]) else {
            respond(connection, status: 400, body: Data())
            return
        }

        let items = components.queryItems ?? []
        let refererEncoded = items.first(where: { $0.name == "r" })?.value ?? ""
        let targetEncoded = items.first(where: { $0.name == "u" })?.value ?? ""
        let referer = LocalHLSProxy.decode(refererEncoded) ?? ""

        guard let targetString = LocalHLSProxy.decode(targetEncoded),
              let target = URL(string: targetString) else {
            respond(connection, status: 400, body: Data())
            return
        }

        fetch(target, referer: referer) { [weak self] data, mime, error in
            guard let self = self else { return }
            guard let data = data, error == nil else {
                self.respond(connection, status: 502, body: Data())
                return
            }

            let isPlaylist = target.path.lowercased().hasSuffix(".m3u8")
                || data.starts(with: Data("#EXTM3U".utf8))

            if isPlaylist {
                let text = String(decoding: data, as: UTF8.self)
                let rewritten = self.rewritePlaylist(text, base: target, referer: referer)
                self.respond(connection,
                             status: 200,
                             contentType: "application/vnd.apple.mpegurl",
                             body: Data(rewritten.utf8))
            } else {
                self.respond(connection,
                             status: 200,
                             contentType: self.mimeType(for: target, from: mime, body: data),
                             body: data)
            }
        }
    }

    // MARK: - 上游请求

    private func fetch(_ url: URL, referer: String, completion: @escaping (Data?, String?, Error?) -> Void) {
        var request = URLRequest(url: url)
        if !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        request.setValue(StreamResolver.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        urlSession.dataTask(with: request) { data, response, error in
            completion(data, (response as? HTTPURLResponse)?.mimeType, error)
        }.resume()
    }

    /// 分片被伪装成 .css / .svg / .webp，按 MPEG-TS 同步字节（0x47）识别最可靠
    private func mimeType(for url: URL, from serverMime: String?, body: Data) -> String {
        if body.count > 188, body.first == 0x47 {
            return "video/mp2t"
        }
        let path = url.path.lowercased()
        if path.hasSuffix(".ts") || path.hasSuffix(".css") { return "video/mp2t" }
        if path.hasSuffix(".m4s") || path.hasSuffix(".mp4") || path.hasSuffix(".m4v") { return "video/mp4" }
        if path.hasSuffix(".aac") { return "audio/aac" }
        if path.hasSuffix(".key") { return "application/octet-stream" }
        return serverMime ?? "application/octet-stream"
    }

    // MARK: - 播放列表改写

    private func rewritePlaylist(_ text: String, base: URL, referer: String) -> String {
        var output: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                output.append(line)
            } else if trimmed.hasPrefix("#") {
                output.append(rewriteURIAttributes(in: line, base: base, referer: referer))
            } else if let resolved = URL(string: trimmed, relativeTo: base)?.absoluteURL,
                      let local = localURL(for: resolved, referer: referer) {
                output.append(local.absoluteString)
            } else {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    /// 处理 #EXT-X-KEY / #EXT-X-MAP / #EXT-X-MEDIA 里的 URI="..."
    private func rewriteURIAttributes(in line: String, base: URL, referer: String) -> String {
        guard line.contains("URI=\"") else { return line }

        var result = ""
        var rest = Substring(line)
        while let marker = rest.range(of: "URI=\"") {
            result += String(rest[..<marker.upperBound])
            let afterMarker = rest[marker.upperBound...]
            guard let endQuote = afterMarker.firstIndex(of: "\"") else {
                result += String(afterMarker)
                return result
            }
            let value = String(afterMarker[..<endQuote])
            if let resolved = URL(string: value, relativeTo: base)?.absoluteURL,
               let local = localURL(for: resolved, referer: referer) {
                result += local.absoluteString
            } else {
                result += value
            }
            result += "\""
            rest = afterMarker[afterMarker.index(after: endQuote)...]
        }
        result += String(rest)
        return result
    }

    // MARK: - 响应

    private func respond(_ connection: NWConnection,
                         status: Int,
                         contentType: String = "application/octet-stream",
                         body: Data) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        default: reason = "Bad Gateway"
        }

        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n\r\n"

        var payload = Data(header.utf8)
        payload.append(body)

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

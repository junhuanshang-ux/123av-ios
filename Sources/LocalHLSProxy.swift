import Foundation
import Network

/// App 内置的本地 HLS 代理（高性能版）。
///
/// 背景：CDN 对播放列表**和每一个分片**都要求 `Referer: https://sadie-shop.site/`，
/// 不带就 403；而 AVPlayer 无法自定义请求头，所以必须有一次本地中转。
///
/// 为了把中转开销压到最低，这里做了三件事：
///   1. **流式透传**：上游一到字节就往下发（带 Content-Length），不再整段下载完再回；
///   2. **播放列表预取**：解析完 m3u8 就把前若干段并发拉进缓存，AVPlayer 请求时直接命中；
///   3. **分片缓存**：32MB LRU，拖动/回看不用重新下载。
final class LocalHLSProxy: NSObject {

    static let shared = LocalHLSProxy()

    // MARK: - 状态

    private let queue = DispatchQueue(label: "com.yidian.hlsproxy")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var started = false

    private lazy var session: URLSession = URLSession(configuration: {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldUsePipelining = true
        return config
    }(), delegate: self, delegateQueue: nil)

    /// taskIdentifier → 正在透传的上下文
    private var relays: [Int: Relay] = [:]
    private let relayLock = NSLock()

    private func setRelay(_ relay: Relay?, for id: Int) {
        relayLock.lock()
        defer { relayLock.unlock() }
        relays[id] = relay
    }

    private func relay(for id: Int) -> Relay? {
        relayLock.lock()
        defer { relayLock.unlock() }
        return relays[id]
    }

    private final class Relay {
        let connection: NWConnection
        let target: URL
        var isPlaylist: Bool
        var headerSent = false
        var buffer = Data()

        init(connection: NWConnection, target: URL, isPlaylist: Bool) {
            self.connection = connection
            self.target = target
            self.isPlaylist = isPlaylist
        }
    }

    // MARK: - 缓存

    private let cacheLock = NSLock()

    // 分片索引：用于边播边往后预取
    private let indexLock = NSLock()
    private var playlistSegments: [String: [String]] = [:]
    private var segmentOwner: [String: (playlist: String, index: Int)] = [:]
    private var cache: [String: Data] = [:]
    private var cacheOrder: [String] = []
    private var cacheBytes = 0
    private let cacheLimit = 48 * 1024 * 1024

    private func cached(_ key: String) -> Data? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[key]
    }

    /// 当前缓存占用（字节）
    var cachedBytes: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cacheBytes
    }

    /// 清空全部缓存与分片索引
    func clearCache() {
        cacheLock.lock()
        cache = [:]
        cacheOrder = []
        cacheBytes = 0
        cacheLock.unlock()

        indexLock.lock()
        playlistSegments = [:]
        segmentOwner = [:]
        indexLock.unlock()
    }

    private func store(_ key: String, _ data: Data) {
        guard !data.isEmpty else { return }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard cache[key] == nil else { return }
        cache[key] = data
        cacheOrder.append(key)
        cacheBytes += data.count
        while cacheBytes > cacheLimit, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) {
                cacheBytes -= removed.count
            }
        }
    }

    // MARK: - 生命周期

    @discardableResult
    func startIfNeeded() -> UInt16 {
        if started { return port }
        started = true
        port = start(loopbackOnly: true) ?? start(loopbackOnly: false) ?? 0
        return port
    }

    private func start(loopbackOnly: Bool) -> UInt16? {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            if loopbackOnly {
                params.requiredInterfaceType = .loopback
            }

            let listener = try NWListener(using: params, on: .any)
            let semaphore = DispatchSemaphore(value: 0)
            var assigned: UInt16 = 0

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let value = listener.port { assigned = value.rawValue }
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
            _ = semaphore.wait(timeout: .now() + 2)

            if assigned > 0 {
                self.listener = listener
                self.port = assigned
                return assigned
            }
            listener.cancel()
            return nil
        } catch {
            return nil
        }
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

    func localURL(for remote: URL, referer: String) -> URL? {
        guard port > 0 else { return nil }
        let u = LocalHLSProxy.encode(remote.absoluteString)
        let r = LocalHLSProxy.encode(referer)
        let rawName = remote.lastPathComponent
        let name = (rawName.isEmpty ? "seg" : rawName)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "seg"
        return URL(string: "http://127.0.0.1:\(port)/p/\(name)?r=\(r)&u=\(u)")
    }

    // MARK: - 连接

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
        guard parts.count >= 2, let components = URLComponents(string: parts[1]) else {
            respond(connection, status: 400, body: Data())
            return
        }

        let items = components.queryItems ?? []
        let referer = LocalHLSProxy.decode(items.first(where: { $0.name == "r" })?.value ?? "") ?? ""
        guard let targetString = LocalHLSProxy.decode(items.first(where: { $0.name == "u" })?.value ?? ""),
              let target = URL(string: targetString) else {
            respond(connection, status: 400, body: Data())
            return
        }

        // 缓存命中：直接整段返回（最快路径）
        if let hit = cached(target.absoluteString) {
            if hit.starts(with: Data("#EXTM3U".utf8)) {
                let result = rewritePlaylist(String(decoding: hit, as: UTF8.self), base: target, referer: referer)
                register(playlistKey: target.absoluteString, segments: result.segments)
                respond(connection, status: 200,
                        contentType: "application/vnd.apple.mpegurl",
                        body: Data(result.body.utf8))
                prefetchRange(playlistKey: target.absoluteString, from: 0, count: 8, referer: referer)
            } else {
                respond(connection, status: 200,
                        contentType: mimeType(for: target, from: nil, body: hit),
                        body: hit)
                prefetchAhead(of: target, referer: referer)
            }
            return
        }

        let isPlaylist = target.path.lowercased().hasSuffix(".m3u8")
        let relay = Relay(connection: connection, target: target, isPlaylist: isPlaylist)

        var request = URLRequest(url: target)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(StreamResolver.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let task = session.dataTask(with: request)
        setRelay(relay, for: task.taskIdentifier)
        task.resume()
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
        case 502: reason = "Bad Gateway"
        default: reason = "Error"
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

    /// 流式响应：先发头，再按块发数据
    private func beginStream(_ connection: NWConnection,
                             contentType: String,
                             contentLength: Int64) {
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        if contentLength > 0 {
            header += "Content-Length: \(contentLength)\r\n"
        }
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
    }

    private func mimeType(for url: URL, from serverMime: String?, body: Data) -> String {
        if body.first == 0x47 { return "video/mp2t" }
        let path = url.path.lowercased()
        for suffix in [".ts", ".css", ".webp", ".svg", ".jpg", ".jpeg", ".png"] where path.hasSuffix(suffix) {
            return "video/mp2t"
        }
        if path.hasSuffix(".m4s") || path.hasSuffix(".mp4") || path.hasSuffix(".m4v") { return "video/mp4" }
        if path.hasSuffix(".aac") { return "audio/aac" }
        if path.hasSuffix(".key") { return "application/octet-stream" }
        return serverMime ?? "application/octet-stream"
    }

    // MARK: - 播放列表改写

    private func rewritePlaylist(_ text: String, base: URL, referer: String) -> (body: String, segments: [String]) {
        var output: [String] = []
        var segments: [String] = []
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
                segments.append(resolved.absoluteString)
            } else {
                output.append(line)
            }
        }
        return (output.joined(separator: "\n"), segments)
    }

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

    // MARK: - 预取

    /// 记录某播放列表的分片顺序
    private func register(playlistKey: String, segments: [String]) {
        guard !segments.isEmpty else { return }
        indexLock.lock()
        playlistSegments[playlistKey] = segments
        for (index, segment) in segments.enumerated() {
            segmentOwner[segment] = (playlistKey, index)
        }
        indexLock.unlock()
    }

    private func prefetchOne(_ targetString: String, referer: String) {
        guard cached(targetString) == nil, let url = URL(string: targetString) else { return }
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(StreamResolver.userAgent, forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data, !data.isEmpty else { return }
            self.store(targetString, data)
        }.resume()
    }

    /// 并发预取某播放列表的一段
    private func prefetchRange(playlistKey: String, from start: Int, count: Int, referer: String) {
        indexLock.lock()
        let list = playlistSegments[playlistKey] ?? []
        indexLock.unlock()
        guard !list.isEmpty else { return }
        let begin = max(start, 0)
        let end = min(begin + count, list.count)
        guard begin < end else { return }
        for index in begin..<end {
            prefetchOne(list[index], referer: referer)
        }
    }

    /// 播放到某段时，往后预取若干段（边播边缓存，拖动/连播不再等）
    private func prefetchAhead(of target: URL, referer: String, count: Int = 8) {
        let key = target.absoluteString
        indexLock.lock()
        let owner = segmentOwner[key]
        indexLock.unlock()
        guard let owner = owner else { return }
        prefetchRange(playlistKey: owner.playlist, from: owner.index + 1, count: count, referer: referer)
    }
}



extension LocalHLSProxy: URLSessionDataDelegate {

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let relay = relay(for: dataTask.taskIdentifier),
           let http = response as? HTTPURLResponse {
            relay.isPlaylist = relay.isPlaylist || (http.mimeType ?? "").contains("mpegurl")
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let relay = relay(for: dataTask.taskIdentifier) else { return }

        if relay.isPlaylist {
            // 播放列表很小，攒完再改写
            relay.buffer.append(data)
            return
        }

        // 分片：边收边发
        if !relay.headerSent {
            relay.headerSent = true
            let length = dataTask.response?.expectedContentLength ?? -1
            let type = mimeType(for: relay.target, from: dataTask.response?.mimeType, body: data)
            beginStream(relay.connection, contentType: type, contentLength: length)
        }
        relay.buffer.append(data)
        relay.connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let relay = relay(for: task.taskIdentifier) else { return }
        setRelay(nil, for: task.taskIdentifier)

        if error != nil {
            if relay.headerSent {
                relay.connection.cancel()
            } else {
                respond(relay.connection, status: 502, body: Data())
            }
            return
        }

        if relay.isPlaylist {
            let raw = relay.buffer
            store(relay.target.absoluteString, raw)
            let text = String(decoding: raw, as: UTF8.self)
            let referer = refererFor(relay)
            let result = rewritePlaylist(text, base: relay.target, referer: referer)
            register(playlistKey: relay.target.absoluteString, segments: result.segments)
            respond(relay.connection,
                    status: 200,
                    contentType: "application/vnd.apple.mpegurl",
                    body: Data(result.body.utf8))
            // 首屏直接把前 8 段拉进缓存
            prefetchRange(playlistKey: relay.target.absoluteString, from: 0, count: 8, referer: referer)
        } else {
            store(relay.target.absoluteString, relay.buffer)
            prefetchAhead(of: relay.target, referer: refererFor(relay))
            if !relay.headerSent {
                // 没有数据（空分片）也要给个完整响应，避免播放器一直等
                respond(relay.connection,
                        status: 200,
                        contentType: mimeType(for: relay.target, from: nil, body: relay.buffer),
                        body: relay.buffer)
            } else {
                relay.connection.cancel()
            }
        }
    }

    private func refererFor(_ relay: Relay) -> String {
        let host = relay.target.host ?? ""
        if host.contains("123av") { return "https://123av.com/" }
        return "https://sadie-shop.site/"
    }
}

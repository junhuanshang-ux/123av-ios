import AVFoundation
import Foundation

/// HLS 本地代理（AVAssetResourceLoader + 自定义 scheme）。
///
/// 站点 CDN 的 **m3u8 和每一个分片**都要求 `Referer: https://sadie-shop.site/`，
/// 否则 Cloudflare 回 403；而且分片是被伪装成 `.css` 的 MPEG-TS 数据。
/// AVPlayer 不能自定义请求头，所以把 URL 的 scheme 换成 avstream:// 交给这里：
/// 由 URLSession 真发请求（补 Referer/UA），按扩展名修正 Content-Type，再把数据喂回 AVPlayer。
final class HLSLocalProxy: NSObject, AVAssetResourceLoaderDelegate {

    static let scheme = "avstream"

    private let referer: String
    private let session: URLSession

    /// 诊断用：记录最近一次失败原因
    private(set) var lastErrorText: String?

    init(referer: String) {
        self.referer = referer
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpMaximumConnectionsPerHost = 8
        cfg.httpShouldUsePipelining = true
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    /// https 地址 → 代理地址
    static func proxyURL(for url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = HLSLocalProxy.scheme
        return comps.url
    }

    /// 按真实内容给 Content-Type：分片是 .css 伪装的 TS，不能把 text/css 直接透给解复用器
    private func contentType(for url: URL, serverMime: String?) -> String {
        let path = url.path.lowercased()
        if path.hasSuffix(".m3u8") || path.hasSuffix(".m3u") {
            return "application/vnd.apple.mpegurl"
        }
        if path.hasSuffix(".ts") || path.hasSuffix(".css") {
            return "video/mp2t"
        }
        if path.hasSuffix(".m4s") || path.hasSuffix(".mp4") || path.hasSuffix(".m4v") {
            return "video/mp4"
        }
        if path.hasSuffix(".aac") {
            return "audio/aac"
        }
        if path.hasSuffix(".key") {
            return "application/octet-stream"
        }
        return serverMime ?? "application/octet-stream"
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {

        guard let url = loadingRequest.request.url,
              url.scheme == HLSLocalProxy.scheme,
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        comps.scheme = "https"
        guard let target = comps.url else { return false }

        var request = URLRequest(url: target)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(StreamResolver.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        // 不转发 Range：统一整段取回，避免 206 与长度声明不一致

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                loadingRequest.finishLoading()
                return
            }

            if let error = error {
                self.lastErrorText = "网络: \(error.localizedDescription)"
                loadingRequest.finishLoading(with: error)
                return
            }

            guard let http = response as? HTTPURLResponse, let data = data else {
                self.lastErrorText = "无响应"
                loadingRequest.finishLoading(with: StreamResolver.ResolveError.badResponse)
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                self.lastErrorText = "HTTP \(http.statusCode) \(target.lastPathComponent)"
                loadingRequest.finishLoading(with: StreamResolver.ResolveError.badResponse)
                return
            }

            if let info = loadingRequest.contentInformationRequest {
                info.contentType = self.contentType(for: target, serverMime: http.mimeType)
                info.contentLength = Int64(data.count)
                info.isByteRangeAccessSupported = false
            }

            if let dataRequest = loadingRequest.dataRequest {
                let offset = Int(dataRequest.requestedOffset)
                let requested = dataRequest.requestedLength
                if offset >= 0 && offset < data.count {
                    let available = data.count - offset
                    let take = (requested > 0 && requested < available) ? requested : available
                    dataRequest.respond(with: data.subdata(in: offset..<(offset + take)))
                }
            }

            loadingRequest.finishLoading()
        }
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        return false
    }
}

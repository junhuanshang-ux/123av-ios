import AVFoundation
import Foundation

/// 本地 HLS 代理。
///
/// 站点 CDN 的 m3u8 / 分片要求 `Referer: https://sadie-shop.site/`，否则 Cloudflare 直接 403，
/// 而 AVPlayer 没法直接给请求加 Referer。做法是把 https 换成自定义 scheme（avstream://）
/// 交给 AVAssetResourceLoader，由这里用 URLSession 真正发请求、补上头部，再把数据喂回去。
///
/// 这样播放走的是系统原生解码与自适应码率，比在 WKWebView 里跑 hls.js 快得多。
final class HLSLocalProxy: NSObject, AVAssetResourceLoaderDelegate {

    static let scheme = "avstream"

    private let referer: String
    private let userAgent: String
    private let session: URLSession

    init(referer: String) {
        self.referer = referer
        self.userAgent = StreamResolver.userAgent
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 60
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpMaximumConnectionsPerHost = 8
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    /// 原始 https 地址 → 代理用地址
    static func proxyURL(for url: URL) -> URL? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = HLSLocalProxy.scheme
        return comps.url
    }

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
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.apple.mpegurl, video/*, */*;q=0.8", forHTTPHeaderField: "Accept")
        if let range = loadingRequest.request.value(forHTTPHeaderField: "Range") {
            request.setValue(range, forHTTPHeaderField: "Range")
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                loadingRequest.finishLoading(with: error)
                return
            }
            guard let http = response as? HTTPURLResponse, let data = data else {
                loadingRequest.finishLoading(with: StreamResolver.ResolveError.badResponse)
                return
            }

            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let k = key as? String, let v = value as? String {
                    headers[k] = v
                }
            }

            if let info = loadingRequest.contentInformationRequest {
                if let type = headers["Content-Type"] {
                    info.contentType = type
                }
                info.contentLength = data.count
                info.isByteRangeAccessSupported = headers["Accept-Ranges"]?.contains("bytes") == true
            }

            if let dataRequest = loadingRequest.dataRequest {
                let offset = Int(dataRequest.requestedOffset)
                if offset >= 0 && offset < data.count {
                    dataRequest.respond(with: data.subdata(in: offset..<data.count))
                }
            }

            loadingRequest.response = HTTPURLResponse(url: target,
                                                      statusCode: http.statusCode,
                                                      httpVersion: "HTTP/1.1",
                                                      headerFields: headers)
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

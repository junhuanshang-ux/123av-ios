import Foundation
import WebKit

/// 把前端 JS 的请求转发给原生 URLSession。
///
/// 为什么要这层：
///   · App 内的页面来自本地 file://，直接 fetch 远程接口会被 WebKit 的跨域策略拦掉；
///   · 由原生发请求可以统一 UA（rec2 的签名要和 UA 一致）、带上站点 Referer；
///   · 前端拿到的永远是纯文本，解析逻辑全在 JS 里。
final class NetBridge: NSObject, WKScriptMessageHandler {

    /// JS / Swift 约定的事件名
    static let handlerName = "net"

    weak var webView: WKWebView?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 45
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpShouldSetCookies = false
        return URLSession(configuration: cfg)
    }()

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let reqId = body["id"] as? String,
              let urlString = body["url"] as? String,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = (body["method"] as? String) ?? "GET"

        if let headers = body["headers"] as? [String: String] {
            for (key, value) in headers where !key.isEmpty {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let text = body["body"] as? String, !text.isEmpty {
            request.httpBody = text.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        if request.value(forHTTPHeaderField: "Referer") == nil {
            request.setValue("https://123av.com/", forHTTPHeaderField: "Referer")
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if let error = error {
                self.reply(id: reqId, status: status == 0 ? 599 : status, text: "NETWORK_ERROR: \(error.localizedDescription)")
                return
            }

            let text: String
            if let data = data, !data.isEmpty {
                text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            } else {
                text = ""
            }
            self.reply(id: reqId, status: status, text: text)
        }.resume()
    }

    // MARK: - 回传给 JS

    private func reply(id: String, status: Int, text: String) {
        let base64 = Data(text.utf8).base64EncodedString()
        let js = "window.__net && window.__net.res(\(jsString(id)), \(status), \(jsString(base64)));"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func jsString(_ value: String) -> String {
        var out = "'"
        for ch in value {
            switch ch {
            case "\\": out += "\\\\"
            case "'": out += "\\'"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            default: out.append(ch)
            }
        }
        out += "'"
        return out
    }
}

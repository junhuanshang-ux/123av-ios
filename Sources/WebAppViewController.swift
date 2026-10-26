import UIKit
import WebKit
import SafariServices

/// 应用主界面：一个全屏 WKWebView，加载打包在 App 里的前端（www/index.html）。
/// 前端所有远程请求都通过 NetBridge 走原生；播放通过原生全屏播放器打开。
final class WebAppViewController: UIViewController {

    private let bridge = NetBridge()
    private var webView: WKWebView!
    private let refreshControl = UIRefreshControl()
    private var localRoot: URL?

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupWebView()
        loadLocalApp()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }

    // MARK: - 构建 WebView

    private func setupWebView() {
        let conf = WKWebViewConfiguration()
        conf.allowsInlineMediaPlayback = true
        conf.mediaTypesRequiringUserActionForPlayback = []
        conf.allowsAirPlayForMediaPlayback = true
        conf.preferences.javaScriptCanOpenWindowsAutomatically = false
        conf.defaultWebpagePreferences.allowsContentJavaScript = true
        conf.websiteDataStore = .default()

        // 标记 App 环境，前端据此走原生桥
        let flagScript = WKUserScript(source: "window.__APP__ = true;",
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: true)
        conf.userContentController.addUserScript(flagScript)
        conf.userContentController.add(bridge, name: NetBridge.handlerName)
        conf.userContentController.add(self, name: "player")

        let webView = WKWebView(frame: .zero, configuration: conf)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = .black
        }
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        refreshControl.tintColor = UIColor(white: 1, alpha: 0.55)
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.webView = webView
        bridge.webView = webView
    }

    private func loadLocalApp() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("www", isDirectory: true) else {
            showFatal("缺少前端资源目录 www")
            return
        }
        localRoot = root
        let index = root.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: index.path) else {
            showFatal("缺少 www/index.html")
            return
        }
        webView.loadFileURL(index, allowingReadAccessTo: root)
    }

    @objc private func handleRefresh() {
        webView.reload()
    }

    private func showFatal(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 15)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    // MARK: - 页面内的外部链接 / 播放器

    private func presentSafari(_ url: URL) {
        guard url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(red: 0.91, green: 0.24, blue: 0.55, alpha: 1)
        present(vc, animated: true)
    }

    private func openPlayer(_ url: URL, title: String) {
        let vc = PlayerViewController(url: url, titleText: title)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }
}

// MARK: - 前端 → 原生消息
extension WebAppViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "player",
              let body = message.body as? [String: Any],
              let urlString = body["url"] as? String,
              let url = URL(string: urlString) else { return }
        openPlayer(url, title: (body["title"] as? String) ?? "")
    }
}

// MARK: - 导航策略
extension WebAppViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // 本地页面（含 hash 路由）一律放行
        if url.isFileURL {
            decisionHandler(.allow)
            return
        }

        // 任何远程地址都不在 WebView 里打开，避免把应用变成简易浏览器
        decisionHandler(.cancel)
        presentSafari(url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - 弹窗 / 新窗口
extension WebAppViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, !url.isFileURL {
            presentSafari(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { field in field.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }
}

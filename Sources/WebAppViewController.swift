import UIKit
import WebKit
import SafariServices

/// 应用主界面：一个全屏 WKWebView，加载打包在 App 里的前端（www/index.html）。
/// 前端所有远程请求都通过 NetBridge 走原生；播放交给原生播放器。
/// 进入应用 / 进入播放器都要求面容（或锁屏密码）验证；切后台时用纯色遮罩挡住快照。
final class WebAppViewController: UIViewController {

    private let bridge = NetBridge()
    private var webView: WKWebView!
    private let refreshControl = UIRefreshControl()
    private var localRoot: URL?

    /// 隐私遮挡（App 切换器快照、未解锁时挡住内容）
    private let coverView = UIView()

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupWebView()
        setupPrivacyCover()
        observeAppLifecycle()
        loadLocalApp()
        coverView.isHidden = AuthGate.isFresh
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentLockIfNeeded(reason: "验证身份以进入邮件") { [weak self] in
            self?.hideCover()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

    // MARK: - 隐私遮挡 & 生命周期

    private func setupPrivacyCover() {
        coverView.backgroundColor = .black
        coverView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coverView)

        let icon = UIImageView(image: UIImage(systemName: "envelope.fill"))
        icon.tintColor = UIColor(white: 1, alpha: 0.55)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "邮件"
        label.textColor = UIColor(white: 1, alpha: 0.55)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        coverView.addSubview(icon)
        coverView.addSubview(label)

        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            coverView.topAnchor.constraint(equalTo: view.topAnchor),
            coverView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            icon.centerXAnchor.constraint(equalTo: coverView.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: coverView.centerYAnchor, constant: -10),
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 32),

            label.centerXAnchor.constraint(equalTo: coverView.centerXAnchor),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 10)
        ])
    }

    private func showCover() {
        coverView.isHidden = false
    }

    private func hideCover() {
        coverView.isHidden = true
    }

    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(appWillResignActive),
                           name: UIApplication.willResignActiveNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(appDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification,
                           object: nil)
    }

    @objc private func appWillResignActive() {
        // 立刻挡住画面：多任务快照里只会看到纯黑
        showCover()
    }

    @objc private func appDidBecomeActive() {
        if AuthGate.isFresh {
            hideCover()
            return
        }
        presentLockIfNeeded(reason: "验证身份以继续") { [weak self] in
            self?.hideCover()
        }
    }

    // MARK: - 验证闸门

    /// 需要验证时弹出全屏验证页；已通过（宽限期内）直接执行 completion
    private func presentLockIfNeeded(reason: String,
                                     force: Bool = false,
                                     completion: (() -> Void)? = nil) {
        if force {
            // 播放器：每次都验证（只容忍 5 秒内的重复触发）
            if AuthGate.fresh(within: AuthGate.playerGrace) {
                completion?()
                return
            }
        } else if AuthGate.isFresh {
            completion?()
            return
        }
        if presentedViewController is LockViewController {
            return
        }

        let lock = LockViewController()
        lock.modalPresentationStyle = .overFullScreen
        lock.modalTransitionStyle = .crossDissolve
        lock.onUnlocked = { [weak self] in
            self?.hideCover()
            completion?()
        }
        topPresenter.present(lock, animated: true, completion: nil)
    }

    /// 最顶层的控制器（播放器等已经 present 时，验证页要弹在它上面）
    private var topPresenter: UIViewController {
        var controller: UIViewController = self
        while let presented = controller.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }

    // MARK: - 打开播放器

    private func openPlayer(_ url: URL, title: String, code: String) {
        presentLockIfNeeded(reason: "验证身份后播放", force: true) { [weak self] in
            self?.startNativePlayer(url, title: title, code: code)
        }
    }

    private func startNativePlayer(_ url: URL, title: String, code: String) {
        let player = NativePlayerViewController(embedURL: url, title: title, code: code)
        player.onFallback = { [weak self] embedURL, embedTitle in
            guard let self = self else { return }
            self.dismiss(animated: false) {
                self.presentEmbedPlayer(embedURL, title: embedTitle)
            }
        }
        player.modalPresentationStyle = .fullScreen
        present(player, animated: true, completion: nil)
    }

    private func presentEmbedPlayer(_ url: URL, title: String) {
        let fallback = PlayerViewController(url: url, titleText: title)
        fallback.modalPresentationStyle = .fullScreen
        present(fallback, animated: true, completion: nil)
    }

    // MARK: - 页面内的外部链接

    private func presentSafari(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "https" || scheme == "http" else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(red: 0.91, green: 0.24, blue: 0.55, alpha: 1)
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
        openPlayer(url,
                   title: (body["title"] as? String) ?? "",
                   code: (body["code"] as? String) ?? "")
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

        if url.isFileURL {
            decisionHandler(.allow)
            return
        }

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

import UIKit
import WebKit
import AVFoundation

/// 全屏播放器：加载站点播放源（embed 页），
/// 屏蔽弹窗与外部跳转，只允许原站域名内的导航。
final class PlayerViewController: UIViewController {

    private let url: URL
    private let titleText: String
    private let allowedHost: String?

    private var webView: WKWebView!
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    init(url: URL, titleText: String) {
        self.url = url
        self.titleText = titleText
        self.allowedHost = url.host?.lowercased()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureAudioSession()
        setupWebView()
        setupChrome()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    // MARK: - 声音：允许静音键下继续出声、支持后台音频会话

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true)
    }

    // MARK: - WebView

    private func setupWebView() {
        let conf = WKWebViewConfiguration()
        conf.allowsInlineMediaPlayback = true
        conf.mediaTypesRequiringUserActionForPlayback = []
        conf.allowsAirPlayForMediaPlayback = true
        conf.allowsPictureInPictureMediaPlayback = true
        conf.defaultWebpagePreferences.allowsContentJavaScript = true
        conf.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: conf)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.webView = webView

        var request = URLRequest(url: url)
        request.setValue("https://123av.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 25
        webView.load(request)
    }

    // MARK: - 顶部控件

    private func setupChrome() {
        let bar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.layer.cornerRadius = 18
        bar.clipsToBounds = true
        view.addSubview(bar)

        titleLabel.text = titleText
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.contentView.addSubview(titleLabel)

        let symbol = UIImage(systemName: "xmark") ?? UIImage()
        closeButton.setImage(symbol, for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor(white: 1, alpha: 0.14)
        closeButton.layer.cornerRadius = 15
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closePlayer), for: .touchUpInside)
        bar.contentView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),

            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            closeButton.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: bar.contentView.centerYAnchor),
            closeButton.topAnchor.constraint(equalTo: bar.contentView.topAnchor, constant: 8),
            closeButton.bottomAnchor.constraint(equalTo: bar.contentView.bottomAnchor, constant: -8),

            titleLabel.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: bar.contentView.centerYAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(showChrome))
        tap.numberOfTapsRequired = 3
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func showChrome() {
        view.subviews.compactMap { $0 as? UIVisualEffectView }.forEach { bar in
            UIView.animate(withDuration: 0.25) { bar.alpha = 1 }
        }
    }

    @objc private func closePlayer() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - 导航限制
extension PlayerViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let target = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = target.scheme?.lowercased() ?? ""

        // 播放器内部的空实现 / 数据地址放行
        if scheme == "about" || scheme == "data" || scheme == "blob" {
            decisionHandler(.allow)
            return
        }

        // 只允许原站域名（及其子域），其余一律拦截：广告跳转、外链全部无效
        if scheme == "https" || scheme == "http" {
            if let allowed = allowedHost,
               let host = target.host?.lowercased(),
               host == allowed || host.hasSuffix("." + allowed) {
                decisionHandler(.allow)
                return
            }
        }

        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - 弹窗拦截
extension PlayerViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // 播放页的广告全部走 window.open，这里直接拒绝
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }
}

import UIKit

/// 全屏遮罩式验证页：盖住整个界面，验证通过才消失。
/// 同时用作"切换后台时的隐私遮挡"——应用快照里看不到任何画面内容。
final class LockViewController: UIViewController {

    /// 验证成功后回调（nil 表示没有外部关注）
    var onUnlocked: (() -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var isAuthenticating = false
    private var didAutoTrigger = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didAutoTrigger {
            didAutoTrigger = true
            authenticate()
        }
    }

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - UI

    private func setupUI() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let config = UIImage.SymbolConfiguration(pointSize: 46, weight: .regular)
        iconView.image = UIImage(systemName: "lock.shield", withConfiguration: config)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit

        titleLabel.text = "邮件"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textAlignment = .center

        hintLabel.text = AuthGate.biometricsAvailable ? "使用面容 ID 解锁" : "输入锁屏密码解锁"
        hintLabel.textColor = UIColor(white: 1, alpha: 0.62)
        hintLabel.font = .systemFont(ofSize: 14)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        actionButton.setTitle("解锁", for: .normal)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        actionButton.backgroundColor = UIColor(white: 1, alpha: 0.14)
        actionButton.layer.cornerRadius = 22
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 11, left: 26, bottom: 11, right: 26)
        actionButton.addTarget(self, action: #selector(authenticate), for: .touchUpInside)

        spinner.color = .white
        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, hintLabel, actionButton, spinner])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.setCustomSpacing(22, after: hintLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    // MARK: - 验证

    @objc private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        actionButton.isHidden = true
        spinner.startAnimating()

        AuthGate.authenticate(reason: "验证身份以继续") { [weak self] ok in
            guard let self = self else { return }
            self.isAuthenticating = false
            self.spinner.stopAnimating()
            if ok {
                self.finish()
            } else {
                self.actionButton.isHidden = false
                self.hintLabel.text = "验证未通过，点击重新验证"
            }
        }
    }

    private func finish() {
        onUnlocked?()
        onUnlocked = nil
        dismiss(animated: true, completion: nil)
    }
}

import UIKit

// MARK: - 图片加载（带内存缓存）

final class RemoteImageView: UIImageView {

    private static let cache = NSCache<NSURL, UIImage>()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private var task: URLSessionDataTask?
    private var targetURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Palette.surfaceAlt
        contentMode = .scaleAspectFill
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(url: URL?) {
        guard let url = url else {
            task?.cancel()
            task = nil
            image = nil
            return
        }
        if targetURL == url, image != nil { return }
        targetURL = url

        if let cached = RemoteImageView.cache.object(forKey: url as NSURL) {
            image = cached
            task?.cancel()
            task = nil
            return
        }

        image = nil
        task?.cancel()

        var request = URLRequest(url: url)
        request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")

        task = RemoteImageView.session.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            RemoteImageView.cache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async {
                guard let self = self, self.targetURL == url else { return }
                self.image = image
            }
        }
        task?.resume()
    }
}

// MARK: - 视频卡片

final class VideoCardCell: UICollectionViewCell {

    static let reuseID = "VideoCardCell"

    private let cover = RemoteImageView()
    private let durationLabel = PaddedLabel()
    private let rankLabel = PaddedLabel()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        cover.translatesAutoresizingMaskIntoConstraints = false
        cover.layer.cornerRadius = 10
        cover.layer.cornerCurve = .continuous
        contentView.addSubview(cover)

        durationLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor(white: 0, alpha: 0.66)
        durationLabel.layer.cornerRadius = 5
        durationLabel.clipsToBounds = true
        durationLabel.insets = UIEdgeInsets(top: 1.5, left: 5, bottom: 1.5, right: 5)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(durationLabel)

        rankLabel.font = .systemFont(ofSize: 10.5, weight: .bold)
        rankLabel.textColor = .white
        rankLabel.backgroundColor = UIColor(white: 0, alpha: 0.62)
        rankLabel.layer.cornerRadius = 5
        rankLabel.clipsToBounds = true
        rankLabel.insets = UIEdgeInsets(top: 1.5, left: 5, bottom: 1.5, right: 5)
        rankLabel.translatesAutoresizingMaskIntoConstraints = false
        rankLabel.isHidden = true
        cover.addSubview(rankLabel)

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cover.topAnchor.constraint(equalTo: contentView.topAnchor),
            cover.heightAnchor.constraint(equalTo: cover.widthAnchor, multiplier: 2.0 / 3.0),

            durationLabel.trailingAnchor.constraint(equalTo: cover.trailingAnchor, constant: -5),
            durationLabel.bottomAnchor.constraint(equalTo: cover.bottomAnchor, constant: -5),

            rankLabel.leadingAnchor.constraint(equalTo: cover.leadingAnchor, constant: 5),
            rankLabel.topAnchor.constraint(equalTo: cover.topAnchor, constant: 5),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 6),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: VideoItem) {
        cover.set(url: item.coverURL)
        durationLabel.text = item.duration
        durationLabel.isHidden = item.duration.isEmpty
        titleLabel.text = item.title

        if let rank = item.rank {
            rankLabel.text = "\(rank)"
            rankLabel.isHidden = false
            rankLabel.backgroundColor = rank <= 3 ? Palette.accent : UIColor(white: 0, alpha: 0.62)
        } else {
            rankLabel.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cover.image = nil
        titleLabel.text = nil
        rankLabel.isHidden = true
    }
}

// MARK: - 小工具

final class PaddedLabel: UILabel {
    var insets: UIEdgeInsets = .zero

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}

final class SectionHeaderView: UICollectionReusableView {

    static let reuseID = "SectionHeaderView"

    private let bar = UIView()
    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        bar.backgroundColor = Palette.accent
        bar.layer.cornerRadius = 1.5
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = Palette.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        actionButton.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        actionButton.setTitleColor(Palette.accent, for: .normal)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            bar.widthAnchor.constraint(equalToConstant: 3),
            bar.heightAnchor.constraint(equalToConstant: 15),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, action: String?, handler: (() -> Void)?) {
        titleLabel.text = title
        actionButton.setTitle(action, for: .normal)
        actionButton.isHidden = (action == nil)
        onAction = handler
    }

    @objc private func handleAction() {
        onAction?()
    }
}

final class ChipCell: UICollectionViewCell {

    static let reuseID = "ChipCell"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = Palette.surface
        contentView.layer.cornerRadius = 15
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = Palette.separator.cgColor

        label.font = .systemFont(ofSize: 13)
        label.textColor = Palette.text
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(genre: Genre) {
        label.text = genre.name
    }
}

// MARK: - 空态

final class EmptyStateView: UIView {

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Palette.text
        titleLabel.textAlignment = .center

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = Palette.secondaryText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        retryButton.setTitle("重试", for: .normal)
        retryButton.setTitleColor(Palette.accent, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, retryButton])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }

    @objc private func retry() {
        onRetry?()
    }
}

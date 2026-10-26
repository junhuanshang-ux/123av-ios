import UIKit
import SafariServices

final class DetailViewController: UIViewController {

    private let code: String
    private var detail: VideoDetail?
    private var related: [VideoItem] = []
    private var selectedEpisode = 0

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let posterView = RemoteImageView()
    private let heroContainer = UIView()
    private let playOverlay = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let statsLabel = UILabel()
    private let episodeScroll = UIScrollView()
    private let episodeStack = UIStackView()
    private let infoContainer = UIView()
    private let infoStack = UIStackView()
    private let genreScroll = UIScrollView()
    private let genreStack = UIStackView()
    private var relatedCollection: UICollectionView!
    private let relatedHeader = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(code: String) {
        self.code = code.lowercased()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        title = code.uppercased()
        setupNavigationBar()
        setupLayout()
        load()
    }

    private func setupNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.background
        appearance.titleTextAttributes = [.foregroundColor: Palette.text]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = Palette.text
    }

    // MARK: - 布局

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        buildHero()
        buildHeadline()
        buildEpisodes()
        buildInfo()
        buildGenres()
        buildRelated()

        spinner.color = Palette.secondaryText
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func buildHero() {
        heroContainer.backgroundColor = .black
        posterView.contentMode = .scaleAspectFill
        posterView.translatesAutoresizingMaskIntoConstraints = false
        heroContainer.addSubview(posterView)

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "play.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold))
        config.baseForegroundColor = .white
        config.background.backgroundColor = Palette.accent
        config.background.cornerRadius = 31
        playOverlay.configuration = config
        playOverlay.translatesAutoresizingMaskIntoConstraints = false
        playOverlay.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        heroContainer.addSubview(playOverlay)

        NSLayoutConstraint.activate([
            posterView.leadingAnchor.constraint(equalTo: heroContainer.leadingAnchor),
            posterView.trailingAnchor.constraint(equalTo: heroContainer.trailingAnchor),
            posterView.topAnchor.constraint(equalTo: heroContainer.topAnchor),
            posterView.bottomAnchor.constraint(equalTo: heroContainer.bottomAnchor),

            playOverlay.widthAnchor.constraint(equalToConstant: 62),
            playOverlay.heightAnchor.constraint(equalToConstant: 62),
            playOverlay.centerXAnchor.constraint(equalTo: heroContainer.centerXAnchor),
            playOverlay.centerYAnchor.constraint(equalTo: heroContainer.centerYAnchor)
        ])

        heroContainer.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 9.0 / 16.0).isActive = true
        contentStack.addArrangedSubview(heroContainer)
    }

    private func buildHeadline() {
        let wrapper = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = Palette.text
        titleLabel.numberOfLines = 0

        statsLabel.font = .systemFont(ofSize: 12)
        statsLabel.textColor = Palette.secondaryText
        statsLabel.numberOfLines = 0

        let playButton = makeActionButton(title: "立即播放", filled: true)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        let webButton = makeActionButton(title: "网页版", filled: false)
        webButton.addTarget(self, action: #selector(openWeb), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [playButton, webButton])
        buttons.axis = .horizontal
        buttons.spacing = 10
        buttons.distribution = .fillEqually

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(statsLabel)
        stack.addArrangedSubview(buttons)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])

        contentStack.addArrangedSubview(wrapper)
    }

    private func makeActionButton(title: String, filled: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 11
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        if filled {
            button.backgroundColor = Palette.accent
            button.setTitleColor(.white, for: .normal)
        } else {
            button.backgroundColor = Palette.surface
            button.setTitleColor(Palette.text, for: .normal)
            button.layer.borderWidth = 1
            button.layer.borderColor = Palette.separator.cgColor
        }
        return button
    }

    private func buildEpisodes() {
        episodeStack.axis = .horizontal
        episodeStack.spacing = 8
        episodeStack.translatesAutoresizingMaskIntoConstraints = false
        episodeScroll.showsHorizontalScrollIndicator = false
        episodeScroll.translatesAutoresizingMaskIntoConstraints = false
        episodeScroll.addSubview(episodeStack)

        NSLayoutConstraint.activate([
            episodeStack.leadingAnchor.constraint(equalTo: episodeScroll.leadingAnchor, constant: 14),
            episodeStack.trailingAnchor.constraint(equalTo: episodeScroll.trailingAnchor, constant: -14),
            episodeStack.topAnchor.constraint(equalTo: episodeScroll.topAnchor),
            episodeStack.bottomAnchor.constraint(equalTo: episodeScroll.bottomAnchor),
            episodeStack.heightAnchor.constraint(equalToConstant: 34),
            episodeScroll.heightAnchor.constraint(equalToConstant: 34)
        ])

        episodeScroll.isHidden = true
        contentStack.addArrangedSubview(episodeScroll)
    }

    private func buildInfo() {
        infoContainer.backgroundColor = Palette.surface
        infoContainer.layer.cornerRadius = 12
        infoContainer.translatesAutoresizingMaskIntoConstraints = false

        infoStack.axis = .vertical
        infoStack.spacing = 0
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.addSubview(infoStack)

        NSLayoutConstraint.activate([
            infoStack.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor, constant: 12),
            infoStack.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor, constant: -12),
            infoStack.topAnchor.constraint(equalTo: infoContainer.topAnchor, constant: 4),
            infoStack.bottomAnchor.constraint(equalTo: infoContainer.bottomAnchor, constant: -4)
        ])

        let wrapper = UIView()
        wrapper.addSubview(infoContainer)
        NSLayoutConstraint.activate([
            infoContainer.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            infoContainer.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -14),
            infoContainer.topAnchor.constraint(equalTo: wrapper.topAnchor),
            infoContainer.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        contentStack.addArrangedSubview(wrapper)
    }

    private func buildGenres() {
        genreStack.axis = .horizontal
        genreStack.spacing = 8
        genreStack.translatesAutoresizingMaskIntoConstraints = false
        genreScroll.showsHorizontalScrollIndicator = false
        genreScroll.translatesAutoresizingMaskIntoConstraints = false
        genreScroll.addSubview(genreStack)

        NSLayoutConstraint.activate([
            genreStack.leadingAnchor.constraint(equalTo: genreScroll.leadingAnchor, constant: 14),
            genreStack.trailingAnchor.constraint(equalTo: genreScroll.trailingAnchor, constant: -14),
            genreStack.topAnchor.constraint(equalTo: genreScroll.topAnchor),
            genreStack.bottomAnchor.constraint(equalTo: genreScroll.bottomAnchor),
            genreStack.heightAnchor.constraint(equalToConstant: 32),
            genreScroll.heightAnchor.constraint(equalToConstant: 32)
        ])

        genreScroll.isHidden = true
        contentStack.addArrangedSubview(genreScroll)
    }

    private func buildRelated() {
        relatedHeader.text = "你可能喜欢"
        relatedHeader.font = .systemFont(ofSize: 16, weight: .bold)
        relatedHeader.textColor = Palette.text
        relatedHeader.isHidden = true

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        layout.itemSize = CGSize(width: 150, height: 150 * 2 / 3 + 46)

        let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.dataSource = self
        collection.delegate = self
        collection.register(VideoCardCell.self, forCellWithReuseIdentifier: VideoCardCell.reuseID)
        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.heightAnchor.constraint(equalToConstant: 150 * 2 / 3 + 46).isActive = true
        collection.isHidden = true
        relatedCollection = collection

        let wrapper = UIView()
        let stack = UIStackView(arrangedSubviews: [relatedHeader, collection])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            stack.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        relatedHeader.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14).isActive = true

        contentStack.addArrangedSubview(wrapper)
    }

    // MARK: - 数据

    private func load() {
        APIClient.shared.detail(code: code) { [weak self] detail in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            guard let detail = detail else {
                self.title = "加载失败"
                return
            }
            self.detail = detail
            self.render(detail)
        }

        APIClient.shared.similar(code: code, count: 12) { [weak self] items in
            guard let self = self, !items.isEmpty else { return }
            self.related = items
            self.relatedHeader.isHidden = false
            self.relatedCollection.isHidden = false
            self.relatedCollection.reloadData()
        }
    }

    private func render(_ detail: VideoDetail) {
        title = detail.code
        posterView.set(url: detail.poster ?? URL(string: "\(AppConfig.cdn)/img2/s500/\(MD5.prefix2(of: code))/\(code)/cover.jpg"))
        titleLabel.text = detail.title
        statsLabel.text = detail.stats.joined(separator: " · ")

        infoStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, row) in detail.info.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 12
            rowStack.alignment = .top

            let keyLabel = UILabel()
            keyLabel.text = row.0
            keyLabel.font = .systemFont(ofSize: 13)
            keyLabel.textColor = Palette.secondaryText
            keyLabel.widthAnchor.constraint(equalToConstant: 62).isActive = true

            let valueLabel = UILabel()
            valueLabel.text = row.1
            valueLabel.font = .systemFont(ofSize: 13)
            valueLabel.textColor = Palette.text
            valueLabel.numberOfLines = 0

            rowStack.addArrangedSubview(keyLabel)
            rowStack.addArrangedSubview(valueLabel)
            rowStack.isLayoutMarginsRelativeArrangement = true
            rowStack.layoutMargins = UIEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)

            let container = UIView()
            container.addSubview(rowStack)
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                rowStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                rowStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                rowStack.topAnchor.constraint(equalTo: container.topAnchor),
                rowStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            infoStack.addArrangedSubview(container)

            if index < detail.info.count - 1 {
                let line = UIView()
                line.backgroundColor = Palette.separator
                line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                infoStack.addArrangedSubview(line)
            }
        }

        if detail.episodes.count > 1 {
            episodeScroll.isHidden = false
            episodeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for (index, episode) in detail.episodes.enumerated() {
                let button = UIButton(type: .system)
                button.setTitle("第 \(index + 1) 集", for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
                button.layer.cornerRadius = 16
                button.layer.borderWidth = 1
                button.layer.borderColor = Palette.separator.cgColor
                button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
                button.setTitleColor(index == selectedEpisode ? Palette.accent : Palette.text, for: .normal)
                button.tag = index
                button.addTarget(self, action: #selector(selectEpisode(_:)), for: .touchUpInside)
                episodeStack.addArrangedSubview(button)
                _ = episode
            }
        }

        if !detail.genres.isEmpty {
            genreScroll.isHidden = false
            genreStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for genre in detail.genres {
                let button = UIButton(type: .system)
                button.setTitle(genre.name, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 13)
                button.setTitleColor(Palette.text, for: .normal)
                button.backgroundColor = Palette.surface
                button.layer.cornerRadius = 16
                button.layer.borderWidth = 1
                button.layer.borderColor = Palette.separator.cgColor
                button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
                button.addAction(UIAction { [weak self] _ in
                    self?.navigationController?.pushViewController(
                        GridViewController(source: .genre(slug: genre.slug, title: genre.name)),
                        animated: true
                    )
                }, for: .touchUpInside)
                genreStack.addArrangedSubview(button)
            }
        }

        Store.addRecent(VideoItem(code: detail.code.lowercased(),
                                  title: detail.title,
                                  duration: detail.info.first(where: { $0.0 == "时长" })?.1 ?? "",
                                  cover: posterView.image == nil ? "" : (detail.poster?.absoluteString ?? "")))
    }

    // MARK: - 动作

    @objc private func selectEpisode(_ sender: UIButton) {
        selectedEpisode = sender.tag
        for case let button as UIButton in episodeStack.arrangedSubviews {
            button.setTitleColor(button.tag == selectedEpisode ? Palette.accent : Palette.text, for: .normal)
        }
    }

    @objc private func playTapped() {
        guard let detail = detail, !detail.episodes.isEmpty else { return }
        let index = min(selectedEpisode, detail.episodes.count - 1)
        let episode = detail.episodes[index]
        let player = NativePlayerViewController(embedURL: episode.url, title: detail.title, code: detail.code)
        // 原生链路失败时自动退回网页播放器（保证一定能播）
        player.onFallback = { [weak self] embedURL, titleText in
            guard let self = self else { return }
            self.dismiss(animated: false) {
                let fallback = PlayerViewController(url: embedURL, titleText: titleText)
                fallback.modalPresentationStyle = .fullScreen
                self.present(fallback, animated: true, completion: nil)
            }
        }
        player.modalPresentationStyle = .fullScreen
        present(player, animated: true, completion: nil)
    }

    @objc private func openWeb() {
        guard let url = URL(string: "\(AppConfig.site)/cn/v/\(code)") else { return }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = Palette.accent
        present(safari, animated: true, completion: nil)
    }
}

extension DetailViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return related.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCardCell.reuseID, for: indexPath) as! VideoCardCell
        cell.configure(with: related[indexPath.item])
        return cell
    }
}

extension DetailViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let item = related[indexPath.item]
        navigationController?.pushViewController(DetailViewController(code: item.code), animated: true)
    }
}

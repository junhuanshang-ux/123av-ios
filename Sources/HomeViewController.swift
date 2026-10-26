import UIKit

final class HomeViewController: UIViewController {

    private struct Block {
        enum Kind { case grid, rail, chips }
        let kind: Kind
        let title: String
        var actionTitle: String?
        var action: (() -> Void)?
        var videos: [VideoItem] = []
        var genres: [Genre] = []
    }

    private var collectionView: UICollectionView!
    private var blocks: [Block] = []
    private let refreshControl = UIRefreshControl()
    private let emptyView = EmptyStateView()
    private var isLoading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        setupNavigationBar()
        setupCollectionView()
        setupEmptyView()
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 从详情页回来时，最近观看可能变了
        if !blocks.isEmpty { rebuildRecentBlock() }
    }

    // MARK: - UI

    private func setupNavigationBar() {
        title = "推荐"
        navigationController?.navigationBar.prefersLargeTitles = false

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.background
        appearance.titleTextAttributes = [.foregroundColor: Palette.text]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance

        let themeButton = UIBarButtonItem(image: UIImage(systemName: "circle.lefthalf.filled"),
                                          style: .plain,
                                          target: self,
                                          action: #selector(toggleTheme))
        themeButton.tintColor = Palette.text
        navigationItem.rightBarButtonItem = themeButton
    }

    private func setupCollectionView() {
        let layout = makeLayout()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = Palette.background
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(VideoCardCell.self, forCellWithReuseIdentifier: VideoCardCell.reuseID)
        collectionView.register(ChipCell.self, forCellWithReuseIdentifier: ChipCell.reuseID)
        collectionView.register(SectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: SectionHeaderView.reuseID)

        refreshControl.tintColor = Palette.secondaryText
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.collectionView = collectionView
    }

    private func setupEmptyView() {
        emptyView.isHidden = true
        emptyView.onRetry = { [weak self] in self?.load() }
        view.addSubview(emptyView)
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - 布局

    private func headerItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                          heightDimension: .absolute(46))
        return NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: size,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self = self, index < self.blocks.count else { return nil }
            let block = self.blocks[index]
            let width = environment.container.contentSize.width

            switch block.kind {
            case .grid:
                let inset: CGFloat = 12
                let spacing: CGFloat = 10
                let itemWidth = max((width - inset * 2 - spacing) / 2, 60)
                let itemHeight = itemWidth * 2 / 3 + 46
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(itemWidth),
                                                                   heightDimension: .absolute(itemHeight)))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(itemHeight)),
                    subitems: [item]
                )
                group.interItemSpacing = .fixed(spacing)
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = 14
                section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: inset, bottom: 8, trailing: inset)
                section.boundarySupplementaryItems = [self.headerItem()]
                return section

            case .rail:
                let itemWidth: CGFloat = 150
                let itemHeight = itemWidth * 2 / 3 + 46
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(itemWidth),
                                                                   heightDimension: .absolute(itemHeight)))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: .absolute(itemWidth), heightDimension: .absolute(itemHeight)),
                    subitems: [item]
                )
                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .continuous
                section.interGroupSpacing = 10
                section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 14, bottom: 8, trailing: 14)
                section.boundarySupplementaryItems = [self.headerItem()]
                return section

            case .chips:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .estimated(86),
                                                                   heightDimension: .absolute(34)))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: .estimated(86), heightDimension: .absolute(34)),
                    subitems: [item]
                )
                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .continuous
                section.interGroupSpacing = 8
                section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 14, bottom: 12, trailing: 14)
                section.boundarySupplementaryItems = [self.headerItem()]
                return section
            }
        }
    }

    // MARK: - 数据

    private func load() {
        guard !isLoading else { return }
        isLoading = true
        emptyView.isHidden = true

        var recommendations: [VideoItem] = []
        var segmentGenres: [String] = []
        var labels: [String: String] = [:]
        var perGenre: [String: [VideoItem]] = [:]
        var fresh: [VideoItem] = []
        var today: [VideoItem] = []
        var genres: [Genre] = []

        let group = DispatchGroup()

        group.enter()
        APIClient.shared.recommendations { items in
            recommendations = items
            group.leave()
        }

        group.enter()
        APIClient.shared.genreLabels { map in
            labels = map
            group.leave()
        }

        group.enter()
        APIClient.shared.listPage(path: "/cn/new", page: 1) { items in
            fresh = Array(items.prefix(18))
            group.leave()
        }

        group.enter()
        APIClient.shared.listPage(path: "/cn/all?sort=today", page: 1) { items in
            today = Array(items.prefix(15))
            group.leave()
        }

        group.enter()
        APIClient.shared.allGenres { list in
            genres = list
            group.leave()
        }

        group.enter()
        APIClient.shared.segments { segments in
            segmentGenres = segments
            let inner = DispatchGroup()
            var collected: [String: [VideoItem]] = [:]
            for genre in segments {
                inner.enter()
                APIClient.shared.items(genre: genre, count: 12) { items, _ in
                    collected[genre] = items
                    inner.leave()
                }
            }
            inner.notify(queue: .main) {
                perGenre = collected
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.refreshControl.endRefreshing()
            self.buildBlocks(recommendations: recommendations,
                             segmentGenres: segmentGenres,
                             labels: labels,
                             perGenre: perGenre,
                             fresh: fresh,
                             today: today,
                             genres: genres)
        }
    }

    private func buildBlocks(recommendations: [VideoItem],
                             segmentGenres: [String],
                             labels: [String: String],
                             perGenre: [String: [VideoItem]],
                             fresh: [VideoItem],
                             today: [VideoItem],
                             genres: [Genre]) {
        var blocks: [Block] = []

        if !recommendations.isEmpty {
            blocks.append(Block(
                kind: .grid,
                title: "为你推荐",
                actionTitle: "换一批 ↻",
                action: { [weak self] in self?.shuffleRecommendations() },
                videos: recommendations
            ))
        }

        let recent = Store.recent()
        if !recent.isEmpty {
            blocks.append(Block(
                kind: .rail,
                title: "最近观看",
                actionTitle: "清空",
                action: { [weak self] in
                    Store.clearRecent()
                    self?.rebuildRecentBlock()
                },
                videos: recent
            ))
        }

        if !today.isEmpty {
            let ranked = today.enumerated().map { index, item -> VideoItem in
                var copy = item
                copy.rank = index + 1
                return copy
            }
            blocks.append(Block(
                kind: .rail,
                title: "今日热门",
                actionTitle: "更多 ›",
                action: { [weak self] in
                    self?.pushGrid(source: .list(path: "/cn/hot", title: "热门"))
                },
                videos: ranked
            ))
        }

        for genre in segmentGenres {
            guard let items = perGenre[genre], !items.isEmpty else { continue }
            let display = labels[genre] ?? genre
            let slug = genres.first(where: { $0.name == display })?.slug
                ?? genre.lowercased().replacingOccurrences(of: " ", with: "-")
            blocks.append(Block(
                kind: .rail,
                title: display,
                actionTitle: "全部 ›",
                action: { [weak self] in
                    self?.pushGrid(source: .genre(slug: slug, title: display))
                },
                videos: items
            ))
        }

        if !fresh.isEmpty {
            blocks.append(Block(
                kind: .rail,
                title: "新发布",
                actionTitle: "更多 ›",
                action: { [weak self] in
                    self?.pushGrid(source: .list(path: "/cn/new", title: "新发布"))
                },
                videos: fresh
            ))
        }

        if !genres.isEmpty {
            blocks.append(Block(
                kind: .chips,
                title: "分类速览",
                actionTitle: "全部 ›",
                action: { [weak self] in
                    self?.pushCategory()
                },
                genres: Array(genres.prefix(14))
            ))
        }

        self.blocks = blocks

        if blocks.isEmpty {
            emptyView.configure(title: "加载失败", subtitle: "网络或接口异常，点重试再试一次")
            emptyView.isHidden = false
        }
        collectionView.reloadData()
    }

    private func rebuildRecentBlock() {
        guard let index = blocks.firstIndex(where: { $0.title == "最近观看" }) else { return }
        let recent = Store.recent()
        if recent.isEmpty {
            blocks.remove(at: index)
        } else {
            blocks[index].videos = recent
        }
        collectionView.reloadData()
    }

    private func shuffleRecommendations() {
        collectionView.refreshControl?.beginRefreshing()
        APIClient.shared.recommendations(count: 18) { [weak self] items in
            guard let self = self, !items.isEmpty else { return }
            guard let index = self.blocks.firstIndex(where: { $0.title == "为你推荐" }) else { return }
            self.blocks[index].videos = items
            UIView.performWithoutAnimation {
                self.collectionView.reloadSections(IndexSet(integer: index))
            }
        }
    }

    // MARK: - 跳转

    private func pushGrid(source: GridViewController.Source) {
        let controller = GridViewController(source: source)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func pushCategory() {
        navigationController?.pushViewController(CategoryViewController(), animated: true)
    }

    @objc private func handleRefresh() {
        load()
    }

    @objc private func toggleTheme() {
        _ = ThemeManager.shared.cycle()
        collectionView.reloadData()
    }
}

// MARK: - 数据源

extension HomeViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return blocks.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let block = blocks[section]
        return block.kind == .chips ? block.genres.count : block.videos.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let block = blocks[indexPath.section]

        if block.kind == .chips {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChipCell.reuseID, for: indexPath) as! ChipCell
            cell.configure(genre: block.genres[indexPath.item])
            return cell
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCardCell.reuseID, for: indexPath) as! VideoCardCell
        cell.configure(with: block.videos[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: SectionHeaderView.reuseID,
            for: indexPath
        ) as! SectionHeaderView

        let block = blocks[indexPath.section]
        header.configure(title: block.title, action: block.actionTitle, handler: block.action)
        return header
    }
}

// MARK: - 点击

extension HomeViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let block = blocks[indexPath.section]

        if block.kind == .chips {
            let genre = block.genres[indexPath.item]
            pushGrid(source: .genre(slug: genre.slug, title: genre.name))
            return
        }

        let item = block.videos[indexPath.item]
        navigationController?.pushViewController(DetailViewController(code: item.code), animated: true)
    }
}

import UIKit

/// 通用分页网格：分类 / 站点列表 / 搜索
final class GridViewController: UIViewController {

    enum Source {
        case genre(slug: String, title: String)
        case list(path: String, title: String)
        case search(keyword: String)
    }

    private let source: Source
    private var items: [VideoItem] = []
    private var page = 0
    private var hasMore = true
    private var isLoading = false
    private var keyword: String = ""

    private var collectionView: UICollectionView!
    private var searchBar: UISearchBar?
    private let emptyView = EmptyStateView()
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(source: Source) {
        self.source = source
        switch source {
        case .search(let word): keyword = word
        default: break
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        setupNavigationBar()
        setupSearchBarIfNeeded()
        setupCollectionView()
        setupEmptyView()

        switch source {
        case .genre(_, let title), .list(_, let title):
            title = title
            loadNextPage()
        case .search:
            title = "搜索"
            emptyView.configure(title: "搜点什么", subtitle: "支持番号、中文标题、女演员、制作商")
            emptyView.isHidden = false
        }
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

    private func setupSearchBarIfNeeded() {
        guard case .search = source else { return }
        let bar = UISearchBar()
        bar.placeholder = "搜索番号、标题、女演员"
        bar.searchBarStyle = .minimal
        bar.delegate = self
        bar.text = keyword
        bar.tintColor = Palette.accent
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6)
        ])
        searchBar = bar
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 14
        layout.sectionInset = UIEdgeInsets(top: 10, left: 12, bottom: 24, right: 12)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = Palette.background
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(VideoCardCell.self, forCellWithReuseIdentifier: VideoCardCell.reuseID)
        collectionView.register(UICollectionReusableView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                withReuseIdentifier: "footer")

        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        let topAnchor = searchBar?.bottomAnchor ?? view.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.collectionView = collectionView
    }

    private func setupEmptyView() {
        emptyView.isHidden = true
        emptyView.onRetry = { [weak self] in
            self?.page = 0
            self?.hasMore = true
            self?.loadNextPage()
        }
        view.addSubview(emptyView)
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyView.topAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            emptyView.bottomAnchor.constraint(equalTo: view.centerYAnchor, constant: 60)
        ])
    }

    // MARK: - 加载

    private func loadNextPage() {
        guard !isLoading, hasMore else { return }
        isLoading = true

        let next = page + 1
        let finish: ([VideoItem]) -> Void = { [weak self] list in
            guard let self = self else { return }
            self.isLoading = false
            self.page = next
            let added = list.filter { item in !self.items.contains(where: { $0.code == item.code }) }
            self.items.append(contentsOf: added)
            self.hasMore = list.count >= 10 && next < 60
            self.emptyView.isHidden = !self.items.isEmpty
            if self.items.isEmpty {
                self.emptyView.configure(title: "没有找到结果", subtitle: "换个关键词或分类再试")
            }
            self.collectionView.reloadData()
        }

        switch source {
        case .genre(let slug, _):
            APIClient.shared.genrePage(slug: slug, page: next, completion: finish)
        case .list(let path, _):
            APIClient.shared.listPage(path: path, page: next, completion: finish)
        case .search:
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                isLoading = false
                return
            }
            APIClient.shared.search(keyword: trimmed, page: next, completion: finish)
        }
    }
}

extension GridViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCardCell.reuseID, for: indexPath) as! VideoCardCell
        cell.configure(with: items[indexPath.item])
        return cell
    }
}

extension GridViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (collectionView.bounds.width - 24 - 10) / 2
        return CGSize(width: width, height: width * 2 / 3 + 46)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let item = items[indexPath.item]
        navigationController?.pushViewController(DetailViewController(code: item.code), animated: true)
    }

    func collectionView(_ collectionView: UICollectionView,
                        willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        if indexPath.item >= items.count - 4 {
            loadNextPage()
        }
    }
}

extension GridViewController: UISearchBarDelegate {

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        keyword = searchBar.text ?? ""
        items = []
        page = 0
        hasMore = true
        collectionView.reloadData()
        loadNextPage()
    }
}

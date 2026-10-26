import UIKit

/// 分类：快捷入口 + 全部分类（可筛选）
final class CategoryViewController: UIViewController {

    private let quickEntries: [(String, String)] = [
        ("新发布", "/cn/new"),
        ("热门", "/cn/hot"),
        ("最近", "/cn/recent"),
        ("有码", "/cn/censored"),
        ("无码", "/cn/uncensored"),
        ("无码泄露", "/cn/uncensored-leaked")
    ]

    private var tableView: UITableView!
    private let searchBar = UISearchBar()
    private var genres: [Genre] = []
    private var filtered: [Genre] = []
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        title = "分类"

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.background
        appearance.titleTextAttributes = [.foregroundColor: Palette.text]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance

        searchBar.placeholder = "筛选分类，如 中出 / 巨乳"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.tintColor = Palette.accent
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)

        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.backgroundColor = Palette.background
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.keyboardDismissMode = .onDrag
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        tableView = table

        spinner.color = Palette.secondaryText
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),

            table.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        spinner.startAnimating()
        APIClient.shared.allGenres { [weak self] list in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            self.genres = list
            self.filtered = list
            self.tableView.reloadData()
        }
    }

    private func push(_ source: GridViewController.Source) {
        navigationController?.pushViewController(GridViewController(source: source), animated: true)
    }
}

extension CategoryViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? quickEntries.count : filtered.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "快捷入口" : "全部分类（\(filtered.count)）"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.textProperties.color = Palette.text

        if indexPath.section == 0 {
            config.text = quickEntries[indexPath.row].0
            cell.backgroundColor = Palette.surface
        } else {
            let genre = filtered[indexPath.row]
            config.text = genre.name
            config.secondaryText = genre.count > 0 ? "\(genre.count)" : nil
            config.secondaryTextProperties.color = Palette.secondaryText
            config.prefersSideBySideTextAndSecondaryText = true
            cell.backgroundColor = Palette.surface
        }

        cell.accessoryType = .disclosureIndicator
        cell.contentConfiguration = config
        return cell
    }
}

extension CategoryViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 {
            let entry = quickEntries[indexPath.row]
            push(.list(path: entry.1, title: entry.0))
            return
        }

        let genre = filtered[indexPath.row]
        push(.genre(slug: genre.slug, title: genre.name))
    }
}

extension CategoryViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            filtered = genres
        } else {
            filtered = genres.filter {
                $0.name.lowercased().contains(trimmed) || $0.slug.contains(trimmed)
            }
        }
        tableView.reloadData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

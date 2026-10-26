import UIKit

/// 设置：外观 / 缓存 / 关于
final class SettingsViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var cacheSummary: String = "计算中…"
    private let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"

    private let themeOptions: [(String, ThemeMode)] = [
        ("跟随系统", .system),
        ("白天模式", .light),
        ("夜间模式", .dark)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        title = "设置"

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.background
        appearance.titleTextAttributes = [.foregroundColor: Palette.text]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = Palette.text

        tableView.backgroundColor = Palette.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        refreshCacheSummary()
    }

    private func refreshCacheSummary() {
        cacheSummary = CacheManager.summary()
        tableView.reloadSections(IndexSet(integer: 1), with: .none)
    }
}

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return themeOptions.count
        case 1: return 2
        default: return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "外观"
        case 1: return "存储"
        default: return "关于"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        return "视频是流式播放，不占存储；这里清的是封面图与请求缓存。"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.textProperties.color = Palette.text
        cell.backgroundColor = Palette.surface
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch indexPath.section {
        case 0:
            let option = themeOptions[indexPath.row]
            config.text = option.0
            config.textProperties.color = (ThemeManager.shared.mode == option.1) ? Palette.accent : Palette.text
            cell.accessoryType = (ThemeManager.shared.mode == option.1) ? .checkmark : .none

        case 1:
            if indexPath.row == 0 {
                config.text = "缓存占用"
                config.secondaryText = cacheSummary
                config.secondaryTextProperties.color = Palette.secondaryText
                config.prefersSideBySideTextAndSecondaryText = true
                cell.selectionStyle = .none
            } else {
                config.text = "清除全部缓存"
                config.textProperties.color = Palette.accent
            }

        default:
            config.text = "版本"
            config.secondaryText = version
            config.secondaryTextProperties.color = Palette.secondaryText
            config.prefersSideBySideTextAndSecondaryText = true
            cell.selectionStyle = .none
        }

        cell.contentConfiguration = config
        return cell
    }
}

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case 0:
            ThemeManager.shared.set(themeOptions[indexPath.row].1)
            tableView.reloadSections(IndexSet(integer: 0), with: .none)

        case 1 where indexPath.row == 1:
            let alert = UIAlertController(title: "清除全部缓存？",
                                          message: "会清掉封面图与请求缓存，不影响使用记录。下次打开需要重新加载图片。",
                                          preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
                CacheManager.clearAll {
                    self?.refreshCacheSummary()
                }
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
            alert.popoverPresentationController?.sourceView = tableView
            alert.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
            present(alert, animated: true, completion: nil)

        default:
            break
        }
    }
}

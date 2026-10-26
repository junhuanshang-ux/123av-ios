import UIKit

final class MainTabBarController: UITabBarController {

    private let shield = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()

        viewControllers = [
            wrap(HomeViewController(), title: "推荐", icon: "house.fill"),
            wrap(CategoryViewController(), title: "分类", icon: "square.grid.2x2.fill"),
            wrap(GridViewController(source: .search(keyword: "")), title: "搜索", icon: "magnifyingglass")
        ]

        applyAppearance()
        setupShield()
        observeLifecycle()
    }

    private func wrap(_ controller: UIViewController, title: String, icon: String) -> UINavigationController {
        let nav = UINavigationController(rootViewController: controller)
        nav.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: icon), selectedImage: nil)
        return nav
    }

    private func applyAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.background
        appearance.shadowColor = Palette.separator

        for item in [appearance.stackedLayoutAppearance,
                     appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = Palette.secondaryText
            item.normal.titleTextAttributes = [.foregroundColor: Palette.secondaryText]
            item.selected.iconColor = Palette.accent
            item.selected.titleTextAttributes = [.foregroundColor: Palette.accent]
        }

        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.tintColor = Palette.accent
        tabBar.unselectedItemTintColor = Palette.secondaryText
    }

    // MARK: - 隐私遮罩

    private func setupShield() {
        shield.backgroundColor = Palette.background
        shield.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "envelope.fill"))
        icon.tintColor = Palette.secondaryText
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        shield.addSubview(icon)

        view.addSubview(shield)
        NSLayoutConstraint.activate([
            shield.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shield.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shield.topAnchor.constraint(equalTo: view.topAnchor),
            shield.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            icon.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: shield.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 32)
        ])
        shield.isHidden = true
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(willResign), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func willResign() {
        shield.isHidden = false
    }

    @objc private func didBecomeActive() {
        if AuthGate.isFresh {
            shield.isHidden = true
            return
        }
        presentLock()
    }

    func presentLock() {
        guard presentedViewController == nil else { return }
        let lock = LockViewController()
        lock.modalPresentationStyle = .overFullScreen
        lock.modalTransitionStyle = .crossDissolve
        lock.onUnlocked = { [weak self] in
            self?.shield.isHidden = true
        }
        present(lock, animated: true, completion: nil)
    }
}

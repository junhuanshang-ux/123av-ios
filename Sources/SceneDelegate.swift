import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = Palette.background
        window.overrideUserInterfaceStyle = ThemeManager.shared.mode.interfaceStyle

        let tabBar = MainTabBarController()
        window.rootViewController = tabBar
        window.makeKeyAndVisible()
        self.window = window

        // 进入 App 先验面容（唯一一次验证点）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            tabBar.presentLock()
        }
    }
}

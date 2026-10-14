import UIKit

/// The native engine owns one window; UIKit owns its scene lifecycle.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene,
              session.role == .windowApplication else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = NativePortViewController()
        self.window = window
        window.makeKeyAndVisible()
    }

    // UIKit removes a presenting view's window during a full-screen modal.
    // The scene delegate retains stable ownership even while Cheats is open.
    func sceneWillResignActive(_ scene: UIScene) {
        (window?.rootViewController as? NativePortViewController)?.sceneDeactivated()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        (window?.rootViewController as? NativePortViewController)?.sceneActivated()
    }
}

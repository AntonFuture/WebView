import UIKit

// MARK: - To Get topViewController
extension UIApplication {
    func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? self.windows.first { $0.isKeyWindow }?.rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: WindowController?
    private let store = TaskStore()
    private var timer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "Quit DailyDot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); NSApp.mainMenu = menu
        controller = WindowController(store: store)
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.store.refreshDay() }
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil)
    }
    @objc private func refresh() { store.refreshDay() }
    func applicationDidBecomeActive(_ notification: Notification) { store.refreshDay() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

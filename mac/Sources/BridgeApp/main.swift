import AppKit
import SwiftUI
import Combine
import UserNotifications
import BridgeCore

// Pure-AppKit menu-bar app (reliable across ad-hoc builds, unlike SwiftUI MenuBarExtra). A status-bar
// item opens AppKit-hosted SwiftUI windows; inbound events show a custom banner (works without the
// notification entitlement that ad-hoc apps lack).
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate, NSMenuItemValidation {

    /// Phone-dependent menu items are greyed out while the phone is not connected.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openScreen) { return LinkManager.shared.status == .connected }
        if menuItem.action == #selector(pushClipboard) { return LinkManager.shared.status == .connected }
        return true
    }
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var screenWindow: NSWindow?
    private var screenShown = false
    private var toastPanels: [NSPanel] = []
    private var callPanel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        // Pin the item near the RIGHT edge of the menu bar: a crowded menu bar hides the
        // leftmost items first, so sitting rightmost keeps us visible. One-time migration
        // (v1) so the user can still ⌘-drag it afterwards and have that position stick.
        if !UserDefaults.standard.bool(forKey: "com.androidbridge.pinnedRight.v1") {
            UserDefaults.standard.set(100.0, forKey: "NSStatusItem Preferred Position AndroidBridge")
            UserDefaults.standard.set(true, forKey: "com.androidbridge.pinnedRight.v1")
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "AndroidBridge" // remember position if the user ⌘-drags it
        if let btn = statusItem.button {
            if let img = NSImage(systemSymbolName: "arrow.left.arrow.right.circle.fill", accessibilityDescription: "Android Bridge") {
                img.isTemplate = true
                btn.image = img
            } else {
                btn.title = "⟷"
            }
        }
        let menu = NSMenu()
        menu.addItem(appMenuItem("Open Bridge", action: #selector(openBridge), key: "o"))
        menu.addItem(appMenuItem("Open Meetings", action: #selector(openMeetings), key: "m"))
        menu.addItem(appMenuItem("Open Second Brain", action: #selector(openSecondBrain), key: "b"))
        menu.addItem(appMenuItem("Open Settings", action: #selector(openSettings), key: ","))
        menu.addItem(appMenuItem("Open Phone Screen", action: #selector(openScreen), key: "s"))
        menu.addItem(.separator())
        menu.addItem(quickActionsMenuItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Android Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        diag("statusItem created: visible=\(statusItem.isVisible) hasButton=\(statusItem.button != nil) hasImage=\(statusItem.button?.image != nil)")
        // macOS silently hides status items when the menu bar is full. If ours is occluded,
        // fall back to a Dock icon so the app is always reachable, and tell the user why.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            let hidden = self.statusItem.button?.window?.occlusionState.contains(.visible) == false
            self.diag("statusItem @6s: occludedByMenuBarOverflow=\(hidden)")
            guard hidden else { return }
            NSApp.setActivationPolicy(.regular)
            self.showToast(title: "Menu bar is full",
                           body: "macOS hid the Android Bridge icon — using a Dock icon instead. ⌘-drag other icons off the menu bar to make room.")
        }

        LinkManager.shared.start()

        LinkManager.shared.$screenImage.receive(on: RunLoop.main).sink { [weak self] img in
            guard let self else { return }
            if img != nil && !self.screenShown { self.screenShown = true; self.openScreenInternal(requestShare: false) }
            if img == nil { self.screenShown = false }
        }.store(in: &cancellables)

        LinkManager.shared.notificationSubject.receive(on: RunLoop.main).sink { [weak self] event in
            self?.showToast(title: event.title, body: event.body, userInfo: event.userInfo)
        }.store(in: &cancellables)

        LinkManager.shared.incomingCallSubject.receive(on: RunLoop.main).sink { [weak self] call in
            self?.showCallPanel(number: call.number, name: call.name)
        }.store(in: &cancellables)

        LinkManager.shared.callStateSubject.receive(on: RunLoop.main).sink { [weak self] ev in
            switch ev.state {
            case "active": self?.showActiveCallPanel(number: ev.number, name: ev.name)
            case "ended": self?.dismissCallPanel()
            default: break
            }
        }.store(in: &cancellables)

        openDashboard()
    }

    private func appMenuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func quickActionsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Quick Actions", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Quick Actions")
        menu.addItem(appMenuItem("Push Clipboard", action: #selector(pushClipboard), key: ""))
        item.submenu = menu
        return item
    }

    private func installMainMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        let edit = NSMenuItem()
        main.addItem(app)
        main.addItem(edit)

        let appMenu = NSMenu(title: "Android Bridge")
        appMenu.addItem(NSMenuItem(title: "Quit Android Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        app.submenu = appMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        edit.submenu = editMenu
        NSApp.mainMenu = main
    }

    @objc func openDashboard() {
        if window == nil {
            let size = AppUIState.windowSize()
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Android Bridge"
            w.isReleasedWhenClosed = false
            w.center()
            w.delegate = self
            w.contentView = NSHostingView(rootView: DashboardView(link: LinkManager.shared))
            window = w
            AppUIState.shared.window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func openBridge() {
        AppUIState.shared.selectedTab = 0
        openDashboard()
    }

    @objc func openMeetings() {
        AppUIState.shared.selectedTab = 1
        openDashboard()
    }

    @objc func openSecondBrain() {
        AppUIState.shared.selectedTab = 2
        openDashboard()
    }

    @objc func openSettings() {
        AppUIState.shared.selectedTab = 3
        openDashboard()
    }

    /// The size the user drags the dashboard to becomes the new default for every tab.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === window else { return }
        AppUIState.saveWindowSize(w.frame.size)
    }

    @objc func openScreen() {
        openScreenInternal(requestShare: true)
    }

    @objc func pushClipboard() {
        LinkManager.shared.sendClipboard(NSPasteboard.general.string(forType: .string) ?? "")
    }

    func openScreenInternal(requestShare: Bool) {
        if requestShare { LinkManager.shared.requestPhoneScreen() }
        if screenWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 800),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Phone Screen"
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: ScreenMirrorView(link: LinkManager.shared))
            screenWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        screenWindow?.makeKeyAndOrderFront(nil)
    }

    private func diag(_ s: String) {
        let line = "[\(Int(Date().timeIntervalSince1970))] \(s)\n"
        let url = URL(fileURLWithPath: "/tmp/androidbridge-diag.txt")
        if let fh = try? FileHandle(forWritingTo: url) { fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); try? fh.close() }
        else { try? line.data(using: .utf8)!.write(to: url) }
    }

    private func showToast(title: String, body: String, userInfo: [AnyHashable: Any] = [:]) {
        diag("TOAST_FIRED title=\(title)")
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.contentView = NSHostingView(rootView: ToastView(title: title, message: body) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
        }.onTapGesture {
            LinkManager.shared.handleNotificationClick(userInfo)
            panel.orderOut(nil)
        })
        if let vf = NSScreen.main?.visibleFrame {
            let offset = CGFloat(96 + toastPanels.count * 92)
            panel.setFrameOrigin(NSPoint(x: vf.maxX - 376, y: vf.maxY - offset))
        }
        panel.orderFrontRegardless()
        toastPanels.append(panel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            panel.orderOut(nil)
            self.toastPanels.removeAll { $0 == panel }
        }
    }

    /// Interactive top-right panel for a ringing phone: Answer / Decline act on the phone remotely.
    /// Unlike toasts this accepts clicks, so it must not be `ignoresMouseEvents`.
    private func showCallPanel(number: String, name: String) {
        diag("CALL_PANEL_FIRED name=\(name)")
        callPanel?.orderOut(nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 138),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        let dismiss: () -> Void = { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.callPanel === panel { self?.callPanel = nil }
        }
        panel.contentView = NSHostingView(rootView: IncomingCallView(
            name: name, number: number,
            onAnswer: { LinkManager.shared.answerCall(); dismiss() },
            onDecline: { LinkManager.shared.hangupCall(); dismiss() }))
        if let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.maxX - 356, y: vf.maxY - 154))
        }
        panel.orderFrontRegardless()
        callPanel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self, weak panel] in
            guard let panel, self?.callPanel === panel else { return }
            dismiss()
        }
    }

    /// Once a call is active, replace the ringing panel with an in-call panel (elapsed time + End Call).
    private func showActiveCallPanel(number: String, name: String) {
        diag("ACTIVE_CALL_PANEL name=\(name)")
        callPanel?.orderOut(nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 138),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        let dismiss: () -> Void = { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.callPanel === panel { self?.callPanel = nil }
        }
        panel.contentView = NSHostingView(rootView: ActiveCallView(
            name: name, number: number, start: Date(),
            onEnd: { LinkManager.shared.hangupCall(); dismiss() }))
        if let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.maxX - 356, y: vf.maxY - 154))
        }
        panel.orderFrontRegardless()
        callPanel = panel
    }

    /// The call ended on the phone — tear down whatever call panel is showing.
    private func dismissCallPanel() {
        diag("CALL_PANEL_DISMISS")
        callPanel?.orderOut(nil)
        callPanel = nil
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        LinkManager.shared.handleNotificationClick(response.notification.request.content.userInfo)
        completionHandler()
    }

    /// Clicking the Dock icon (fallback mode) reopens the dashboard.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openDashboard() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        m.addItem(appMenuItem("Open Bridge", action: #selector(openBridge), key: ""))
        m.addItem(appMenuItem("Open Meetings", action: #selector(openMeetings), key: ""))
        m.addItem(appMenuItem("Open Second Brain", action: #selector(openSecondBrain), key: ""))
        m.addItem(appMenuItem("Open Settings", action: #selector(openSettings), key: ""))
        m.addItem(appMenuItem("Open Phone Screen", action: #selector(openScreen), key: ""))
        m.addItem(.separator())
        m.addItem(quickActionsMenuItem())
        return m
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

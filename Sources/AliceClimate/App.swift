import AppKit
import SwiftUI
import Combine
import ClimateCore
import Darwin

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var readingsWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?
    private var store: ClimateStore!
    private let instanceGate: SingleInstanceGate
    private var reopenObserver: NSObjectProtocol?
    private var pendingReopen = false
    static let reopenNotification = Notification.Name("local.aliceclimate.reopen")
    static let notificationObject = String(getuid())

    init(instanceGate: SingleInstanceGate) throws {
        self.instanceGate = instanceGate
        super.init()
        // Install IPC before the application starts loading credentials or building views.
        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.reopenNotification, object: Self.notificationObject, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.revealMainWindow() }
        }
        try instanceGate.markReady()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ApplicationMenu.install()
        let demo = CommandLine.arguments.contains("--demo")
        NSApp.setActivationPolicy(demo ? .regular : .accessory)
        store = ClimateStore(isDemo: demo)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Климат дома: открыть показания")
        }
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ClimateMenu(store: store, openSettings: { [weak self] in self?.showSettings() }))
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.store.refresh() }
        }
        updateTitle()
        store.start()
        if store.isDemo {
            showReadingsWindow()
        } else if !store.hasToken {
            showSettings()
        }
        if pendingReopen { pendingReopen = false; revealMainWindow() }
    }

    private func updateTitle() {
        statusItem.button?.title = store.title
        let selected = store.selected
        statusItem.button?.toolTip = selected.map { "\($0.room.isEmpty ? $0.name : $0.room) · \($0.name)\n\($0.measurementDescription(at: Date()))" } ?? "Алиса Климат"
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        store.now = Date()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showReadingsWindow() {
        if readingsWindow == nil {
            let view = NSHostingView(rootView: ClimateMenu(store: store, openSettings: { [weak self] in self?.showSettings() }))
            let size = view.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = store.isDemo ? "Алиса Климат — демо" : "Алиса Климат — показания"
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.center()
            readingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        readingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard store != nil else { return true }
        revealMainWindow()
        return true
    }

    private func revealMainWindow() {
        guard store != nil else { pendingReopen = true; return }
        if store.isDemo || store.hasToken { showReadingsWindow() }
        else { showSettings() }
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Алиса Климат — подключение"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ConnectionSettings(store: store, done: { [weak self] in self?.settingsWindow?.close() }))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct AliceClimateApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        do {
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("local.aliceclimate-\(getuid()).lock").path
            let gate = try SingleInstanceGate(path: path)
            guard gate.isPrimary else {
                // A concurrent first launch may still be constructing its windows.
                for _ in 0..<60 {
                    if gate.ownerIsReady { break }
                    Thread.sleep(forTimeInterval: 0.05)
                }
                guard gate.ownerIsReady else {
                    application.setActivationPolicy(.regular)
                    application.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "Алиса Климат ещё запускается"
                    alert.informativeText = "Другая копия уже запускается. Дождитесь её открытия и повторите запуск, если окно не появится. Дополнительная копия не будет запущена."
                    alert.runModal()
                    return
                }
                DistributedNotificationCenter.default().postNotificationName(
                    AppDelegate.reopenNotification, object: AppDelegate.notificationObject,
                    userInfo: nil, deliverImmediately: true
                )
                if let pid = gate.ownerPID {
                    NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                }
                return
            }
            let delegate = try AppDelegate(instanceGate: gate)
            application.delegate = delegate
            withExtendedLifetime((delegate, gate)) { application.run() }
        } catch {
            application.setActivationPolicy(.regular)
            application.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Не удалось запустить Алиса Климат"
            alert.informativeText = "Не удалось проверить, запущено ли приложение. Повторите запуск. \(error.localizedDescription)"
            alert.runModal()
        }
    }
}

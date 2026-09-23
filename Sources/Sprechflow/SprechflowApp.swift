import SwiftUI
import Combine
import SprechflowCore

@main
struct SprechflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Einstellungen …") { delegate.openSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private let hotKey = HotKey()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var hud: NSPanel?
    private var observation: AnyCancellable?
    private var menuSignature = ""
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sprechflow")
        statusItem.button?.toolTip = "Sprechflow · Strg + Alt halten oder zweimal drücken"
        state.showSettings = { [weak self] in self?.openSettings() }
        state.showResult = { [weak self] in self?.openResult() }
        hotKey.start = { [weak self] handsFree in self?.state.startFromShortcut(handsFree: handsFree) ?? false }
        hotKey.stop = { [weak self] in self?.state.stop() }
        state.recordingEnded = { [weak self] in self?.hotKey.reset() }
        state.shortcutAvailable = hotKey.register()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let allowed = TextInsertion.permitted
                if allowed != self.state.hasAccessibilityPermission {
                    self.state.hasAccessibilityPermission = allowed
                    if !allowed && (self.state.recording || self.state.starting) { self.state.stop() }
                    self.state.shortcutAvailable = self.hotKey.register()
                }
            }
        }
        observation = state.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenuAndHUD() }
        }
        updateMenuAndHUD()
        Task { await state.refreshModels() }
        openSettings()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        state.cancel()
        guard state.recording || state.starting else { return .terminateNow }
        Task {
            while state.recording || state.starting { try? await Task.sleep(for: .milliseconds(100)) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func item(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func updateMenuAndHUD() {
        // Level updates redraw the HUD through SwiftUI; do not replace an open menu 10 times a second.
        let signature = "\(state.phase)|\(state.recording)|\(state.busy)|\(state.starting)|\(state.notice)"
        guard signature != menuSignature else { return }
        menuSignature = signature
        let menu = NSMenu()
        menu.addItem(item("Sprechflow · \(state.phase)", nil))
        menu.addItem(.separator())
        let record = item(state.recording ? "Aufnahme beenden" : "Diktat starten", #selector(toggle))
        record.isEnabled = !state.busy && !state.starting
        menu.autoenablesItems = false
        menu.addItem(record)
        if state.busy || state.recording { menu.addItem(item("Abbrechen", #selector(cancel))) }
        menu.addItem(item("Letztes Diktat …", #selector(openResult)))
        menu.addItem(item("Einstellungen …", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Sprechflow beenden", #selector(quit)))
        statusItem.menu = menu
        statusItem.button?.contentTintColor = state.recording ? .systemRed : nil
        if state.recording || state.busy || state.starting || !state.notice.isEmpty {
            if hud == nil {
                let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 466, height: 120), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isFloatingPanel = true; panel.level = .floating
                panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.contentView = NSHostingView(rootView: RecordingHUD(state: state))
                hud = panel
            }
            if let screen = NSScreen.main {
                hud?.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 233, y: screen.visibleFrame.minY + 35))
            }
            hud?.orderFrontRegardless()
        } else { hud?.orderOut(nil) }
    }

    @objc func openSettings() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Sprechflow"
            w.contentView = NSHostingView(rootView: SettingsView(state: state))
            w.minSize = NSSize(width: 860, height: 660)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc func openResult() { openSettings(); NotificationCenter.default.post(name: .showSprechflowResult, object: nil) }
    @objc func toggle() { state.toggleRecording() }
    @objc func cancel() { state.cancel() }
    @objc func quit() { state.cancel(); NSApp.terminate(nil) }
}

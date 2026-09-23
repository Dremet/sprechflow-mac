import AppKit
import Carbon
import SprechflowCore

@MainActor
final class HotKey {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var timer: Timer?
    private var gesture = DictationGesture()
    var start: ((Bool) -> Bool)?
    var stop: (() -> Void)?

    func register() -> Bool {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                self?.receive(event)
                return event
            }
        }
        if !TextInsertion.permitted {
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
            reset()
            return false
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in self?.receive(event) }
        }
        return globalMonitor != nil && localMonitor != nil
    }

    func reset() { timer?.invalidate(); timer = nil; gesture.reset() }

    private func receive(_ event: NSEvent) {
        if event.type == .keyDown {
            gesture.otherKeyPressed()
        } else {
            let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])
            perform(gesture.modifiersChanged(chordIsDown: flags == [.control, .option], at: ProcessInfo.processInfo.systemUptime))
        }
        schedule()
    }

    private func perform(_ actions: [DictationGesture.Action]) {
        for action in actions {
            switch action {
            case .startHold, .startHandsFree:
                if start?(action == .startHandsFree) != true { reset() }
            case .stop: stop?()
            }
        }
    }

    private func schedule() {
        timer?.invalidate(); timer = nil
        guard let deadline = gesture.deadline else { return }
        let next = Timer(timeInterval: max(0.001, deadline - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.perform(self.gesture.tick(at: ProcessInfo.processInfo.systemUptime))
                self.schedule()
            }
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }
}

@MainActor
enum TextInsertion {
    enum Outcome {
        case posted, permissionMissing, targetMissing, targetChanged, modifiersHeld, eventFailed
        var message: String {
            switch self {
            case .posted: return "Einfügen gesendet. Dein Text liegt auch in der Zwischenablage."
            case .permissionMissing: return "Text erkannt, aber macOS blockiert das Einfügen. Bitte Sprechflow in den Bedienungshilfen freigeben."
            case .targetMissing: return "Text kopiert. Bitte ein Textfeld in deiner Ziel-App anklicken und mit Windows-Taste + V einfügen."
            case .targetChanged: return "Text kopiert. Du hast die App gewechselt; bitte mit Windows-Taste + V einfügen."
            case .modifiersHeld: return "Text kopiert. Bitte die gedrückten Tasten loslassen und mit Windows-Taste + V einfügen."
            case .eventFailed: return "Automatisches Einfügen nicht möglich. Der Text liegt in der Zwischenablage."
            }
        }
    }
    static var permitted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    static func insert(_ text: String, target: NSRunningApplication?) async throws -> Outcome {
        try Task.checkCancellation()
        copy(text)
        guard permitted else { return .permissionMissing }
        guard let target, !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .targetMissing }
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard currentPID == target.processIdentifier || currentPID == ProcessInfo.processInfo.processIdentifier else { return .targetChanged }
        target.activate(options: [])
        try await Task.sleep(for: .milliseconds(250))
        // Do not combine the synthetic Cmd+V with a still-held physical chord.
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        for _ in 0..<40 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty else { return .modifiersHeld }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return .targetChanged }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return .eventFailed }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return .posted
    }
}

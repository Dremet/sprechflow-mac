import AppKit
import AVFoundation
import SwiftUI
import SprechflowCore

@MainActor
final class AppState: ObservableObject {
    @Published var preferences: Preferences { didSet { do { try Storage.save(preferences, name: "preferences.json") } catch { message = "Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)" } } }
    @Published var models: [RouterModel] = []
    @Published var microphones: [Microphone] = []
    @Published var keyDraft = ""
    @Published var hasKey = false
    @Published var message = ""
    @Published var catalogMessage = ""
    @Published var keyMessage = ""
    @Published var loadingModels = false
    @Published var checkingKey = false
    @Published var phase = "Bereit"
    @Published var recording = false
    @Published var testingMicrophone = false
    @Published var busy = false
    @Published var starting = false
    @Published var level: Float = 0
    @Published var elapsed = 0
    @Published var result = ""
    @Published var rawTranscript = ""
    @Published var shortcutAvailable = false
    @Published var hasAccessibilityPermission = TextInsertion.permitted
    @Published var handsFree = false
    @Published var notice = ""
    @Published var noticeNeedsPermission = false
    private let recorder = Recorder()
    private let router = OpenRouter()
    private var target: NSRunningApplication?
    private var snapshot = Preferences()
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var discard = false
    private var stopWhenReady = false
    private var noticeTask: Task<Void, Never>?
    private var audioForRetry: Data?
    private var observers: [NSObjectProtocol] = []
    var showSettings: (() -> Void)?
    var showResult: (() -> Void)?
    var recordingEnded: (() -> Void)?
    var canRetry: Bool { audioForRetry != nil && !busy && !recording && !starting }

    init() {
        preferences = Storage.load(Preferences.self, name: "preferences.json") ?? Preferences()
        models = Storage.load([RouterModel].self, name: "models.json") ?? []
        if !models.isEmpty { catalogMessage = "Gespeicherter Modellkatalog. Aktualisierung läuft …" }
        do { hasKey = !(try Keychain.load()).isEmpty } catch { keyMessage = error.localizedDescription }
        refreshMicrophones()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshMicrophones() }
            })
        }
    }

    func refreshMicrophones() { microphones = Recorder.microphones() }
    func refreshModels() async {
        guard !loadingModels else { return }
        loadingModels = true
        defer { loadingModels = false }
        do {
            let fresh = try await router.models()
            guard !fresh.isEmpty else { throw FlowError.message("Der Modellkatalog ist leer.") }
            models = fresh
            try Storage.save(models, name: "models.json")
            catalogMessage = "\(models.filter(\.acceptsAudio).count) Audiomodelle · \(models.filter(\.acceptsText).count) Textmodelle · gerade aktualisiert"
        } catch { catalogMessage = "Aktualisierung fehlgeschlagen: \(error.localizedDescription)" }
    }

    func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { keyMessage = "Bitte einen OpenRouter-API-Schlüssel eingeben."; return }
        do { try Keychain.save(key); hasKey = true; keyDraft = ""; keyMessage = "Sicher im Schlüsselbund gespeichert." } catch { keyMessage = error.localizedDescription }
    }
    func deleteKey() {
        do { try Keychain.delete(); hasKey = false; keyDraft = ""; keyMessage = "API-Schlüssel gelöscht." } catch { keyMessage = error.localizedDescription }
    }
    func checkKey() async {
        checkingKey = true
        defer { checkingKey = false }
        do { try await router.validateKey(Keychain.load()); keyMessage = "Verbindung erfolgreich. Dein API-Schlüssel ist gültig." } catch { keyMessage = error.localizedDescription }
    }

    func toggleRecording() {
        if recording || starting { stop(); return }
        _ = startRecording(handsFree: true)
    }

    func startFromShortcut(handsFree: Bool) -> Bool {
        if recording || starting { stop(); return false }
        return startRecording(handsFree: handsFree)
    }

    private func startRecording(handsFree: Bool) -> Bool {
        guard !busy && !starting else { return false }
        if !hasKey { message = "Bitte zuerst deinen OpenRouter-API-Schlüssel speichern."; showSettings?(); return false }
        guard models.contains(where: { $0.id == preferences.sttModel && $0.acceptsAudio }) else { message = "Bitte ein verfügbares Audiomodell auswählen."; showSettings?(); return false }
        guard !preferences.processText || models.contains(where: { $0.id == preferences.textModel && $0.acceptsText }) else { message = "Bitte ein verfügbares Textmodell auswählen."; showSettings?(); return false }
        target = NSWorkspace.shared.frontmostApplication
        snapshot = preferences
        self.handsFree = handsFree
        begin(test: false)
        return true
    }

    func toggleMicrophoneTest() {
        if testingMicrophone { stop(); return }
        guard !busy && !recording && !starting else { return }
        begin(test: true)
    }

    private func begin(test: Bool) {
        if !test { audioForRetry = nil }
        dismissNotice()
        stopWhenReady = false
        starting = true; discard = false; message = ""; elapsed = 0; level = 0
        testingMicrophone = test
        phase = "Mikrofon wird gestartet …"
        Task { [self] in
            do {
                try await recorder.start(deviceID: preferences.microphoneID, onLevel: { [weak self] value in
                    Task { @MainActor in self?.level = value }
                }, onFinish: { [weak self] result in
                    Task { @MainActor in self?.finishedRecording(result, test: test) }
                })
                starting = false; recording = true
                if discard || stopWhenReady { recorder.stop(); return }
                phase = test ? "Mikrofontest · bleibt lokal" : "Ich höre zu …"
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.elapsed += 1
                        if self.elapsed >= (test ? 15 : 180) { self.stop() }
                    }
                }
            } catch {
                starting = false; testingMicrophone = false; phase = "Bereit"; message = error.localizedDescription
                recordingEnded?()
                showNotice(message)
            }
        }
    }

    func stop() {
        if starting { stopWhenReady = true; return }
        guard recording else { return }
        timer?.invalidate(); timer = nil; phase = "Aufnahme wird beendet …"; recorder.stop()
    }
    func cancel() {
        discard = true
        if recording { stop() }
        task?.cancel()
        if busy { phase = "Wird abgebrochen …" }
    }

    private func finishedRecording(_ captured: Result<URL, Error>, test: Bool) {
        timer?.invalidate(); timer = nil
        recording = false; testingMicrophone = false; level = 0; phase = "Bereit"
        recordingEnded?()
        do {
            let url = try captured.get()
            defer { try? FileManager.default.removeItem(at: url) }
            guard !discard else { return }
            if test { message = "Mikrofontest beendet. Die Testaufnahme wurde gelöscht."; return }
            let audio = try Data(contentsOf: url)
            guard elapsed >= 1, audio.count > 1000 else { throw FlowError.message("Aufnahme zu kurz. Bitte mindestens eine Sekunde sprechen.") }
            audioForRetry = audio
            process(audio)
        } catch { message = error.localizedDescription; showResult?() }
    }

    func retry() {
        guard let audio = audioForRetry, canRetry else { return }
        snapshot = preferences
        process(audio)
    }

    private func process(_ audio: Data) {
        busy = true; message = ""; rawTranscript = ""; result = ""; phase = "Wird transkribiert …"
        let settings = snapshot
        task = Task {
            defer { busy = false; phase = "Bereit"; task = nil }
            do {
                guard let model = models.first(where: { $0.id == settings.sttModel && $0.acceptsAudio }) else { throw FlowError.message("Audiomodell nicht mehr verfügbar. Bitte neu auswählen.") }
                let key = try Keychain.load()
                let transcript = try await router.transcribe(audio: audio, model: model, preferences: settings, key: key)
                try Task.checkCancellation()
                rawTranscript = transcript
                result = transcript
                if settings.processText {
                    phase = "Text wird überarbeitet …"
                    do { result = try await router.polish(transcript, preferences: settings, key: key) }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        try Task.checkCancellation()
                        message = "Überarbeitung fehlgeschlagen. Das ursprüngliche Transkript bleibt erhalten. \(error.localizedDescription)"
                        showResult?()
                        return
                    }
                }
                try Task.checkCancellation()
                if settings.autoPaste {
                    let outcome = try await TextInsertion.insert(result, target: target)
                    try Task.checkCancellation()
                    message = outcome.message
                    hasAccessibilityPermission = TextInsertion.permitted
                    showNotice(message, permission: !hasAccessibilityPermission)
                } else { TextInsertion.copy(result); message = "Text kopiert. Auf deiner PC-Tastatur mit Windows-Taste + V einfügen."; showNotice(message) }
                audioForRetry = nil
            } catch {
                if Task.isCancelled { message = "Verarbeitung abgebrochen." }
                else { message = error.localizedDescription; showResult?() }
            }
        }
    }

    func clearResult() { result = ""; rawTranscript = ""; audioForRetry = nil; message = "" }

    func testInsertion() {
        guard !busy && !recording && !starting else { return }
        dismissNotice()
        busy = true
        task = Task {
            defer { busy = false; phase = "Bereit"; task = nil }
            do {
                for remaining in (1...10).reversed() {
                    phase = "Textfeld anklicken · Test in \(remaining) s"
                    try await Task.sleep(for: .seconds(1))
                }
                let destination = NSWorkspace.shared.frontmostApplication
                let outcome = try await TextInsertion.insert("Sprechflow-Test", target: destination)
                message = outcome.message
                showNotice(message, permission: !TextInsertion.permitted)
            } catch { message = "Einfügetest abgebrochen." }
        }
    }

    func dismissNotice() { noticeTask?.cancel(); noticeTask = nil; notice = ""; noticeNeedsPermission = false }
    private func showNotice(_ text: String, permission: Bool = false) {
        dismissNotice()
        noticeNeedsPermission = permission
        notice = text
        noticeTask = Task {
            do { try await Task.sleep(for: .seconds(permission ? 20 : 8)); notice = "" } catch {}
        }
    }
}

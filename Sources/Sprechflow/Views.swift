import SwiftUI
import AVFoundation
import SprechflowCore

// Explicit alias keeps the property wrapper compatible with SDKs that also declare a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private let accent = Color(red: 0.32, green: 0.34, blue: 0.85)

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ViewState<String> private var tab = "Allgemein"
    private let tabs = [("Allgemein", "slider.horizontal.3"), ("Modelle", "sparkles"), ("Wörterbuch", "text.book.closed"), ("Letztes Diktat", "text.alignleft")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 24, weight: .bold)).foregroundStyle(accent)
                    Text("sprechflow").font(.system(size: 22, weight: .bold, design: .rounded)).lineLimit(1)
                }.padding(.vertical, 25)
                Text("DEINE STIMME. DEIN TEXT.").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary).padding(.bottom, 20)
                ForEach(tabs, id: \.0) { name, icon in
                    Button { tab = name } label: {
                        Label(name, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(11)
                            .background(tab == name ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(tab == name ? accent : .primary)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label("Strg + Alt", systemImage: "keyboard").font(.callout.weight(.medium))
                Text("Halten zum Sprechen. Zweimal kurz für Daueraufnahme.").font(.caption).foregroundStyle(.secondary)
                Text("Version 1.0 · macOS").font(.caption2).foregroundStyle(.tertiary).padding(.top, 14)
            }.padding(20).frame(width: 230).background(.quaternary.opacity(0.35))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tab).font(.system(size: 29, weight: .bold))
                        Text(subtitle).foregroundStyle(.secondary)
                    }.padding(.bottom, 4)
                    switch tab {
                    case "Modelle": ModelsView(state: state)
                    case "Wörterbuch": VocabularyView(state: state)
                    case "Letztes Diktat": ResultView(state: state)
                    default: GeneralView(state: state)
                    }
                    if !state.message.isEmpty { Label(state.message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(minWidth: 860, minHeight: 660).tint(accent)
        .onReceive(NotificationCenter.default.publisher(for: .showSprechflowResult)) { _ in tab = "Letztes Diktat" }
    }
    var subtitle: String {
        switch tab {
        case "Modelle": return "Zwei Schritte, ein flüssiges Diktat. Du wählst die Modelle."
        case "Wörterbuch": return "Damit Namen, Fachbegriffe und Lieblingswörter richtig ankommen."
        case "Letztes Diktat": return "Dein jüngstes Ergebnis – nur für diese Sitzung."
        default: return "Sprechen statt tippen. In der App, in der du gerade arbeitest."
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1))
    }
}

struct GeneralView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Card(title: "OpenRouter verbinden") {
            Label(state.hasKey ? "API-Schlüssel gespeichert" : "API-Schlüssel fehlt", systemImage: state.hasKey ? "checkmark.shield.fill" : "key.fill")
                .foregroundStyle(state.hasKey ? .green : .secondary)
            HStack {
                SecureField(state.hasKey ? "Neuen Schlüssel eingeben …" : "sk-or-v1-…", text: $state.keyDraft).textFieldStyle(.roundedBorder)
                Button("Speichern") { state.saveKey() }.disabled(state.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Button(state.checkingKey ? "Prüft …" : "Verbindung prüfen") { Task { await state.checkKey() } }.disabled(!state.hasKey || state.checkingKey)
                Link("API-Schlüssel erstellen ↗", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                Spacer()
                if state.hasKey { Button("Löschen", role: .destructive) { state.deleteKey() } }
            }.font(.callout)
            if !state.keyMessage.isEmpty { Text(state.keyMessage).font(.caption).foregroundStyle(.secondary) }
            Text("Dein Schlüssel bleibt im macOS-Schlüsselbund. Diktate werden zum Erkennen und Überarbeiten an OpenRouter und den gewählten Modellanbieter gesendet. Es gelten deren Preise und Datenrichtlinien.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Card(title: "Mikrofon") {
            Picker("Eingabegerät", selection: $state.preferences.microphoneID) {
                Text("Systemstandard verwenden").tag("")
                ForEach(state.microphones) { mic in Text(mic.name).tag(mic.id) }
                if !state.preferences.microphoneID.isEmpty && !state.microphones.contains(where: { $0.id == state.preferences.microphoneID }) {
                    Text("Gespeichertes Mikrofon · nicht verbunden").tag(state.preferences.microphoneID)
                }
            }.disabled(state.recording || state.starting)
            Text("Diese Auswahl gilt nur für Sprechflow. Deine systemweite Mikrofoneinstellung wird nicht verändert.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ProgressView(value: Double(state.level)).tint(state.level > 0.85 ? .orange : accent)
                Button(state.testingMicrophone ? "Test beenden" : "Mikrofon testen") { state.toggleMicrophoneTest() }.disabled(state.busy || state.starting || (state.recording && !state.testingMicrophone))
                Button { state.refreshMicrophones() } label: { Image(systemName: "arrow.clockwise") }.help("Mikrofone neu laden")
            }
            Text("Der Test dauert maximal 15 Sekunden, bleibt lokal und wird danach gelöscht.").font(.caption).foregroundStyle(.secondary)
        }
        Card(title: "Diktieren & Einfügen") {
            Label("Strg + Alt · ohne Leertaste", systemImage: "keyboard")
            Text("Gedrückt halten: sprechen, dann zum Beenden loslassen.\nZweimal kurz drücken: ohne Halten diktieren. Noch einmal drücken beendet die Aufnahme.").font(.callout)
            Text("PC-Tastatur: Strg und die linke Alt-Taste. Mac-Tastatur: Control und Option.").font(.caption).foregroundStyle(.secondary)
            if !state.shortcutAvailable { Text("Für Strg + Alt in anderen Apps bitte Bedienungshilfen freigeben. Bis dahin kannst du über das Menüleisten-Icon aufnehmen.").foregroundStyle(.orange).font(.caption) }
            Toggle("Automatisch in die ursprüngliche App einfügen", isOn: $state.preferences.autoPaste)
            HStack {
                Button("Einfügen testen (10 Sek.)") { state.testInsertion() }.disabled(state.busy || state.recording || state.starting)
                Text("Danach ein leeres Textfeld anklicken. Fügt ‚Sprechflow-Test‘ ohne Zeilenumbruch ein; keine API-Anfrage.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Label(state.hasAccessibilityPermission ? "Bedienungshilfen erlaubt" : "macOS blockiert automatisches Einfügen", systemImage: state.hasAccessibilityPermission ? "checkmark.circle" : "hand.raised")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Systemeinstellungen öffnen") { TextInsertion.requestPermission() }
            }
            if !state.hasAccessibilityPermission {
                Text("In Datenschutz & Sicherheit → Bedienungshilfen Sprechflow einschalten. Bei neueren macOS-Versionen kann der Bereich ‚Gerätesteuerung & Datenzugriff‘ heißen. Fehlt die App, über + den Eintrag Programme → Sprechflow hinzufügen. Nach einem Update bei Bedarf den alten Eintrag entfernen und die App erneut hinzufügen.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Manuell einfügen: auf einer PC-Tastatur Windows-Taste + V, auf einer Mac-Tastatur Command + V. Aufnahmen enden nach spätestens 3 Minuten.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ModelsView: View {
    @ObservedObject var state: AppState
    @ViewState<Bool?> private var choosingAudio: Bool? = nil
    var body: some View {
        Card(title: "1 · Sprache erkennen") {
            modelButton(audio: true)
            Picker("Sprache", selection: $state.preferences.language) {
                Text("Deutsch").tag("de"); Text("Automatisch erkennen").tag(""); Text("English").tag("en"); Text("Français").tag("fr"); Text("Español").tag("es")
            }
            Text("Zum Einstieg: Whisper für reine Transkription. Wenn Eigennamen schwierig sind, probiere ein Audio-Sprachmodell wie Gemini mit deinem Wörterbuch. Vergleiche mit demselben kurzen Diktat.").font(.callout).foregroundStyle(.secondary)
        }
        Card(title: "2 · Text überarbeiten") {
            Toggle("Diktat nach der Erkennung überarbeiten", isOn: $state.preferences.processText)
            modelButton(audio: false).disabled(!state.preferences.processText)
            Picker("Schreibstil", selection: $state.preferences.style) { ForEach(WritingStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.disabled(!state.preferences.processText)
            Text(state.preferences.style.instruction).font(.caption).foregroundStyle(.secondary)
            Text("Zum Einstieg: Gemini Flash Lite für kurze Alltagsdiktate. Für komplexe Formulierungen kannst du größere Modelle vergleichen. Geschwindigkeit und Qualität hängen vom Anbieter ab.").font(.callout).foregroundStyle(.secondary)
            if !state.preferences.processText { Text("Bei speziellen STT-Modellen greift dein Wörterbuch nur mit aktivierter Überarbeitung.").font(.caption).foregroundStyle(.orange) }
        }
        HStack {
            Button(state.loadingModels ? "Lädt …" : "Modellliste aktualisieren") { Task { await state.refreshModels() } }.disabled(state.loadingModels)
            Text(state.catalogMessage).font(.caption).foregroundStyle(.secondary)
        }
        Text("Die Auswahl zeigt nur Modelle mit passender Ein- und Ausgabe. Preise und Verfügbarkeit kommen aus dem OpenRouter-Katalog; kostenlose Modelle können stärker begrenzt sein.").font(.caption).foregroundStyle(.secondary)
            .sheet(isPresented: Binding(get: { choosingAudio != nil }, set: { if !$0 { choosingAudio = nil } })) {
                ModelChooser(state: state, audio: choosingAudio ?? true)
            }
    }
    func modelButton(audio: Bool) -> some View {
        let id = audio ? state.preferences.sttModel : state.preferences.textModel
        let model = state.models.first { $0.id == id }
        return Button { choosingAudio = audio } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model?.name ?? id).font(.headline)
                    Text(model == nil ? "Verfügbarkeit prüfen · Modell auswählen" : id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
            }.padding(12).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}

struct ModelChooser: View {
    @ObservedObject var state: AppState
    let audio: Bool
    @Environment(\.dismiss) var dismiss
    @ViewState<String> private var search = ""
    var filtered: [RouterModel] {
        state.models.filter { (audio ? $0.acceptsAudio : $0.acceptsText) && (search.isEmpty || ($0.name + $0.id).localizedCaseInsensitiveContains(search)) }
            .sorted { a, b in
                let ar = rank(a), br = rank(b)
                return ar == br ? a.name < b.name : ar < br
            }
    }
    func rank(_ model: RouterModel) -> Int {
        if model.id == (audio ? "openai/whisper-1" : "google/gemini-2.5-flash-lite") { return 0 }
        if audio && model.isTranscription { return 1 }
        return 2
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(audio ? "Modell für Spracherkennung" : "Modell für Textüberarbeitung").font(.title2.bold()); Spacer(); Button("Fertig") { dismiss() } }
            TextField("Modelle durchsuchen …", text: $search).textFieldStyle(.roundedBorder)
            if filtered.isEmpty { ContentUnavailableView("Keine Modelle gefunden", systemImage: "magnifyingglass", description: Text("Suche anpassen oder Modellliste aktualisieren.")) }
            List(filtered) { model in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.name).font(.headline)
                        if rank(model) == 0 { Text("Zum Einstieg").font(.caption).padding(4).background(accent.opacity(0.1), in: Capsule()) }
                        Spacer()
                        Button((audio ? state.preferences.sttModel : state.preferences.textModel) == model.id ? "Ausgewählt ✓" : "Auswählen") {
                            if audio { state.preferences.sttModel = model.id } else { state.preferences.textModel = model.id }
                            dismiss()
                        }
                    }
                    Text(model.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(audio ? model.guidance : "Für Zeichensetzung, Füllwörter und Formulierungen. Starte mit einem günstigen kleinen Modell; größere Modelle lohnen sich bei anspruchsvollen Texten.").font(.callout)
                    Text(model.textPrice).font(.caption).foregroundStyle(.secondary)
                    Link("Details & Preise auf OpenRouter ↗", destination: URL(string: "https://openrouter.ai/" + model.id)!).font(.caption)
                }.padding(.vertical, 9)
            }.listStyle(.inset)
        }.padding(24).frame(width: 710, height: 590)
    }
}

struct VocabularyView: View {
    @ObservedObject var state: AppState
    @ViewState<String> private var word = ""
    @ViewState<String> private var aliases = ""
    @ViewState<String> private var note = ""
    var body: some View {
        Card(title: "Neues Wort hinzufügen") {
            TextField("Richtige Schreibweise, z. B. Sprechflow", text: $word).textFieldStyle(.roundedBorder)
            TextField("Oft falsch erkannt als … (optional)", text: $aliases).textFieldStyle(.roundedBorder)
            HStack { Text("Zum Beispiel: Sprech Flow, Sprechflo").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Hinzufügen", action: add).buttonStyle(.borderedProminent).disabled(word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        Text("\(state.preferences.vocabulary.count) gespeicherte Wörter").font(.headline)
        if state.preferences.vocabulary.isEmpty {
            ContentUnavailableView("Deine Wörter, richtig geschrieben", systemImage: "text.book.closed", description: Text("Ergänze Namen, Projekte und Fachbegriffe, die du häufig diktierst."))
        }
        ForEach($state.preferences.vocabulary) { $entry in
            HStack {
                VStack(alignment: .leading) {
                    TextField("Schreibweise", text: $entry.word).font(.headline)
                    TextField("Alternative Erkennungen", text: $entry.aliases).font(.caption)
                }.textFieldStyle(.roundedBorder)
                Button(role: .destructive) { state.preferences.vocabulary.removeAll { $0.id == entry.id } } label: { Image(systemName: "trash") }.help("Wort entfernen")
            }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        }
        Text("Änderungen werden automatisch gespeichert. Wörter werden als Kontexthilfe verwendet; eine bestimmte Erkennung kann das Modell nicht garantieren.").font(.caption).foregroundStyle(.secondary)
    }
    func add() {
        let value = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !state.preferences.vocabulary.contains(where: { $0.word.caseInsensitiveCompare(value) == .orderedSame }) else { note = "Dieses Wort ist schon vorhanden."; return }
        state.preferences.vocabulary.append(VocabularyEntry(word: value, aliases: aliases.trimmingCharacters(in: .whitespacesAndNewlines)))
        word = ""; aliases = ""; note = ""
    }
}

struct ResultView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Card(title: state.phase) {
            if state.result.isEmpty { Text("Hier erscheint dein nächstes Diktat.").foregroundStyle(.secondary) }
            else {
                TextEditor(text: $state.result).font(.body).frame(minHeight: 180).disabled(state.busy)
                HStack {
                    Button("Text kopieren") { TextInsertion.copy(state.result); state.message = "Text kopiert." }
                    Spacer()
                    Button("Verwerfen", role: .destructive) { state.clearResult() }
                }.disabled(state.busy)
            }
            if state.canRetry {
                HStack {
                    Button("Aufnahme erneut verarbeiten") { state.retry() }
                    if state.result.isEmpty { Button("Aufnahme verwerfen", role: .destructive) { state.clearResult() } }
                }
            }
            if state.busy { ProgressView(); Button("Abbrechen") { state.cancel() } }
            if !state.rawTranscript.isEmpty { DisclosureGroup("Ursprüngliches Transkript") { Text(state.rawTranscript).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
        }
        Text("Es wird kein Diktatverlauf auf der Festplatte gespeichert. Bei einem Fehler bleibt die letzte Aufnahme bis zum erneuten Versuch, Verwerfen oder Beenden im Arbeitsspeicher.").font(.caption).foregroundStyle(.secondary)
    }
}

struct RecordingHUD: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: !state.notice.isEmpty ? "doc.on.clipboard" : (state.recording ? "waveform" : "sparkles")).font(.title2).foregroundStyle(state.recording ? .red : accent)
            VStack(alignment: .leading, spacing: 5) {
                if !state.notice.isEmpty {
                    Text(state.notice).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if state.noticeNeedsPermission { Button("Einfügen freigeben") { TextInsertion.requestPermission() } }
                } else {
                    Text(state.phase).font(.callout.weight(.semibold))
                    if state.recording {
                        ProgressView(value: Double(state.level)).frame(width: 170)
                        Text(String(format: "%d:%02d · ", state.elapsed / 60, state.elapsed % 60) + (state.testingMicrophone ? "Mikrofontest" : state.handsFree ? "Strg + Alt beendet" : "Zum Beenden loslassen")).font(.caption2).foregroundStyle(.secondary)
                    } else { ProgressView().controlSize(.small) }
                }
            }
            if state.recording { Button { state.stop() } label: { Image(systemName: "stop.fill") }.help("Aufnahme beenden") }
            Button { if state.notice.isEmpty { state.cancel() } else { state.dismissNotice() } } label: { Image(systemName: "xmark") }.help("Schließen / Abbrechen").disabled(state.starting)
        }.padding(18).frame(width: 430).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)).tint(accent)
    }
}

extension Notification.Name { static let showSprechflowResult = Notification.Name("showSprechflowResult") }

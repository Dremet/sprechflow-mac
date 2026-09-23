import Foundation

public struct RouterModel: Codable, Identifiable, Hashable, Sendable {
    public struct Architecture: Codable, Hashable, Sendable {
        public let input_modalities: [String]
        public let output_modalities: [String]
    }
    public struct Pricing: Codable, Hashable, Sendable {
        public let prompt: String?
        public let completion: String?
        public let audio: String?
    }
    public let id: String
    public let name: String
    public let description: String?
    public let architecture: Architecture
    public let pricing: Pricing?
    public var isTranscription: Bool { architecture.output_modalities.contains("transcription") }
    public var acceptsAudio: Bool { architecture.input_modalities.contains("audio") && (isTranscription || architecture.output_modalities.contains("text")) && !id.contains(":batch") }
    public var acceptsText: Bool { architecture.input_modalities.contains("text") && architecture.output_modalities.contains("text") && !id.contains(":batch") }
    public var guidance: String {
        if isTranscription { return "Spezialisiert auf Sprache → Text. Ein guter Ausgangspunkt für Diktate. Dein Wörterbuch wird in der anschließenden Überarbeitung berücksichtigt." }
        if acceptsAudio { return "Audiofähiges Sprachmodell: berücksichtigt dein Wörterbuch schon bei der Transkription. Mit Eigennamen und deutschem Diktat ausprobieren." }
        return "Für Zeichensetzung, Füllwörter und Formulierungen. Starte mit einem günstigen kleinen Modell; größere Modelle lohnen sich bei anspruchsvollen Texten." 
    }
    public var textPrice: String {
        guard !isTranscription, let p = Double(pricing?.prompt ?? ""), let c = Double(pricing?.completion ?? ""), p >= 0, c >= 0 else { return "Abrechnung und Audiopreise auf der Modellseite prüfen." }
        return String(format: "Text: $%.2f Eingabe / $%.2f Ausgabe je 1 Mio. Tokens. Audio wird ggf. separat berechnet.", p * 1_000_000, c * 1_000_000)
    }
}

public struct VocabularyEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var word: String
    public var aliases: String
    public init(id: UUID = UUID(), word: String, aliases: String = "") { self.id = id; self.word = word; self.aliases = aliases }
}

public enum WritingStyle: String, Codable, CaseIterable, Sendable {
    case clean = "Bereinigen", verbatim = "Wortgetreu", polished = "Flüssig formulieren"
    public var instruction: String {
        switch self {
        case .clean: return "Korrigiere Zeichensetzung und Rechtschreibung, entferne Füllwörter und versehentliche Wiederholungen. Behalte Tonfall und Bedeutung."
        case .verbatim: return "Behalte alle gesprochenen Wörter und den Tonfall. Ergänze nur Zeichensetzung und korrigiere eindeutig falsch erkannte Wörter aus dem Wörterbuch."
        case .polished: return "Formuliere flüssig und gut lesbar. Behalte Bedeutung, Sprache und persönlichen Ton; füge keine Informationen hinzu."
        }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var microphoneID = ""
    public var sttModel = "openai/whisper-1"
    public var textModel = "google/gemini-2.5-flash-lite"
    public var language = "de"
    public var style = WritingStyle.clean
    public var processText = true
    public var autoPaste = true
    public var vocabulary: [VocabularyEntry] = []
    public init() {}
    public var dictionaryHint: String {
        vocabulary.map { $0.aliases.isEmpty ? $0.word : "\($0.word) (häufig falsch erkannt als: \($0.aliases))" }.joined(separator: "\n")
    }
}

public enum FlowError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}

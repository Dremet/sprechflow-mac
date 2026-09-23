# Prüfstand – 23. September 2026

## Nachgewiesen

- Release-Build erfolgreich; `codesign --verify --deep --strict` und `plutil -lint` erfolgreich.
- App unter `/Users/dremet/Applications/Sprechflow.app` installiert und nach dem finalen Build neu gestartet.
- Einstellungsfenster visuell geprüft; App-Name, Navigation und Karten ohne abgeschnittene Texte.
- Live-Modellkatalog erfolgreich in der laufenden App geladen: 612 Einträge, davon 58 passende Audiomodelle und 382 passende Textmodelle zum Prüfzeitpunkt.
- Audiomodell über die UI gesucht und ausgewählt; Einstellung auf der Festplatte bestätigt.
- Wörterbucheintrag „Sprechflow“ mit „Sprech Flow, Sprechflo“ in der UI angelegt; Speicherung bestätigt.
- Mikrofonliste enthielt „Amazon USB Streaming Mic“ und „HD Pro Webcam C920“. Festes USB-Mikrofon ausgewählt und gespeichert. Lokaler Mikrofontest lieferte einen sichtbaren Pegel (~0,55); nach Stop waren keine temporären Sprechflow-WAV-Dateien vorhanden.
- Gerät wurde bei zeitweisiger Nichtverfügbarkeit als nicht verbunden angezeigt und nach Wiederverfügbarkeit erneut erkannt. Keine Änderung des Systemstandards durch die App.
- Nach Neustart bleiben Geräte-ID, Modellwahl und Wörterbuch erhalten.
- Fünf automatische Testgruppen erfolgreich: dedizierter STT-Pfad und WAV-Payload; Audio-Chat und Wörterbuch; gewähltes Textmodell/Stil; HTTP-/Providerfehler, leere und abgeschnittene Antworten; Modellfilter und Persistenz.
- Nachprüfung: Abbruch und Fokuswechsel unmittelbar vor dem Einfügen werden jetzt geprüft. Der Release-Build mit dieser Korrektur ist erfolgreich.

## Nachprüfung am 23. September

- Schlüssel wurde vom Nutzer in der App gespeichert; die Oberfläche bestätigt die erfolgreiche Verbindung. Der Schlüssel wurde nicht ausgelesen.
- Ein echter Diktatdurchlauf lieferte in der Oberfläche „Hallo kleiner Test“. Die Meldung zeigte, dass das Ergebnis nur kopiert wurde. Die macOS-Freigabe für Sprechflow war ausgeschaltet.
- Die neue Bedienung verwendet Strg + Alt: Halten zum Sprechen, Loslassen zum Beenden; zweimal kurz drücken startet Daueraufnahme, erneut drücken beendet sie. Sechs Zustandsautomaten-Tests decken Halten, Doppeldruck, Zeitüberschreitung, andere Tastenkombinationen, Abbruch und verzögerte Ereignisverarbeitung ab. Zusammen mit den fünf API-Testgruppen sind elf Tests erfolgreich.
- Release-Build erfolgreich. Einfügen wartet nun auf das Loslassen physisch gedrückter Modifikatortasten und meldet den konkreten Grund, falls nur kopiert werden konnte.
- Ein kostenfreier Einfügetest mit zehn Sekunden Vorlauf ist in den Einstellungen verfügbar. Das Ergebnis wird als Hinweis direkt nach der Verarbeitung angezeigt; der Berechtigungsstatus wird automatisch aktualisiert.
- Der Nutzer hat die Freigabe autorisiert und den macOS-Dialog bestätigt. Der alte Sprechflow-Eintrag musste entfernt und die aktuell installierte App erneut hinzugefügt werden. Anschließend meldete die App „Bedienungshilfen erlaubt“; die Warnung für den globalen Tastaturmonitor verschwand.
- Der Nutzer bestätigt: „habe gerade den einfügen-test gemacht, hat geklappt“. Damit ist das praktische Einfügen nach der Freigabe bestätigt; die Zielanwendung wurde dabei nicht ausdrücklich genannt.
- Ein zusätzlicher automatisierter Browser-Test in einem lokalen Textfeld lieferte keinen sichtbaren Text. Die App meldete gesendetes Einfügen; die tatsächliche Zielanwendung ließ sich dabei nicht bestätigen. Dieser Test gilt nicht als erfolgreich. Die UI-Automation für iTerm2 wird vom verwendeten Werkzeug verweigert.

## Noch praktisch zu prüfen

- Ein vollständiges Diktat mit automatischem Einfügen in iTerm2 und Browser nach der Freigabe bestätigen.
- Halten und Doppeldruck wurden automatisch getestet; der globale Modifier-Monitor muss nach erteilter Freigabe auch praktisch mit der Tastatur geprüft werden.

## Reproduzieren

```sh
bash scripts/test.sh
bash scripts/build-app.sh
```

Die vorhandene Swift-6.4-Vorabinstallation benötigt einen expliziten Pfad zum mitgelieferten Swift-Testing-Plugin. `scripts/test.sh` ermittelt diesen aus `xcrun`. Die Anwendung nutzt wegen einer Namenskollision im aktuellen SDK einen Alias für den klassischen SwiftUI-State-Property-Wrapper.

# Sprechflow

A native macOS menu bar app for dictation with OpenRouter. Requires macOS 14 or later.

## Getting started

After building, the app is available at `dist/Sprechflow.app`. If installed at `~/Applications/Sprechflow.app`, double-click it to launch. The waveform icon in the upper-right corner opens recording, settings, and the latest dictation.

1. Under **General**, save an OpenRouter API key and click **Check connection**. The key is stored in the macOS Keychain.
2. Select a microphone. Choosing a specific device is independent of the system-wide default. **Test microphone** displays the input level, keeps the test local, and deletes the test recording. If a device is unavailable, the app shows an error instead of silently switching devices.
3. Under **Models**, select separate models for speech recognition and refinement. The list is fetched live from OpenRouter, with search, selection guidance, and pricing links. Whisper and Gemini Flash Lite are suggested starting points, not a guarantee of quality.
4. Under **Dictionary**, add correct spellings and, optionally, common misrecognitions. Changes are saved automatically.
5. In the text field where you want to dictate, **hold Ctrl + Left Alt**, speak, and release to finish. **Quickly press Ctrl + Alt twice** to start hands-free recording; press Ctrl + Alt again to stop. On a Mac keyboard, these keys are called Control and Option. You can also start recording from the menu bar icon.
6. To use the global shortcut and automatic paste, allow Sprechflow under **System Settings → Privacy & Security → Accessibility**. The app opens this settings pane directly. Without this permission, you can record from the menu bar icon; the text is copied and can be pasted with Windows+V on a PC keyboard (Command+V on a Mac). Allow microphone access the first time you record.
7. **Test paste (10 sec.)** checks pasting independently of the microphone and API. During the countdown, click an empty text field in iTerm2 or a browser. The app inserts `Sprechflow-Test` without a line break.

## Behavior

- Dictation is limited to 3 minutes; microphone tests are limited to 15 seconds.
- Audio is recorded as mono WAV at 16 kHz and 16-bit. The selected input device is opened directly through AVFoundation; the macOS default device is not changed.
- STT models with a `transcription` output use `/audio/transcriptions`; audio language models use `input_audio` through `/chat/completions`.
- Dedicated STT models do not receive a universal dictionary prompt because OpenRouter does not consistently support it. The dictionary is applied in a second step for these models; the interface explains this when refinement is disabled.
- The raw transcript is preserved if refinement fails. Errors allow you to retry with a different model selection. Cancel stops in-flight client requests; API costs already incurred may remain.
- The latest result stays in memory; there is no saved dictation history. Temporary audio files are deleted when recording ends. If an error occurs, audio remains in memory for another attempt. **Discard** removes it.
- Copying and automatic pasting replace the current clipboard contents. The app sends Cmd+V to the original app; app-specific restrictions may require manual pasting. If you switch to another app while processing, the text is only copied. Cancelling during the brief paste preparation prevents Cmd+V from being sent.
- Settings and the cached model catalog are stored in `~/Library/Application Support/Sprechflow/`. No API key is stored in these files.

## Development

```sh
bash scripts/test.sh
bash scripts/build-app.sh
```

There are no external libraries. The app uses SwiftUI/AppKit, AVFoundation, local and global modifier events, and the Security Keychain. It is signed locally with an ad hoc signature; distribution to other Macs will require Developer ID signing and notarization. macOS permissions may need to be granted again after rebuilding.

The tests cover both API paths, audio payloads, dictionary and model handoff, error responses, truncated text, model filtering, and persistence of the selected microphone. A real paid STT request requires an API key entered by the user in the app.

## API references

- [OpenRouter Speech-to-Text](https://openrouter.ai/docs/guides/overview/multimodal/stt)
- [OpenRouter Audio Inputs](https://openrouter.ai/docs/guides/overview/multimodal/audio)
- [OpenRouter Model Catalog](https://openrouter.ai/docs/api/api-reference/models/get-models)

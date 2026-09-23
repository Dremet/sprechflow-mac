import AVFoundation
import SprechflowCore

struct Microphone: Identifiable {
    let id: String
    let name: String
}

final class Recorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "de.sprechflow.capture")
    private var session: AVCaptureSession?
    private var output: AVCaptureAudioFileOutput?
    private var completion: (@Sendable (Result<URL, Error>) -> Void)?
    private var meter: DispatchSourceTimer?

    static func microphones() -> [Microphone] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices.map { Microphone(id: $0.uniqueID, name: $0.localizedName) }
    }

    func start(deviceID: String, onLevel: @escaping @Sendable (Float) -> Void, onFinish: @escaping @Sendable (Result<URL, Error>) -> Void) async throws {
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard allowed else { throw FlowError.message("Mikrofonzugriff fehlt. Unter Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon Sprechflow erlauben.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard self.session == nil else { throw FlowError.message("Es läuft bereits eine Aufnahme.") }
                    let device = deviceID.isEmpty ? AVCaptureDevice.default(for: .audio) : AVCaptureDevice(uniqueID: deviceID)
                    guard let device, device.hasMediaType(.audio), device.isConnected else { throw FlowError.message("Das ausgewählte Mikrofon ist nicht angeschlossen. Bitte ein anderes Mikrofon auswählen.") }
                    let session = AVCaptureSession()
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioFileOutput()
                    guard session.canAddInput(input), session.canAddOutput(output) else { throw FlowError.message("Dieses Mikrofon kann gerade nicht verwendet werden.") }
                    session.addInput(input)
                    session.addOutput(output)
                    output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
                    output.maxRecordedDuration = CMTime(seconds: 180, preferredTimescale: 600)
                    self.session = session
                    self.output = output
                    self.completion = onFinish
                    session.startRunning()
                    guard session.isRunning else { self.cleanup(); throw FlowError.message("Mikrofon konnte nicht gestartet werden.") }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sprechflow-\(UUID().uuidString).wav")
                    output.startRecording(to: url, outputFileType: .wav, recordingDelegate: self)
                    let timer = DispatchSource.makeTimerSource(queue: self.queue)
                    timer.schedule(deadline: .now(), repeating: .milliseconds(100))
                    timer.setEventHandler { [weak self] in
                        let db = self?.output?.connection(with: .audio)?.audioChannels.map(\.averagePowerLevel).max() ?? -80
                        onLevel(max(0, min(1, (db + 55) / 55)))
                    }
                    self.meter = timer
                    timer.resume()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() { queue.async { self.output?.stopRecording() } }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            let completion = self.completion
            self.cleanup()
            if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
                try? FileManager.default.removeItem(at: outputFileURL)
                completion?(.failure(error))
            } else { completion?(.success(outputFileURL)) }
        }
    }

    private func cleanup() {
        meter?.cancel(); meter = nil
        session?.stopRunning()
        session = nil; output = nil; completion = nil
    }
}

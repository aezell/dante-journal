// dante-ear: the journal's ear. Captures the microphone (or reads an audio
// file), transcribes on-device with Apple's SpeechAnalyzer, and talks to the
// Elixir side over newline-delimited JSON on stdin/stdout.
//
// in:  {"cmd":"start","clip":"/path/to/clip.wav"}   begin a dictation
//      {"cmd":"stop"}                               end it
//      {"cmd":"file","path":"/path/to/audio"}       transcribe a file
//      {"cmd":"quit"}
// out: {"event":"ready","locale":"en_US"}
//      {"event":"started"}
//      {"event":"partial","text":"..."}             finalized + volatile so far
//      {"event":"stopped","text":"...","clip":"...","ms":12300}
//      {"event":"transcript","text":"...","path":"..."}
//      {"event":"error","message":"..."}
//      {"event":"log","message":"..."}

import AVFoundation
import Foundation
import Speech

// MARK: - Output

let out = FileHandle.standardOutput
let outLock = NSLock()

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let line = String(data: data, encoding: .utf8) else { return }
    outLock.lock()
    out.write((line + "\n").data(using: .utf8)!)
    outLock.unlock()
}

func emitError(_ message: String) { emit(["event": "error", "message": message]) }
func log(_ message: String) { emit(["event": "log", "message": message]) }

// MARK: - Transcription session

@available(macOS 26.0, *)
actor Ear {
    let locale: Locale
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var clipFile: AVAudioFile?
    private var clipPath: String?
    private var startedAt: Date?
    private var finalized: [String] = []
    private var volatile = ""

    init(locale: Locale) { self.locale = locale }

    var running: Bool { engine != nil }

    func ensureModel() async throws {
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            log("downloading speech model for \(locale.identifier)")
            try await request.downloadAndInstall()
        }
    }

    // Builds a fresh analyzer and the buffer pipeline; shared by mic and file.
    private func openAnalyzer() async throws -> (AVAudioFormat, AsyncStream<AnalyzerInput>.Continuation) {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw EarError("no compatible audio format for the speech model")
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.input = continuation
        self.finalized = []
        self.volatile = ""

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    await self?.handle(result)
                }
            } catch {
                emitError("results stream: \(error.localizedDescription)")
            }
        }
        try await analyzer.start(inputSequence: stream)
        return (format, continuation)
    }

    private func handle(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        if result.isFinal {
            finalized.append(text)
            volatile = ""
        } else {
            volatile = text
        }
        emit(["event": "partial", "text": currentText()])
    }

    private func currentText() -> String {
        (finalized + (volatile.isEmpty ? [] : [volatile]))
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func closeAnalyzer() async throws -> String {
        input?.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        let text = currentText()
        analyzer = nil
        transcriber = nil
        input = nil
        resultsTask = nil
        return text
    }

    // MARK: Microphone

    func start(clip: String) async throws {
        guard !running else { throw EarError("already recording") }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { throw EarError("microphone access denied") }

        let (format, continuation) = try await openAnalyzer()
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let inputFormat = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw EarError("cannot convert \(inputFormat) to \(format)")
        }
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: clip), settings: inputFormat.settings)
        clipFile = file
        clipPath = clip

        node.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            try? file.write(from: buffer)
            if let converted = Ear.convert(buffer, with: converter, to: format) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        startedAt = Date()
        emit(["event": "started"])
    }

    func stop() async throws {
        guard let engine else { throw EarError("not recording") }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        let text = try await closeAnalyzer()
        let seconds = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        clipFile = nil
        emit(["event": "stopped", "text": text, "clip": clipPath ?? "", "ms": Int(seconds * 1000)])
        clipPath = nil
        startedAt = nil
    }

    // MARK: Files

    func transcribe(path: String) async throws {
        guard !running else { throw EarError("busy recording") }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let (format, continuation) = try await openAnalyzer()
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
            throw EarError("cannot convert \(file.processingFormat) to \(format)")
        }
        let frames: AVAudioFrameCount = 8192
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { break }
            try file.read(into: buffer, frameCount: frames)
            if buffer.frameLength == 0 { break }
            if let converted = Ear.convert(buffer, with: converter, to: format) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        let text = try await closeAnalyzer()
        emit(["event": "transcript", "text": text, "path": path])
    }

    nonisolated static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error { emitError("convert: \(error.localizedDescription)"); return nil }
        return output.frameLength > 0 ? output : nil
    }
}

struct EarError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Command loop

guard #available(macOS 26.0, *) else {
    emitError("dante-ear needs macOS 26 or later for on-device SpeechAnalyzer")
    exit(2)
}

let localeId = CommandLine.arguments.dropFirst().first ?? "en_US"
let ear = Ear(locale: Locale(identifier: localeId))

do {
    try await ear.ensureModel()
} catch {
    emitError("speech model: \(error)")
    exit(3)
}
emit(["event": "ready", "locale": localeId])

for try await line in FileHandle.standardInput.bytes.lines {
    guard let data = line.data(using: .utf8),
          let command = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cmd = command["cmd"] as? String else {
        emitError("unparseable command: \(line)")
        continue
    }
    do {
        switch cmd {
        case "start":
            let clip = command["clip"] as? String ?? NSTemporaryDirectory() + "dante-ear-\(Int(Date().timeIntervalSince1970)).wav"
            try await ear.start(clip: clip)
        case "stop":
            try await ear.stop()
        case "file":
            guard let path = command["path"] as? String else { throw EarError("file needs a path") }
            try await ear.transcribe(path: path)
        case "quit":
            if await ear.running { try? await ear.stop() }
            exit(0)
        default:
            throw EarError("unknown command \(cmd)")
        }
    } catch {
        emitError("\(cmd): \(error)")
    }
}
// stdin closed: the Elixir side went away.
if await ear.running { try? await ear.stop() }
exit(0)

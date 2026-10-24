// dante-ear: the journal's ear. Captures the microphone (or reads an audio
// file), transcribes on-device with Apple's SpeechAnalyzer, and talks to the
// Elixir side over newline-delimited JSON on stdin/stdout.
//
// in:  {"cmd":"start","clip":"/path/to/clip.wav"}   begin a dictation
//      {"cmd":"stop"}                               end it
//      {"cmd":"file","path":"/path/to/audio"}       transcribe a file
//      {"cmd":"hotkey","key":61}                    watch a key system-wide (0 = stop watching);
//                                                   key = keycode | modifiers << 8 (⌘1 ⌥2 ⌃4 ⇧8 fn16)
//      {"cmd":"learn"}                              report the next key pressed, for choosing one
//      {"cmd":"play","path":"/path/clip.wav"}       play a clip (output only, no permission needed)
//      {"cmd":"stopplay"}
//      {"cmd":"quit"}
// out: {"event":"ready","locale":"en_US"}
//      {"event":"started"}
//      {"event":"partial","text":"..."}             finalized + volatile so far
//      {"event":"stopped","text":"...","clip":"...","ms":12300}
//      {"event":"transcript","text":"...","path":"..."}
//      {"event":"hotkey","status":"listening","key":61} | {"event":"hotkey","status":"denied"}
//      {"event":"hotkey","state":"down"} | {"event":"hotkey","state":"up"}
//      {"event":"hotkey","learned":105}
//      {"event":"play","state":"started"|"finished"|"failed","path":"..."}
//      {"event":"error","message":"..."}
//      {"event":"log","message":"..."}

import AVFoundation
import CoreGraphics
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

// MARK: - Hold-to-talk hotkey

/// Watches one key or chord system-wide with a listen-only CGEventTap on its
/// own run loop, so holding it works while the journal is in the background.
/// Needs Input Monitoring permission; the first call asks for it.
///
/// A hotkey is `keycode | modifiers << 8`. With no modifiers the key may be a
/// modifier itself (right ⌥, fn…), tracked through flagsChanged; otherwise it
/// is an ordinary key that must be pressed with exactly those modifiers.
final class HotkeyMonitor {
    static let shared = HotkeyMonitor()
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private(set) var hotkey: Int64 = 0
    private var down = false
    private var learning = false
    private var learnSawKey = false
    private var askedForAccess = false
    private var reportedDenied = false
    private var pending: Int64 = 0

    private var keyCode: Int64 { hotkey & 0xFF }
    private var modifiers: Int64 { hotkey >> 8 }

    // Modifier keys arrive as flagsChanged; everything else as keyDown/keyUp.
    private static let modifierMasks: [Int64: CGEventFlags] = [
        54: .maskCommand, 55: .maskCommand,
        56: .maskShift, 60: .maskShift,
        58: .maskAlternate, 61: .maskAlternate,
        59: .maskControl, 62: .maskControl,
        63: .maskSecondaryFn,
    ]

    // Modifier bits in a hotkey's high byte, in the order the app names them.
    private static let modifierBits: [(Int64, CGEventFlags)] = [
        (1, .maskCommand), (2, .maskAlternate), (4, .maskControl), (8, .maskShift), (16, .maskSecondaryFn),
    ]

    private static func bits(of flags: CGEventFlags) -> Int64 {
        modifierBits.reduce(0) { acc, pair in flags.contains(pair.1) ? acc | pair.0 : acc }
    }

    // The chord's modifiers must be held, and no others among ⌘⌥⌃⇧.
    private func modifiersMatch(_ flags: CGEventFlags) -> Bool {
        let held = HotkeyMonitor.bits(of: flags)
        let required = modifiers
        return (held & 15) == (required & 15) && (required & 16 == 0 || held & 16 != 0)
    }

    func stop() {
        pending = 0
        if let runLoop { CFRunLoopStop(runLoop) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        runLoop = nil
        thread = nil
        hotkey = 0
        down = false
    }

    /// Reports the next key or chord pressed, then goes back to watching the current one.
    func learn() {
        learning = true
        learnSawKey = false
        if tap == nil { start(hotkey: 0, forLearning: true) }
    }

    func start(hotkey value: Int64, forLearning: Bool = false) {
        let wasLearning = learning || forLearning
        stop()
        learning = wasLearning
        guard value > 0 || learning else { return }
        if !CGPreflightListenEventAccess() {
            // Asks once; macOS shows the Input Monitoring prompt for the responsible
            // app. The grant arrives later, so keep checking and start when it does.
            if !askedForAccess {
                askedForAccess = true
                _ = CGRequestListenEventAccess()
            }
            if !CGPreflightListenEventAccess() {
                if !reportedDenied {
                    reportedDenied = true
                    emit(["event": "hotkey", "status": "denied"])
                }
                pending = value
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, self.pending == value, self.tap == nil else { return }
                    self.start(hotkey: value, forLearning: forLearning)
                }
                return
            }
        }
        pending = 0
        reportedDenied = false
        hotkey = value
        let thread = Thread { [weak self] in
            guard let self else { return }
            let mask: CGEventMask =
                (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            let callback: CGEventTapCallBack = { _, type, event, userInfo in
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo!).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            }
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                emit(["event": "hotkey", "status": "denied"])
                return
            }
            self.tap = tap
            self.runLoop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            if value > 0 { emit(["event": "hotkey", "status": "listening", "key": value]) }
            CFRunLoopRun()
        }
        thread.name = "dante-ear.hotkey"
        thread.start()
        self.thread = thread
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if learning {
            learnStep(type: type, code: code, flags: event.flags, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            return
        }
        let pressed: Bool
        if modifiers == 0, let mask = HotkeyMonitor.modifierMasks[keyCode] {
            // A modifier on its own.
            guard type == .flagsChanged, code == keyCode else { return }
            pressed = event.flags.contains(mask)
        } else {
            switch type {
            case .keyDown:
                guard code == keyCode, !down else { return }
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
                guard modifiersMatch(event.flags) else { return }
                pressed = true
            case .keyUp:
                guard code == keyCode, down else { return }
                pressed = false
            case .flagsChanged:
                // Letting go of a modifier ends the chord too.
                guard down, !modifiersMatch(event.flags) else { return }
                pressed = false
            default:
                return
            }
        }
        guard pressed != down else { return }
        down = pressed
        emit(["event": "hotkey", "state": pressed ? "down" : "up"])
    }

    // Learning: an ordinary key pressed with whatever modifiers are held is the
    // chord; a modifier pressed and released on its own is a single-key choice.
    private func learnStep(type: CGEventType, code: Int64, flags: CGEventFlags, isRepeat: Bool) {
        switch type {
        case .keyDown:
            guard !isRepeat else { return }
            learnSawKey = true
            finishLearning(code | (HotkeyMonitor.bits(of: flags) << 8))
        case .flagsChanged:
            guard let mask = HotkeyMonitor.modifierMasks[code] else { return }
            if flags.contains(mask) {
                learnSawKey = false
            } else if !learnSawKey {
                finishLearning(code)
            }
        default:
            return
        }
    }

    private func finishLearning(_ value: Int64) {
        learning = false
        emit(["event": "hotkey", "learned": value])
    }
}

// MARK: - Clip playback

/// Plays one clip at a time with AVAudioPlayer. Output needs no permission,
/// unlike `afplay`, whose AudioToolbox setup can raise the microphone prompt
/// for the app that spawned it.
final class ClipPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = ClipPlayer()
    private var player: AVAudioPlayer?
    private var path = ""

    func play(path: String) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player.delegate = self
            self.player = player
            self.path = path
            let ok = player.play()
            log("play \(URL(fileURLWithPath: path).lastPathComponent): \(ok ? "started" : "refused"), \(player.duration) s")
            if ok {
                emit(["event": "play", "state": "started", "path": path])
            } else {
                emit(["event": "play", "state": "failed", "path": path, "message": "could not start playback"])
                self.player = nil
            }
        } catch {
            emit(["event": "play", "state": "failed", "path": path, "message": "\(error.localizedDescription)"])
        }
    }

    func stop() {
        guard let player else { return }
        player.stop()
        self.player = nil
        emit(["event": "play", "state": "finished", "path": path])
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        emit(["event": "play", "state": "finished", "path": path])
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        self.player = nil
        emit(["event": "play", "state": "failed", "path": path, "message": error?.localizedDescription ?? "decode error"])
    }
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
        case "hotkey":
            let key = (command["key"] as? NSNumber)?.int64Value ?? 0
            HotkeyMonitor.shared.start(hotkey: key)
        case "learn":
            HotkeyMonitor.shared.learn()
        case "play":
            guard let path = command["path"] as? String else { throw EarError("play needs a path") }
            ClipPlayer.shared.play(path: path)
        case "stopplay":
            ClipPlayer.shared.stop()
        case "quit":
            ClipPlayer.shared.stop()
            HotkeyMonitor.shared.stop()
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

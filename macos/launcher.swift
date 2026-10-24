// The app's main executable. It stays alive as the process macOS launched
// and runs the Erlang release as a child, so the microphone and Input
// Monitoring requests made by the helper underneath are attributed to
// "Dante Journal" (this bundle) rather than to Erlang's own binaries. A
// shell script that exec'd into Erlang left macOS attributing them to erlexec.
import Foundation

let bundle = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent()   // MacOS
    .deletingLastPathComponent()   // Contents
let release = bundle.appendingPathComponent("Resources/release/bin/dante_journal")
let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Dante Journal")
try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

var environment = ProcessInfo.processInfo.environment
environment["RELEASE_TMP"] = (environment["TMPDIR"] ?? "/tmp") + "/dante-journal"
environment["ERL_CRASH_DUMP"] = logs.appendingPathComponent("erl_crash.dump").path

// macOS passes a process serial number to apps opened from Finder on some releases.
let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }

let child = Process()
child.executableURL = release
child.arguments = ["eval", "DanteJournal.CLI.main(System.argv())"] + arguments
child.environment = environment

if isatty(STDOUT_FILENO) == 0 {
    let log = logs.appendingPathComponent("dante-journal.log")
    if !FileManager.default.fileExists(atPath: log.path) {
        FileManager.default.createFile(atPath: log.path, contents: nil)
    }
    if let handle = try? FileHandle(forWritingTo: log) {
        handle.seekToEndOfFile()
        child.standardOutput = handle
        child.standardError = handle
    }
}

// Quit from the Dock or logout sends SIGTERM here; pass it on.
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler { child.terminate() }
term.resume()
let int = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
int.setEventHandler { child.terminate() }
int.resume()

child.terminationHandler = { process in
    exit(process.terminationStatus)
}

do {
    try child.run()
} catch {
    FileHandle.standardError.write("Could not start the release: \(error)\n".data(using: .utf8)!)
    exit(1)
}
dispatchMain()

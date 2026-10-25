# Dante Journal

A native macOS reading journal for the *Divine Comedy*, in Elixir on the GPUI
bindings. Read the printed book, tap a key, dictate a note; it is transcribed
on-device and pinned to the canto and tercet it talks about. The plan is in
[docs/PLAN.md](docs/PLAN.md).

## Run

Requires Elixir 1.20 on OTP 29 (see `.tool-versions`) and Apple silicon
macOS 26 or later. No Rust: the GPUI native library is downloaded precompiled.

```sh
mix deps.get
./native/dante-ear/build.sh   # the Swift transcription helper → priv/bin/dante-ear
mix dante                     # or: mix dante --light
```

## Build the Mac app

```sh
MIX_ENV=prod mix dante.app    # dist/Dante Journal.app and a zip to share
```

The bundle carries its own Erlang runtime, the GPUI library, the helper and
the OpenSSL library Erlang's crypto needs. Run `macos/make_signing_cert.sh`
once to create a self-signed "Dante Journal Developer" certificate; builds
are then signed with it, so macOS keeps the app's microphone and Input
Monitoring grants across rebuilds. Without it the app is signed ad hoc and
asks again after every build. Its minimum macOS
is whatever the bundled Erlang was built for (27.0 with the asdf build here). On first launch
macOS asks for the microphone; hold-to-talk also needs Input Monitoring
(System Settings → Privacy & Security → Input Monitoring), then a relaunch.
Any key or chord can be the hold-to-talk key. A chord with ⌘ or ⌃, a lone
modifier or a function key is best, since an ordinary key still types into
whatever app is in front. Releasing any part of a chord ends the dictation.
Opened from Finder the app logs to `~/Library/Logs/Dante Journal/`. The icon
is drawn by `macos/make_icon.sh`.

## The on-device model

With Apple's Foundation Models command available (macOS 27; accept its terms
once with `sudo fm license`), the app uses the local model, never the
network, for three things:

- **Reading a note.** Each dictation gets a type, a short title and tags from
  the model while the card is open; the rule-based guess shows first and a
  type you pick by hand is never overridden.
- **Placing a note.** When the spoken place isn't in a form the parser reads
  ("the second canto of Purgatory, around the fourth stanza"), the model
  reads it and the card shows "read by the model". ⌘K → "Re-read spoken
  anchors…" also asks the model about notes left on a whole canto.
- **Ask about these notes.** The box under the filters sends a question with
  the most relevant of the notes shown, and their lines, to the model; the
  answer cites notes as [n], and each citation is a button that jumps to the
  note.

Without the model everything else works as before; the status bar says
"no model".

## The Mandelbaum translation

Longfellow ships with the app. Allen Mandelbaum's translation is in
copyright, so it is never part of this repository; instead

```sh
mix dante.import
```

fetches it canto by canto from the University of Virginia's World of Dante
for your personal use, validates every canto against the Petrocchi line
counts, and writes it to `~/Library/Application Support/Dante Journal/texts/`.
Restart the app afterwards: it then reads Mandelbaum by default, and ⌘K
offers "Read the Longfellow translation" to switch.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘⇧D | Start a dictation; press again to stop (it also stops after a 6 s pause; change or disable that from ⌘K) |
| hold a key | Hold-to-talk from any app: press to start, release to stop; a quick tap toggles instead. Right Option by default; pick any key or chord (⌘], F13, right ⌃…) with ⌘K → "Set the hold-to-talk key…" and press it, or turn it off |
| ⌘N | Type a note, anchored to the selected tercet or the open canto |
| ⌘S | Save the note in the card |
| ⌘K | Go to a canto ("inf 5", "purg 9.70") or run a command |
| ⌘F | Search notes |
| ⌘I | Toggle the Italian (Petrocchi) column |
| ⌘⇧N / ⌘⇧P | Next / previous canto |
| ⌘⇧L | Toggle dark / light |
| ⌘Q | Quit |

Say where you are, then your note: "Canto 2, stanza 12, Dante sees the
leopard…" or "In canto 1, line 7, …". The anchor is parsed from what you
said, tolerating the speech model's habits ("Encanto one"); without one,
the note attaches to the tercet you clicked, or to the open canto. If a
note ended up on a whole canto, ⌘K → "Re-read spoken anchors of
whole-canto notes" tries again with the current parser. A confirm card
lets you fix the anchor and the note type before saving.

Lines with notes carry a coloured bar in the margin. Click a note to scroll
the poem to its lines and highlight them; click a marked tercet to scroll
the notes pane to its note. The notes pane shows this canto, this cantica
or everything, filtered by type and search, grouped by canto, type or day. Each note can be edited,
re-anchored (by typing a place such as "Purg. 9.70" or "canto 9 stanza
24"), played back, or deleted. **Save MD** and **Save TXT** write the shown
notes, with the lines they point at quoted, to `~/Documents/Dante Journal`;
**Copy MD** puts the same Markdown on the clipboard.

Clips are normalised to −1 dBFS and trimmed of leading and trailing
silence when a dictation ends, so the pause that stops a recording doesn't
end up in the file.

Notes live as one JSON file each, with their audio clips, under
`~/Library/Application Support/Dante Journal/notes`. Preferences (theme,
Italian column, notes layout) are remembered in the user config folder.

## The transcription helper

`native/dante-ear/main.swift` is a small Swift program built with `swiftc`
from the Command Line Tools. It captures the microphone with AVAudioEngine,
transcribes with Apple's on-device SpeechAnalyzer, saves the clip as WAV, and
talks newline-delimited JSON on stdin/stdout:

```
→ {"cmd":"start","clip":"/path/clip.wav"}
← {"event":"started"}
← {"event":"partial","text":"In Canto 2, stanza"}
→ {"cmd":"stop"}
← {"event":"stopped","text":"In Canto 2, stanza 12, …","clip":"/path/clip.wav","ms":6200}
→ {"cmd":"file","path":"/path/audio.aiff"}   # transcribe a file instead
← {"event":"transcript","text":"…","path":"…"}
```

Try it without the app:

```sh
say -o /tmp/sample.aiff "In canto two, stanza twelve, Dante sees the leopard."
printf '{"cmd":"file","path":"/tmp/sample.aiff"}\n{"cmd":"quit"}\n' | priv/bin/dante-ear
```

## Test

```sh
mix test
```

Tests run on GPUI's renderer-independent test display; no window opens.

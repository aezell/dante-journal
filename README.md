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
the OpenSSL library Erlang's crypto needs, signed ad hoc. Its minimum macOS
is whatever the bundled Erlang was built for (27.0 with the asdf build here). On first launch
macOS asks for the microphone; hold-to-talk also needs Input Monitoring
(System Settings → Privacy & Security → Input Monitoring), then a relaunch.
Any key or chord can be the hold-to-talk key. A chord with ⌘ or ⌃, a lone
modifier or a function key is best, since an ordinary key still types into
whatever app is in front. Releasing any part of a chord ends the dictation.
Opened from Finder the app logs to `~/Library/Logs/Dante Journal/`. The icon
is drawn by `macos/make_icon.sh`.

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
leopard…". The anchor is parsed from what you said; without one, the note
attaches to the tercet you clicked, or to the open canto. A confirm card
lets you fix the anchor and the note type before saving.

The notes pane shows this canto, this cantica or everything, filtered by
type and search, grouped by canto, type or day. Each note can be edited,
re-anchored (by typing a place such as "Purg. 9.70" or "canto 9 stanza
24"), played back, or deleted. **Save MD** and **Save TXT** write the shown
notes, with the lines they point at quoted, to `~/Documents/Dante Journal`;
**Copy MD** puts the same Markdown on the clipboard.

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

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

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘I | Toggle the Italian (Petrocchi) column |
| ⌘⇧N / ⌘⇧P | Next / previous canto |
| ⌘⇧L | Toggle dark / light |

Click a tercet to select it; dictated notes without a spoken anchor will
attach to the selected tercet.

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

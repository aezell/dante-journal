# Dante Journal — plan

A native macOS reading journal for the *Divine Comedy*, written in Elixir on
the GPUI bindings. You read the printed book, tap a key, dictate a note, and
the note is transcribed on-device and pinned to the canto and tercet it talks
about. The poem itself is in the app so notes can be seen in context, searched,
filtered, grouped and exported.

Patterns are borrowed from `~/workspace/superfly/sprites-desktop`: one
`GPUI.Application` with a single root `GPUI.View`, a plain state map, a `Theme`
module that resolves `{:theme, token}` styles, a `UIKit` of shared treatments,
long-running work in supervised GenServers that push messages into the view
with `GPUI.Runtime.send_view/3`, renderer-independent tests on `GPUI.Test`,
and a `mix dante.app` task that wraps a release in a `.app` bundle.

## What was verified on this Mac (2026-10-24)

| Thing | Finding |
| --- | --- |
| macOS | 27.0.1 on Apple silicon, Command Line Tools only (no full Xcode), Swift 6.4 |
| Elixir | 1.20.4-otp-29 installed via asdf (shell default is 1.19.2; project needs a `.tool-versions`) |
| Rust | Not installed. The sprites-desktop GPUI fork is a source checkout and would need Rust 1.95 plus full Xcode with the Metal toolchain |
| GPUI on Hex | `gpui`, `gpui_components`, `gpui_native` 0.2.0 published; the precompiled `aarch64-apple-darwin--gpui-component` NIF asset downloads. No Rust needed |
| Transcription | `SpeechTranscriber.isAvailable == true`; en_US model already installed. A probe compiled with plain `swiftc` against the CLT SDK |
| Apple on-device LLM | `/usr/bin/fm` present. It refuses everything until `sudo fm license` is run once (your action, not mine) |
| Mandelbaum text | Digital Dante (Columbia) blocks non-browser fetches with Anubis. The Società Dantesca Italiana site (danteonline.it) and UVA's World of Dante both serve the Mandelbaum text openly, tercet-numbered, with Petrocchi Italian available |
| Public-domain text | Petrocchi Italian (from Wikisource) and Longfellow English (Gutenberg #1004) exist as clean line-level JSON: `cantica`, `canto`, `line_number`, `text`. 14,233 lines each |

## Decisions

1. **GPUI from Hex, not the fork.** sprites-desktop pins a `chrismccord/gpui`
   commit for its terminal surface. We don't need a terminal, so we use the
   published 0.2.0 packages with the `:gpui_component` host and get the
   precompiled NIF. This removes the Rust and Xcode prerequisite entirely.
   Risk: 0.2.0 may lack a fix the fork carries; the Phase 0 spike exists to
   find out.

2. **Transcription is a small Swift helper, driven over a Port.** GPUI has no
   microphone or audio API, so a `priv/bin/dante-ear` binary built with
   `swiftc` owns `AVAudioEngine` capture and `SpeechAnalyzer` /
   `SpeechTranscriber`. It speaks newline-delimited JSON on stdin/stdout:
   `{"cmd":"start"}` / `{"cmd":"stop"}` in, `{"event":"partial","text":…}`,
   `{"event":"final","text":…,"audio":"…/clip.wav"}` out. Elixir never touches
   audio frames. This mirrors how sprites-desktop treats rclone as a helper
   process. Fully on-device, no network, no API keys. A whisper.cpp fallback
   can slot behind the same JSON protocol later if Apple's model disappoints.

3. **Push-to-talk, two steps.** GPUI exposes window shortcuts (key *down*
   only, as `:command` events) and nothing for key up, so true hold-to-talk
   can't be done in the GPUI layer.
   - V1: a toggle shortcut (⌘⇧D, or a bare key you choose) starts recording;
     the same key, Return, or two seconds of silence stops it. A visible
     recording banner with the live partial transcript.
   - V2: the Swift helper installs a `CGEventTap` for one global key
     (needs Input Monitoring permission, granted once). Then holding the key
     records and releasing stops, and it works while the app is in the
     background, which fits reading from a printed book.

4. **Anchors are parsed, then confirmed.** A deterministic Elixir parser
   reads the leading phrase of a transcript: cantica names (Inferno /
   Purgatorio / Paradiso, Hell / Purgatory / Paradise), `canto N`
   (digits, Roman numerals and spoken ordinals), and a unit: `stanza` or
   `tercet N` (lines 3N−2…3N), `line N`, `lines N to M`. Anything missing
   falls back to the reader's current position (selected cantica, canto,
   tercet). After each recording a small card shows the transcript, the
   resolved anchor and the type, each editable, so a misheard number is a
   one-click fix. The spoken anchor phrase is kept in the note body but
   can be hidden in views.

5. **Note types start as heuristics, graduate to the local LLM.** Types:
   `question`, `insight`, `reference`, `summary`, `quote`, `todo`, `note`
   (default). V1 rules: a question mark or openers like "I wonder", "why
   does", "is this" → question; "this echoes / reminds me / reference to /
   compare" → reference; "I think / it seems / the point is" → insight;
   "look up / check / find" → todo. V2: `fm respond --schema` classifies
   with a JSON schema and can also propose a one-line title and tags.
   Classification is advisory; the type is always editable.

6. **Notes are files, not a database, for now.** One JSON document per
   note in `~/Library/Application Support/Dante Journal/notes/`, plus the
   audio clip beside it. An ETS index is rebuilt at launch; a few thousand
   notes search instantly in memory. Files are human-readable, trivially
   exportable, back up with the folder, and need no NIF compile. If volume
   or query needs grow, SQLite with FTS5 via `exqlite` is the upgrade path
   and the `Notes` module boundary is designed so that swap is local.

7. **Texts: ship public domain, import Mandelbaum locally.** The repo
   bundles Petrocchi Italian and Longfellow English (the translation the
   Wordsworth Classics edition uses). Mandelbaum's translation (1980–84) is
   still in copyright, so it is never committed. A `mix dante.import`
   task fetches it canto by canto from danteonline.it (a POST form with
   `livello1`/`livello2` selects) or UVA's World of Dante, normalises it to
   the same line JSON, and writes it into your data folder for personal
   use. The reader shows whichever English translation is installed, with
   Mandelbaum preferred when present. Side-by-side Italian is a toggle.

8. **Ask-my-notes uses `fm` as a subprocess.** The on-device model has an
   8k context (about 6,000 words of your own text), so the feature is
   retrieval first: filter notes by the cantos or terms the question names,
   pack the most relevant notes plus the referenced tercets, then
   `fm respond`. `fm serve` gives an OpenAI-compatible local endpoint if we
   later want streaming or to swap in a bigger model. This is Phase 5 and
   gated on you running `sudo fm license`.

## Architecture

```
lib/
  dante_journal.ex                  start/1: builds state, starts runtime + workers
  dante_journal/
    desktop.ex                      GPUI.Application: window, shortcuts, root view
    view.ex                         Root GPUI.View: layout, handle_event, handle_info
    view/reader.ex                  Poem pane: virtual_collection of tercets, markers
    view/notes_pane.ex              Notes list, filters, search, grouping
    view/recorder.ex                Recording banner, confirm card
    view/palette.ex                 ⌘K command palette (go to canto, filters)
    state.ex                        Initial state map and pure transitions
    theme.ex                        Palettes; resolve({:theme, token})
    ui_kit.ex                       Shared treatments (headers, pills, fields)
    text.ex                         Corpus: load JSON, index by {cantica, canto, line}
    text/tercet.ex                  Line ↔ tercet math, Roman numerals, labels
    anchor.ex                       Transcript → %Anchor{} parser (+ fallback)
    notes.ex                        Note store: files on disk, ETS index, search
    notes/note.ex                   %Note{} struct and JSON codec
    classifier.ex                   Heuristic type rules; later fm-backed
    recorder.ex                     GenServer owning the Port to dante-ear
    recorder/protocol.ex            JSON line encode/decode for the helper
    export.ex                       Notes for a canto → Markdown / plain text
    ask.ex                          Retrieval + fm respond (Phase 5)
    preferences.ex                  Translation choice, hotkey, theme
    cli.ex                          Entry for `mix dante` and the .app
  mix/tasks/dante.ex                Run the app
  mix/tasks/dante.app.ex            Build Dante Journal.app (+ Info.plist usage strings)
  mix/tasks/dante.import.ex         Import Mandelbaum into the data folder
native/dante-ear/                   Swift package: capture + SpeechTranscriber + hotkey
priv/texts/                         petrocchi.json, longfellow.json (public domain)
test/                               GPUI.Test view tests, parser and store tests
```

Data shapes:

```elixir
%Anchor{cantica: :inferno, canto: 2, from_line: 34, to_line: 36}   # tercet 12
%Note{
  id: "01J…",            # ULID; file name
  anchor: %Anchor{},
  type: :question,
  text: "…transcript…",
  title: nil,            # optional, fm-proposed later
  tags: [],
  audio: "01J….wav",     # relative to notes dir
  recorded_at: ~U[],
  edited_at: ~U[],
  source: :dictation | :typed
}
```

UI layout (one window, 1200×780 min 900×600):

- **Sidebar**: three cantiche, expandable to cantos, each with a note count
  badge. Click jumps the reader. ⌘K palette for "Inferno 5", "questions in
  Purgatorio", etc.
- **Reader** (centre): a `UI.virtual_collection` of tercets for the current
  canto (34/33/33 cantos, each about 45 tercets, so one canto per
  collection keeps snapshots small). Each tercet is a `rich_text` with the
  tercet number in a gutter; a coloured dot per note type sits in the
  gutter and clicking it selects that note. Italian toggle shows the
  Petrocchi tercet beside or beneath the English. The selected tercet is
  the anchor fallback for dictation.
- **Notes pane** (right, toggleable): notes for the current canto by
  default; scope switch to cantica or everything. Filter chips by type,
  search box, group by canto / type / day. A note shows type, anchor label
  ("Inf. 2.34–36"), text, play-clip button, edit, delete.
- **Recording banner** (bottom): appears on start, shows a level/elapsed
  indicator and the live partial transcript; on stop becomes the confirm
  card with anchor, type and text editable, Save / Discard.

## Phases

### Phase 0 — spikes (done 2026-10-24)
Both spikes passed on this Mac:
- `gpui_native` 0.2.0 from Hex compiled and loaded its precompiled NIF with
  no Rust installed; `mix dante` opens the window on `GPUI.Display.Native`.
- `priv/bin/dante-ear` (built by `native/dante-ear/build.sh` with plain
  `swiftc`) transcribed a `say`-synthesized sentence exactly, including
  spoken numbers as digits ("In Canto 2, stanza 12, Dante sees the
  leopard…"), both from the shell and over an Erlang Port. Live microphone
  capture started, was granted access, and wrote the WAV clip.
- Note for Phase 2: `AVAudioNode.installTap` is deprecated in macOS 27;
  it still works, and the replacement can be adopted in the helper later.
Prove the two risky pieces before writing product code.
- `mix new dante_journal`, `.tool-versions` (erlang 29.1.1, elixir
  1.20.4-otp-29), `gpui_native 0.2.0` with the component host; a hello
  window opens on this Mac without Rust.
- `native/dante-ear`: a Swift CLI that records from the default mic while
  running, streams partial and final transcripts as JSON lines, and writes
  the clip to a WAV path it is given. Confirm the microphone permission
  prompt appears when launched from an Erlang Port.
Done when: window opens; `echo '{"cmd":"start"}' | dante-ear` prints what I
say.

### Phase 1 — the poem (done 2026-10-24)
Bundled Petrocchi and Longfellow as `priv/texts/*.json` via
`scripts/fetch_texts.exs` (14,233 lines each, validated per cantica);
`Text` and `Tercet` modules with tests; sidebar of 100 cantos in a `<scroll>`,
reader as a `virtual_collection` keyed per canto, Italian side-by-side toggle
(⌘I), next/previous canto (⌘⇧N / ⌘⇧P), tercet selection shown in the status
bar as the anchor fallback. Verified against the live native display: 46
tercet items for Inferno 1, 49 for Paradiso 33, Italian lines present after
the toggle. Still to come from the original list: the ⌘K go-to palette and
a preferences file (folded into Phase 3).
- Fetch and normalise Petrocchi and Longfellow into `priv/texts/*.json`
  with a documented script; record provenance in `priv/texts/README.md`.
- `Text` and `Tercet` modules with tests (line ↔ tercet, Roman numerals,
  canto sizes, the 14,233-line total).
- Desktop, View, State, Theme, UIKit skeleton following sprites-desktop.
- Sidebar navigation, reader with virtualised tercets, Italian toggle,
  ⌘K go-to-canto, ⌘⇧L theme, preferences file.
Done when: you can scroll any canto in either language from the sidebar.

### Phase 2 — dictate and anchor (done 2026-10-24)
`Recorder` supervises the helper over a Port, relays partials, stops after
3 s of silence once something was heard (15 s if nothing was), restarts a
dead helper, and can transcribe an audio file. `Anchor.parse/2` handles
cantica words, canto digits/Roman/number words, stanza/tercet, line and
line ranges, drops impossible numbers and falls back to the selected
tercet, then the canto. `Classifier` rules; `Notes` store as one JSON file
per note plus WAV clips under `~/Library/Application Support/Dante
Journal/notes`. UI: ⌘⇧D record/stop, banner with live transcript, confirm
card (anchor choices, type chips, ⌘S save, discard), gutter markers
coloured by type, sidebar counts, a notes pane for the open canto with
two-step delete. Verified end to end on the native display with a
synthesized Purgatorio note (anchor Purg. 9.70–72, type question, marker
and jump) and a live mic session. 26 tests.
Carried to Phase 3: editing a note, playback, typed notes, ⌘K palette.
- `Recorder` GenServer: supervises the helper Port, restarts it, forwards
  partial/final events to the view, stores the clip.
- `Anchor` parser with a test table of spoken phrases ("canto two stanza
  twelve", "Purgatorio 9, lines 70 to 72", "in canto XXXIII", no anchor).
- `Classifier` heuristics with tests.
- `Notes` store: write/read/delete JSON files, ETS index, list by anchor.
- Recording banner, confirm card, gutter markers, note counts in sidebar.
- Toggle shortcut and silence auto-stop.
Done when: tap, speak "Canto 2, stanza 12, …", confirm, and the dot shows
on Inferno 2 tercet 12 with the text in the notes pane.

### Phase 3 — browse, edit, export (done 2026-10-24)
Notes pane with scope (canto / cantica / everything), type filter chips,
⌘F search over text, anchor label and type, grouping by canto, type or
day; one note card (`Form`) for dictations, typed notes (⌘N) and edits,
with a native `text_surface` when the backend is present and a single-line
input otherwise (tests); re-anchoring by buttons or by typing "Purg. 9.70"
or "canto 9 stanza 24" into the card, through the same parser; clip
playback with `afplay` via a `Player` worker; Markdown and plain-text
export of the shown notes with the anchored lines quoted, saved under
~/Documents/Dante Journal and revealed in Finder, plus Copy MD to the
clipboard; ⌘K palette for "inf 5" / "purg 9.70" and commands; a
preferences file for theme, Italian, scope and grouping. 31 tests; live
checks of the surface, edit flow, playback and palette passed.
Deferred: PDF export, tags.
- Notes pane: scope, type filters, search, grouping, sort.
- Edit text and type in place (`text_surface`), re-anchor, delete with
  confirm, play clip (`afplay` via the helper or `System.cmd`).
- Typed notes without dictation, anchored to the selected tercet.
- Export the current canto's or a filter's notes as Markdown and plain
  text to a chosen folder. PDF comes later through the helper (print an
  HTML rendering to PDF with WebKit) or `cupsfilter`; not a V1 blocker.
Done when: "all questions in Purgatorio" is one click and exports cleanly.

### Phase 4 — Mandelbaum, hold-to-talk, the .app (done 2026-10-24)
`mix dante.import` fetches Mandelbaum from UVA's World of Dante (URL scheme
`inferno.xml/1.N`, `purgatory.xml/2.N`, `paradise.xml/3.N`; one canto per
page with Italian beside English), validates each canto's line count
against Petrocchi, compares the page's Italian to ours as a drift check,
and writes `~/Library/Application Support/Dante Journal/texts/mandelbaum.json`;
the reader prefers it and ⌘K switches translations. `dante-ear` gained a
listen-only `CGEventTap` on its own run loop for one key (right ⌥ by
default; any key or chord such as ⌘] via ⌘K → "Set the hold-to-talk key…",
which puts the tap in a learn mode that reports the next key pressed with
the modifiers held, encoded as `keycode ||| modifiers <<< 8`; or off): press starts,
held release stops, a quick tap toggles; it needs Input Monitoring, which the helper
requests and the app explains when denied. `mix dante.app` builds a
release into `Dante Journal.app` with the helper, the precompiled GPUI
library, Homebrew's libcrypto rebound with `install_name_tool`, an icon
drawn by `macos/make_icon.swift`, microphone and speech usage strings, ad
hoc signing and a zip. 37 tests. Two things learned: `gpui_native` 0.2.0
must be declared with `env: :release`, or inside any git checkout it tries
to build its Rust crate; and the asdf-built Erlang runtime sets the
bundle's minimum macOS to 27.0 (an OTP built with an older deployment
target would lower it).
- `mix dante.import`: fetch, parse, normalise, validate line counts
  against Petrocchi, write to the data folder; reader prefers it.
- Helper gains a global hotkey via `CGEventTap`; preferences let you pick
  the key; V1 toggle remains for when permission isn't granted.
- `mix dante.app`: release in a bundle, icon, `Info.plist` with
  `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`,
  ad hoc signing, portable-library check, logs to `~/Library/Logs`.
Done when: the .app in /Applications works end to end with Mandelbaum.

### Phase 5 — the local LLM (exploratory)
- After `sudo fm license`: `Classifier` asks `fm respond --schema` for type,
  title and tags; falls back to heuristics when `fm` is unavailable.
- `Ask`: a question box in the notes pane; retrieval over notes and
  tercets, answer streamed into a panel with the notes it drew on linked
  back to their anchors.

## Open questions for you

- **Hotkey**: which key for V1 toggle? Default proposal ⌘⇧D; for V2 hold,
  Right Option is a good single key that nothing else uses.
- **Mandelbaum import source**: danteonline.it (SDI) or UVA. Both work;
  I'd start with UVA since it's line-interleaved with Italian, which makes
  validation easy.
- **Storage**: files-plus-ETS as above, or SQLite from day one?
- **Keep the audio clips** by default, or only the transcript?

## Sources

- GPUI README and guides in `~/workspace/superfly/sprites-desktop/deps/gpui/apps/gpui/guides`
- Petrocchi/Longfellow JSON: https://github.com/gio-derosa/divine-comedy
- Mandelbaum online: https://www.danteonline.it/opere/index.php?opera=The+Divine+Comedy+-+tr.+Mandelbaum and https://worldofdante.iath.virginia.edu/comedy/dante/inferno.xml/1.1
- Princeton Dante Project e-text list: https://dante.princeton.edu/pdp/da_e_2.htm
- SpeechAnalyzer: https://developer.apple.com/videos/play/wwdc2025/277/ and https://github.com/arraypress/swift-speech-transcriber
- `fm` CLI guide: https://github.com/llostinthesauce/fm-guide

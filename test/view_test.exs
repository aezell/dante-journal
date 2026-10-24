defmodule DanteJournal.ViewTest do
  use GPUI.Test, async: true
  alias DanteJournal.{Anchor, Notes, State, View}
  alias DanteJournal.Notes.Note

  setup do
    dir = Path.join(System.tmp_dir!(), "dante-view-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, notes} = Notes.start_link(dir: dir, name: nil)
    {:ok, notes: notes, dir: dir}
  end

  defp payload(runtime),
    do: View.render(assigns(runtime)) |> GPUI.Element.to_payload() |> inspect(limit: :infinity)

  defp seed(notes, id, cantica, canto, from, type, text, day \\ ~U[2026-10-24 16:00:00Z]) do
    :ok =
      Notes.save(notes, %Note{
        id: id,
        anchor: %Anchor{
          cantica: cantica,
          canto: canto,
          from_line: from,
          to_line: from && from + 2
        },
        type: type,
        text: text,
        recorded_at: day
      })
  end

  test "the sidebar selects cantos and the shortcuts step through them", %{notes: notes} do
    runtime = start_runtime!(DanteJournal.Desktop, args: State.initial(notes: notes))
    assert %{cantica: :inferno, canto: 1} = assigns(runtime)

    click(runtime, "select:purgatorio:9")
    assert %{cantica: :purgatorio, canto: 9, status: "Purgatorio · Canto IX"} = assigns(runtime)

    command(runtime, "previous-canto")
    assert %{canto: 8} = assigns(runtime)

    state = State.initial() |> State.select(:inferno, 34) |> State.next_canto()
    assert {:purgatorio, 1} = {state.cantica, state.canto}
    assert %{cantica: :inferno, canto: 1} = State.initial() |> State.previous_canto()

    assert %{cantica: :paradiso, canto: 33} =
             State.initial() |> State.select(:paradiso, 33) |> State.next_canto()
  end

  test "the reader lists every tercet, toggles Italian and selects a tercet" do
    runtime = start_runtime!(DanteJournal.Desktop, args: State.initial())
    tree = View.render(assigns(runtime))
    assert GPUI.Tree.find!(tree, id: "reader-inferno-1")
    assert GPUI.Tree.find!(tree, id: "tercet-46")
    refute GPUI.Tree.find(tree, id: "tercet-47")

    click(runtime, "tercet:12")
    assert %{tercet: 12} = assigns(runtime)
    assert payload(runtime) =~ "Inf. 1.34–36"

    command(runtime, "toggle-italian")
    assert %{italian: true} = assigns(runtime)
    assert payload(runtime) =~ "Nel mezzo del cammin di nostra vita"
    assert payload(runtime) =~ "Midway upon the journey of our life"
  end

  test "a dictation becomes a form, is confirmed, saved, marked and deleted", %{notes: notes} do
    runtime =
      start_runtime!(DanteJournal.Desktop, args: State.initial(notes: notes, recorder: self()))

    command(runtime, "toggle-recording")
    refute_receive {:"$gen_cast", _}
    assert %{notice: "Transcription isn't ready."} = assigns(runtime)

    send_view(runtime, {:recorder, :ready})
    command(runtime, "toggle-recording")
    assert_receive {:"$gen_cast", {:start_recording, clip}}
    assert %{recording: %{phase: :arming}} = assigns(runtime)

    send_view(runtime, {:recorder, :started})
    send_view(runtime, {:recorder, {:partial, "In Canto 2"}})
    assert %{recording: %{phase: :recording, text: "In Canto 2"}} = assigns(runtime)
    assert GPUI.Tree.find!(View.render(assigns(runtime)), id: "recording-banner")

    File.write!(clip, "RIFF")

    send_view(
      runtime,
      {:recorder,
       {:stopped, %{text: "In Canto 2, stanza 12, Dante sees the leopard.", clip: clip, ms: 4200}}}
    )

    assert %{recording: nil, form: form} = assigns(runtime)
    assert form.anchor == %Anchor{cantica: :inferno, canto: 2, from_line: 34, to_line: 36}
    assert {form.type, form.how, form.phrase} == {:note, :spoken, "canto 2, stanza 12"}
    assert GPUI.Tree.find!(View.render(assigns(runtime)), id: "form-card")

    click(runtime, "form-type:question")
    # Without a native buffer the card falls back to a single-line input.
    change(runtime, "form-text", "In Canto 2, stanza 12, Dante sees the leopard, not a lion.")
    command(runtime, "form-save")
    state = assigns(runtime)
    assert state.form == nil
    assert {state.cantica, state.canto, state.tercet} == {:inferno, 2, 12}
    assert state.note_counts == %{{:inferno, 2} => 1}
    [note] = Notes.all(notes)

    assert %{
             type: :question,
             audio: "audio/" <> _,
             text: "In Canto 2, stanza 12, Dante sees the leopard, not a lion."
           } = note

    tree = View.render(state)
    assert GPUI.Tree.find!(tree, id: "marker-" <> note.id)
    assert GPUI.Tree.find!(tree, id: "note-" <> note.id)
    assert GPUI.Tree.find!(tree, id: "play-" <> note.id)

    click(runtime, "note-delete:" <> note.id)
    assert assigns(runtime).pending_delete == note.id
    click(runtime, "note-delete-confirm:" <> note.id)
    assert %{all_notes: [], note_counts: %{}} = assigns(runtime)
    assert Notes.all(notes) == []
  end

  test "typed notes, editing, re-anchoring by typing, and a silent transcript", %{notes: notes} do
    runtime =
      start_runtime!(DanteJournal.Desktop, args: State.initial(notes: notes, recorder: self()))

    send_view(runtime, {:recorder, :ready})

    click(runtime, "tercet:5")
    command(runtime, "new-note")

    assert %{
             form: %{
               how: :selection,
               source: :typed,
               anchor: %Anchor{from_line: 13, to_line: 15},
               text: ""
             }
           } = assigns(runtime)

    command(runtime, "form-save")
    assert %{notice: "The note is empty.", form: %{}} = assigns(runtime)

    change(runtime, "form-text", "Virgil arrives.")
    submit(runtime, "form-anchor-apply", "Purg. 9.70–72")

    assert %{
             form: %{
               anchor: %Anchor{cantica: :purgatorio, canto: 9, from_line: 70, to_line: 72},
               how: :chosen
             }
           } = assigns(runtime)

    submit(runtime, "form-anchor-apply", "nowhere at all")
    assert %{form: %{anchor_error: "Couldn't read" <> _}} = assigns(runtime)
    command(runtime, "form-save")
    state = assigns(runtime)
    assert {state.cantica, state.canto, state.tercet, state.form} == {:purgatorio, 9, 24, nil}
    [note] = Notes.all(notes)
    assert note.source == :typed and note.edited_at == nil

    click(runtime, "note-edit:" <> note.id)
    assert %{form: %{existing: %Note{}, text: "Virgil arrives."}} = assigns(runtime)
    change(runtime, "form-text", "Virgil arrives, finally.")
    click(runtime, "form-type:insight")
    command(runtime, "form-save")
    [edited] = Notes.all(notes)

    assert %{id: id, type: :insight, text: "Virgil arrives, finally.", edited_at: %DateTime{}} =
             edited

    assert id == note.id

    send_view(runtime, {:recorder, {:transcript, %{text: "   ", path: "/tmp/x.aiff"}}})
    assert %{form: nil, notice: "Nothing was heard."} = assigns(runtime)
  end

  test "the notes pane scopes, filters, searches and groups", %{notes: notes} do
    seed(notes, "a", :inferno, 1, 1, :question, "Why a leopard?")
    seed(notes, "b", :inferno, 1, 34, :insight, "The wood is midlife")

    seed(
      notes,
      "c",
      :inferno,
      5,
      100,
      :reference,
      "Francesca echoes Lancelot",
      ~U[2026-10-23 09:00:00Z]
    )

    seed(notes, "d", :paradiso, 33, 1, :quote, "Vergine madre")
    runtime = start_runtime!(DanteJournal.Desktop, args: State.initial(notes: notes))

    ids = fn -> State.visible_notes(assigns(runtime)) |> Enum.map(& &1.id) end
    assert ids.() == ["a", "b"]
    click(runtime, "scope:cantica")
    assert ids.() == ["a", "b", "c"]
    click(runtime, "scope:all")
    assert ids.() == ["a", "b", "c", "d"]

    click(runtime, "filter:question")
    click(runtime, "filter:quote")
    assert ids.() == ["a", "d"]
    click(runtime, "notes-clear-filters")
    change(runtime, "notes-query", "lancelot")
    assert ids.() == ["c"]
    change(runtime, "notes-query", "Par. 33")
    assert ids.() == ["d"]
    change(runtime, "notes-query", "")

    assert [
             {"inferno-1", "Inferno · Canto I", [_, _]},
             {"inferno-5", _, [_]},
             {"paradiso-33", _, [_]}
           ] = State.grouped_notes(assigns(runtime))

    click(runtime, "group:type")

    assert ["Question", "Insight", "Reference", "Quote"] =
             State.grouped_notes(assigns(runtime)) |> Enum.map(&elem(&1, 1))

    click(runtime, "group:day")

    assert ["2026-10-24", "2026-10-23"] =
             State.grouped_notes(assigns(runtime)) |> Enum.map(&elem(&1, 0))

    assert GPUI.Tree.find!(View.render(assigns(runtime)), id: "notes-shown")
  end

  test "the palette goes to a place or runs a command", %{notes: notes} do
    runtime = start_runtime!(DanteJournal.Desktop, args: State.initial(notes: notes))
    command(runtime, "open-palette")
    assert %{palette: true} = assigns(runtime)

    change(runtime, "palette-query", "purg 9.70")

    assert [%{label: "Go to Purgatorio · Canto IX, line 70"} | _] =
             State.choices(assigns(runtime))

    submit(runtime, "palette-submit", "purg 9.70")
    assert %{palette: false, cantica: :purgatorio, canto: 9, tercet: 24} = assigns(runtime)

    command(runtime, "open-palette")
    change(runtime, "palette-query", "italian")
    assert [%{event: "toggle-italian"}] = State.choices(assigns(runtime))
    change(runtime, "palette-pick", "choice-toggle-italian")
    assert %{palette: false, italian: true} = assigns(runtime)
  end

  test "the hold-to-talk key starts a dictation and a held release stops it", %{notes: notes} do
    runtime =
      start_runtime!(DanteJournal.Desktop, args: State.initial(notes: notes, recorder: self()))

    send_view(runtime, {:recorder, :ready})
    send_view(runtime, {:recorder, {:hotkey, {:listening, 61}}})
    assert %{hotkey_status: :listening} = assigns(runtime)
    assert payload(runtime) =~ "hold right ⌥ to talk"

    send_view(runtime, {:recorder, {:hotkey, :down}})
    assert_receive {:"$gen_cast", {:start_recording, _}}
    send_view(runtime, {:recorder, :started})
    # A quick tap keeps recording…
    send_view(runtime, {:recorder, {:hotkey, :up}})
    refute_receive {:"$gen_cast", :stop_recording}
    assert %{recording: %{}} = assigns(runtime)
    # …and a second press stops it, as does a held release.
    send_view(runtime, {:recorder, {:hotkey, :down}})
    assert_receive {:"$gen_cast", :stop_recording}

    send_view(runtime, {:recorder, {:hotkey, :denied}})

    assert %{hotkey_status: :denied, notice: "Hold-to-talk needs Input Monitoring" <> _} =
             assigns(runtime)

    click(runtime, "hotkey:0")
    assert_receive {:"$gen_cast", {:set_hotkey, nil}}
    assert %{hotkey: 0, hotkey_status: :off} = assigns(runtime)
  end

  test "theme tokens are resolved before the tree reaches a display" do
    tree = View.render(State.initial())
    refute inspect(tree, limit: :infinity) =~ ":theme"
    assert GPUI.Tree.find!(tree, id: "status")
  end
end

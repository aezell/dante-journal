defmodule DanteJournal.ViewTest do
  use GPUI.Test, async: true
  alias DanteJournal.{Anchor, Notes, State, View}

  setup do
    dir = Path.join(System.tmp_dir!(), "dante-view-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, notes} = Notes.start_link(dir: dir, name: nil)
    {:ok, notes: notes, dir: dir}
  end

  defp payload(runtime),
    do: View.render(assigns(runtime)) |> GPUI.Element.to_payload() |> inspect(limit: :infinity)

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

  test "a dictation becomes a draft, is confirmed, saved, marked and deleted", %{notes: notes} do
    runtime =
      start_runtime!(DanteJournal.Desktop, args: State.initial(notes: notes, recorder: self()))

    # Not ready yet: nothing starts.
    command(runtime, "toggle-recording")
    refute_receive {:"$gen_cast", _}
    assert %{notice: "Transcription isn't ready."} = assigns(runtime)

    send_view(runtime, {:recorder, :ready})
    command(runtime, "toggle-recording")
    assert_receive {:"$gen_cast", {:start_recording, clip}}
    assert String.ends_with?(clip, ".wav")
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

    assert %{recording: nil, draft: draft} = assigns(runtime)
    assert draft.anchor == %Anchor{cantica: :inferno, canto: 2, from_line: 34, to_line: 36}
    assert draft.type == :note
    assert draft.how == :spoken
    assert payload(runtime) =~ "Inf. 2.34–36"

    click(runtime, "draft-type:question")
    assert %{draft: %{type: :question}} = assigns(runtime)

    command(runtime, "draft-save")
    state = assigns(runtime)
    assert state.draft == nil
    assert {state.cantica, state.canto, state.tercet} == {:inferno, 2, 12}
    assert state.note_counts == %{{:inferno, 2} => 1}

    assert [%{type: :question, audio: "audio/" <> _, anchor_phrase: "canto 2, stanza 12"}] =
             state.canto_notes

    [note] = Notes.all(notes)
    tree = View.render(state)
    assert GPUI.Tree.find!(tree, id: "marker-" <> note.id)
    assert GPUI.Tree.find!(tree, id: "note-" <> note.id)

    click(runtime, "note-delete:" <> note.id)
    assert assigns(runtime).pending_delete == note.id
    click(runtime, "note-delete-confirm:" <> note.id)
    assert %{canto_notes: [], note_counts: %{}} = assigns(runtime)
    assert Notes.all(notes) == []
  end

  test "a transcript with no spoken anchor uses the selected tercet, and silence is reported", %{
    notes: notes
  } do
    runtime =
      start_runtime!(DanteJournal.Desktop, args: State.initial(notes: notes, recorder: self()))

    send_view(runtime, {:recorder, :ready})
    click(runtime, "tercet:5")

    send_view(
      runtime,
      {:recorder,
       {:transcript, %{text: "Why does Virgil appear so suddenly?", path: "/tmp/x.aiff"}}}
    )

    assert %{
             draft: %{
               how: :selection,
               type: :question,
               anchor: %Anchor{from_line: 13, to_line: 15}
             }
           } = assigns(runtime)

    click(runtime, "draft-anchor-canto")
    assert %{draft: %{how: :chosen, anchor: %Anchor{from_line: nil}}} = assigns(runtime)
    click(runtime, "draft-discard")
    assert %{draft: nil} = assigns(runtime)

    send_view(runtime, {:recorder, {:transcript, %{text: "   ", path: "/tmp/x.aiff"}}})
    assert %{draft: nil, notice: "Nothing was heard."} = assigns(runtime)
  end

  test "theme tokens are resolved before the tree reaches a display" do
    tree = View.render(State.initial())
    refute inspect(tree, limit: :infinity) =~ ":theme"
    assert GPUI.Tree.find!(tree, id: "status")
  end
end

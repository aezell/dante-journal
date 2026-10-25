defmodule DanteJournal.ModelViewTest do
  # Not async: the fake fm is global application configuration.
  use GPUI.Test, async: false
  alias DanteJournal.{Anchor, Notes, State, View}

  @fake Path.expand("support/fake_fm.sh", __DIR__)

  setup do
    Application.put_env(:dante_journal, :fm_binary, @fake)
    on_exit(fn -> Application.delete_env(:dante_journal, :fm_binary) end)
    start_supervised!({Task.Supervisor, name: DanteJournal.Tasks})
    dir = Path.join(System.tmp_dir!(), "dante-model-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, notes} = Notes.start_link(dir: dir, name: nil)
    runtime = start_runtime!(DanteJournal.Desktop, args: State.initial(notes: notes))
    send_view(runtime, {:configure, fm: true, fm_status: :ready, model_sink: {:runtime, runtime}})
    {:ok, runtime: runtime, notes: notes}
  end

  defp eventually(fun, tries \\ 40) do
    if fun.() or tries == 0,
      do: fun.(),
      else:
        (
          Process.sleep(50)
          eventually(fun, tries - 1)
        )
  end

  test "a dictation gets a type, title, tags and, when the parser found no lines, a place from the model",
       %{runtime: runtime} do
    send_view(
      runtime,
      {:recorder,
       {:transcript, %{text: "This echoes the Aeneid, book six.", path: "/tmp/a.aiff"}}}
    )

    assert %{form: %{pending: pending}} = assigns(runtime)
    assert MapSet.member?(pending, :classify) and MapSet.member?(pending, :locate)
    assert GPUI.Tree.find!(View.render(assigns(runtime)), id: "form-thinking")

    assert eventually(fn -> MapSet.size(assigns(runtime).form.pending) == 0 end)
    form = assigns(runtime).form

    assert {form.type, form.title, form.tags} ==
             {:reference, "Aeneas and the unburied", ["aeneid", "virgil"]}

    assert form.anchor.from_line == nil
    assert GPUI.Tree.find!(View.render(assigns(runtime)), id: "form-title")
    click(runtime, "form-discard")

    send_view(
      runtime,
      {:recorder,
       {:transcript,
        %{
          text: "So in the second canto of Purgatory, around the fourth stanza, Cato appears.",
          path: "/tmp/b.aiff"
        }}}
    )

    assert eventually(fn -> MapSet.size(assigns(runtime).form.pending) == 0 end)
    form = assigns(runtime).form
    assert %Anchor{cantica: :purgatorio, canto: 2, from_line: 10, to_line: 12} = form.anchor
    assert form.how == :model
    assert form.type == :insight
    click(runtime, "form-discard")
  end

  test "a type the reader chose survives the model's suggestion", %{runtime: runtime} do
    send_view(
      runtime,
      {:recorder,
       {:transcript, %{text: "Look up who Celestine the fifth was.", path: "/tmp/c.aiff"}}}
    )

    click(runtime, "form-type:quote")
    assert eventually(fn -> MapSet.size(assigns(runtime).form.pending) == 0 end)
    assert %{form: %{type: :quote, title: "Celestine the fifth"}} = assigns(runtime)
    click(runtime, "form-discard")
  end

  test "saved notes get a title and tags, and questions are answered with citations", %{
    runtime: runtime,
    notes: notes
  } do
    send_view(
      runtime,
      {:recorder,
       {:transcript, %{text: "Look up who Celestine the fifth was.", path: "/tmp/c.aiff"}}}
    )

    assert eventually(fn -> MapSet.size(assigns(runtime).form.pending) == 0 end)
    command(runtime, "form-save")
    [note] = Notes.all(notes)
    assert note.title == "Celestine the fifth" and note.tags == ["celestine", "popes"]
    assert GPUI.Tree.find!(View.render(assigns(runtime)), id: "note-" <> note.id <> "-title")

    click(runtime, "scope:all")
    submit(runtime, "ask", "Which notes mention a pope?")
    assert %{ask: %{pending: "Which notes mention a pope?"}} = assigns(runtime)
    assert GPUI.Tree.find!(View.render(assigns(runtime)), id: "ask-thinking")
    assert eventually(fn -> assigns(runtime).ask.pending == nil end)
    state = assigns(runtime)
    assert state.ask.answer == "Note [3] is about the heart. [1] is about death."
    assert state.ask.cited == [note.id]
    assert GPUI.Tree.find!(View.render(state), id: "answer-text")
    click(runtime, "note-focus:" <> note.id)
    assert %{focused_note: id} = assigns(runtime)
    assert id == note.id
    click(runtime, "ask-close")
    assert %{ask: %{answer: nil}} = assigns(runtime)

    send_view(runtime, {:fm, {:available, false}})
    assert %{fm: false, fm_status: :unavailable} = assigns(runtime)
    submit(runtime, "ask", "anything")
    assert %{notice: "The on-device model isn't available" <> _} = assigns(runtime)
  end
end

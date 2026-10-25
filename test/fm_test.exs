defmodule DanteJournal.FMTest do
  use ExUnit.Case, async: false
  alias DanteJournal.{Anchor, FM}

  @fake Path.expand("support/fake_fm.sh", __DIR__)

  setup do
    previous = Application.get_env(:dante_journal, :fm_binary)
    Application.put_env(:dante_journal, :fm_binary, @fake)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dante_journal, :fm_binary, previous),
        else: Application.delete_env(:dante_journal, :fm_binary)
    end)

    :ok
  end

  test "availability follows the binary" do
    assert FM.available?()
    Application.put_env(:dante_journal, :fm_binary, "/nonexistent/fm")
    refute FM.available?()
    assert {:error, "fm is not installed" <> _} = FM.respond("hi")
  end

  test "classification maps onto the note types" do
    assert {:ok,
            %{type: :reference, title: "Aeneas and the unburied", tags: ["aeneid", "virgil"]}} =
             FM.classify("This echoes the Aeneid, book six.")

    assert {:ok, %{type: :todo}} = FM.classify("Look up who Celestine the fifth was.")
    assert {:ok, %{type: :insight, tags: ["canned"]}} = FM.classify("Anything else.")
  end

  test "locating reads loose phrasing and drops impossible numbers" do
    here = %{cantica: :inferno, canto: 1}

    assert {:ok, %Anchor{cantica: :purgatorio, canto: 2, from_line: 10, to_line: 12}} =
             FM.locate(
               "So in the second canto of Purgatory, around the fourth stanza, Cato appears.",
               here
             )

    assert {:ok, %Anchor{cantica: :inferno, canto: 34, from_line: 133, to_line: 139}} =
             FM.locate("Right at the end of Inferno, canto thirty four, lines 133 to 139.", here)

    assert {:ok, nil} = FM.locate("I keep thinking the she-wolf is avarice.", here)
    assert {:ok, nil} = FM.locate("At line nine hundred of this canto.", here)
  end

  test "asking cites the numbered notes" do
    notes = [
      {1, "Inf. 1.7", "note", "bitter death", ["so bitter-death is hardly more severe!"]},
      {3, "Inf. 1.19–21", "question", "lake within my heart?", []}
    ]

    assert {:ok, "Note [3] is about the heart. [1] is about death."} =
             FM.ask("Which are about the body?", notes)
  end

  test "a slow model is cut off" do
    assert {:error, "fm took longer than 1 s"} = FM.respond("be slow please", timeout: 1_000)
  end
end

defmodule DanteJournal.ExportTest do
  use ExUnit.Case, async: true
  alias DanteJournal.{Anchor, Export}
  alias DanteJournal.Notes.Note

  defp note(id, cantica, canto, from, to, type, text) do
    %Note{
      id: id,
      anchor: %Anchor{cantica: cantica, canto: canto, from_line: from, to_line: to},
      type: type,
      text: text,
      anchor_phrase: "",
      recorded_at: ~U[2026-10-24 16:00:00Z]
    }
  end

  test "markdown quotes the anchored lines and orders by place" do
    notes = [
      note("z", :paradiso, 33, 1, 3, :quote, "Vergine madre"),
      note("a", :inferno, 1, 1, 3, :question, "Why a leopard?"),
      note("b", :inferno, 1, nil, nil, :summary, "The whole canto")
    ]

    md = Export.markdown(notes, :longfellow, "Test")
    assert md =~ "# Test"
    [_, inferno, paradiso] = String.split(md, "\n## ")
    assert inferno =~ "Inferno · Canto I"
    assert inferno =~ "### Inf. 1 · Summary"

    assert inferno =~
             "### Inf. 1.1–3 · Question\n> Midway upon the journey of our life\n> I found myself within a forest dark,\n> For the straightforward pathway had been lost.\n>\nWhy a leopard?"

    assert paradiso =~ "Par. 33.1–3 · Quote"

    txt = Export.text(notes, :longfellow, "Test")
    assert txt =~ "Inferno · Canto I\n===="
    assert txt =~ "    Midway upon the journey of our life"
  end
end

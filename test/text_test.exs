defmodule DanteJournal.TextTest do
  use ExUnit.Case, async: true
  alias DanteJournal.Text

  test "both bundled texts hold the whole poem, aligned line for line" do
    for text <- [:petrocchi, :longfellow] do
      counts =
        for cantica <- Text.cantiche(),
            canto <- 1..Text.canto_count(cantica),
            do: Text.line_count(text, cantica, canto)

      assert Enum.sum(counts) == 14_233
      assert Text.line_count(text, :inferno, 1) == 136
      assert Text.line_count(text, :paradiso, 33) == 145
    end

    assert Text.line(:petrocchi, :inferno, 1, 1) == "Nel mezzo del cammin di nostra vita"
    assert Text.line(:longfellow, :inferno, 1, 1) == "Midway upon the journey of our life"
  end

  test "tercets carry their line ranges" do
    tercets = Text.tercets(:longfellow, :inferno, 1)
    assert length(tercets) == 46
    assert %{number: 12, from: 34, to: 36, lines: [_, _, _]} = Enum.at(tercets, 11)
    assert %{number: 46, from: 136, to: 136, lines: [_]} = List.last(tercets)
  end

  test "Longfellow is the default English until Mandelbaum is imported" do
    assert Text.default_english() == :longfellow
    assert Text.available?(:petrocchi)
  end
end

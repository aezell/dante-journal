defmodule DanteJournal.AnchorTest do
  use ExUnit.Case, async: true
  alias DanteJournal.Anchor

  @here %{cantica: :inferno, canto: 1, tercet: nil}
  @selected %{cantica: :inferno, canto: 1, tercet: 5}

  test "a full spoken anchor overrides the reader position" do
    {anchor, phrase, :spoken} =
      Anchor.parse("Purgatorio, canto 9, stanza 24, the gate has three steps.", @here)

    assert anchor == %Anchor{cantica: :purgatorio, canto: 9, from_line: 70, to_line: 72}
    assert phrase == "purgatorio, canto 9, stanza 24"
    assert Anchor.label(anchor) == "Purg. 9.70–72"

    assert Anchor.strip_phrase(
             "Purgatorio, canto 9, stanza 24, the gate has three steps.",
             phrase
           ) == "The gate has three steps."
  end

  test "canto and stanza in the current cantica, with digits or words" do
    {anchor, _, :spoken} = Anchor.parse("In Canto 2, stanza 12, Dante sees the leopard.", @here)
    assert anchor == %Anchor{cantica: :inferno, canto: 2, from_line: 34, to_line: 36}

    {anchor, _, :spoken} = Anchor.parse("canto twenty-one tercet three, the devils", @here)
    assert anchor == %Anchor{cantica: :inferno, canto: 21, from_line: 7, to_line: 9}

    {anchor, _, :spoken} = Anchor.parse("Canto XXXIII. Ugolino.", @here)
    assert anchor == %Anchor{cantica: :inferno, canto: 33, from_line: nil, to_line: nil}
  end

  test "line ranges and single lines" do
    {anchor, _, :spoken} = Anchor.parse("Paradise canto 33 lines 1 to 3, Vergine madre", @here)
    assert anchor == %Anchor{cantica: :paradiso, canto: 33, from_line: 1, to_line: 3}

    {anchor, _, :spoken} = Anchor.parse("Hell, canto 3, line 9.", @here)
    assert anchor == %Anchor{cantica: :inferno, canto: 3, from_line: 9, to_line: 9}
    assert Anchor.label(anchor) == "Inf. 3.9"
  end

  test "a stanza alone stays in the current canto" do
    {anchor, _, :spoken} = Anchor.parse("stanza 4, the she-wolf", %{@here | canto: 7})
    assert anchor == %Anchor{cantica: :inferno, canto: 7, from_line: 10, to_line: 12}
  end

  test "nothing spoken falls back to the selected tercet, then the canto" do
    {anchor, "", :selection} = Anchor.parse("Why does Virgil appear so suddenly?", @selected)
    assert anchor == %Anchor{cantica: :inferno, canto: 1, from_line: 13, to_line: 15}

    {anchor, "", :position} = Anchor.parse("Why does Virgil appear so suddenly?", @here)
    assert anchor == %Anchor{cantica: :inferno, canto: 1, from_line: nil, to_line: nil}
    assert Anchor.label(anchor) == "Inf. 1"
  end

  test "impossible numbers are dropped instead of guessed" do
    {anchor, _, :spoken} = Anchor.parse("canto 99 stanza 2, nonsense", @here)
    assert anchor.canto == 1
    assert {anchor.from_line, anchor.to_line} == {4, 6}

    {anchor, _, :spoken} = Anchor.parse("canto 1 stanza 60, past the end", @selected)
    assert {anchor.from_line, anchor.to_line} == {13, 15}
  end

  test "number words become digits" do
    assert Anchor.number_words_to_digits("canto twenty-one stanza three") == "canto 21 stanza 3"
    assert Anchor.number_words_to_digits("line one hundred and twelve") == "line 112"
    assert Anchor.number_words_to_digits("one hundred forty five") == "145"
  end
end

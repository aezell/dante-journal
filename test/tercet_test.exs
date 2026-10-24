defmodule DanteJournal.TercetTest do
  use ExUnit.Case, async: true
  alias DanteJournal.Tercet

  test "lines map to tercets and the closing line stands alone" do
    assert Tercet.number_for_line(1) == 1
    assert Tercet.number_for_line(3) == 1
    assert Tercet.number_for_line(4) == 2
    assert Tercet.number_for_line(34) == 12
    assert Tercet.range(12, 136) == {34, 36}
    assert Tercet.count(136) == 46
    assert Tercet.range(46, 136) == {136, 136}
    assert Tercet.count(145) == 49
    assert_raise ArgumentError, fn -> Tercet.range(47, 136) end
  end

  test "labels and roman numerals" do
    assert Tercet.label(:inferno, 2, 34, 36) == "Inf. 2.34–36"
    assert Tercet.label(:paradiso, 33, 145, 145) == "Par. 33.145"
    assert Tercet.roman(1) == "I"
    assert Tercet.roman(4) == "IV"
    assert Tercet.roman(34) == "XXXIV"
    assert Tercet.from_roman("xxxiii") == 33
    assert Tercet.from_roman("IX") == 9
    assert Tercet.from_roman("IIII") == nil
    assert Tercet.from_roman("canto") == nil
    assert Tercet.cantica_from_word("Purgatory") == :purgatorio
    assert Tercet.cantica_from_word("hell") == :inferno
    assert Tercet.cantica_from_word("stanza") == nil
  end
end

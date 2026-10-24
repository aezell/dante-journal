defmodule DanteJournal.KeysTest do
  use ExUnit.Case, async: true
  import Bitwise
  alias DanteJournal.Keys

  test "chords encode to one integer and name themselves" do
    assert Keys.encode(30, 1) == 286
    assert Keys.decode(286) == {30, 1}
    assert Keys.name(286) == "⌘]"
    assert Keys.name(Keys.encode(105, 0)) == "F13"
    assert Keys.name(Keys.encode(49, 4 + 8)) == "⌃⇧space"
    assert Keys.name(61) == "right ⌥"
    assert Keys.name(-1) == "off"
    assert Keys.name(200) == "key 200"
  end

  test "quiet keys don't type into the app in front" do
    assert Keys.quiet?(61)
    assert Keys.quiet?(105)
    assert Keys.quiet?(286)
    refute Keys.quiet?(0)
    refute Keys.quiet?(Keys.encode(0, 8))
  end

  test "validity" do
    assert Keys.valid?(-1)
    assert Keys.valid?(0)
    assert Keys.valid?(Keys.encode(255, 31))
    refute Keys.valid?(-2)
    refute Keys.valid?(32 <<< 8 ||| 1)
    refute Keys.valid?("61")
  end
end

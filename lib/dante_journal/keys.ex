defmodule DanteJournal.Keys do
  @moduledoc """
  Hold-to-talk keys. A hotkey is one integer, `keycode ||| modifiers <<< 8`,
  so it travels unchanged through preferences, the palette and the helper's
  protocol. Modifier bits: ⌘ 1, ⌥ 2, ⌃ 4, ⇧ 8, fn 16. `-1` means off.
  """
  import Bitwise

  @names %{
    0 => "A",
    1 => "S",
    2 => "D",
    3 => "F",
    4 => "H",
    5 => "G",
    6 => "Z",
    7 => "X",
    8 => "C",
    9 => "V",
    11 => "B",
    12 => "Q",
    13 => "W",
    14 => "E",
    15 => "R",
    16 => "Y",
    17 => "T",
    18 => "1",
    19 => "2",
    20 => "3",
    21 => "4",
    22 => "6",
    23 => "5",
    24 => "=",
    25 => "9",
    26 => "7",
    27 => "-",
    28 => "8",
    29 => "0",
    30 => "]",
    31 => "O",
    32 => "U",
    33 => "[",
    34 => "I",
    35 => "P",
    36 => "return",
    37 => "L",
    38 => "J",
    39 => "'",
    40 => "K",
    41 => ";",
    42 => "\\",
    43 => ",",
    44 => "/",
    45 => "N",
    46 => "M",
    47 => ".",
    48 => "tab",
    49 => "space",
    50 => "`",
    51 => "delete",
    53 => "escape",
    54 => "right ⌘",
    55 => "left ⌘",
    56 => "left ⇧",
    57 => "caps lock",
    58 => "left ⌥",
    59 => "left ⌃",
    60 => "right ⇧",
    61 => "right ⌥",
    62 => "right ⌃",
    63 => "fn",
    64 => "F17",
    65 => "keypad .",
    67 => "keypad *",
    69 => "keypad +",
    71 => "clear",
    75 => "keypad /",
    76 => "keypad enter",
    78 => "keypad -",
    79 => "F18",
    80 => "F19",
    81 => "keypad =",
    82 => "keypad 0",
    83 => "keypad 1",
    84 => "keypad 2",
    85 => "keypad 3",
    86 => "keypad 4",
    87 => "keypad 5",
    88 => "keypad 6",
    89 => "keypad 7",
    90 => "F20",
    91 => "keypad 8",
    92 => "keypad 9",
    96 => "F5",
    97 => "F6",
    98 => "F7",
    99 => "F3",
    100 => "F8",
    101 => "F9",
    103 => "F11",
    105 => "F13",
    106 => "F16",
    107 => "F14",
    109 => "F10",
    111 => "F12",
    113 => "F15",
    114 => "help",
    115 => "home",
    116 => "page up",
    117 => "forward delete",
    118 => "F4",
    119 => "end",
    120 => "F2",
    121 => "page down",
    122 => "F1",
    123 => "←",
    124 => "→",
    125 => "↓",
    126 => "↑"
  }

  @modifiers [54, 55, 56, 58, 59, 60, 61, 62, 63]
  @bits [{1, "⌘"}, {2, "⌥"}, {4, "⌃"}, {8, "⇧"}, {16, "fn"}]

  @doc "`-1` means hold-to-talk is off; 0 is the A key."
  def off, do: -1

  def encode(code, modifiers) when code in 0..255 and modifiers in 0..31,
    do: code ||| modifiers <<< 8

  def decode(key) when is_integer(key) and key >= 0, do: {key &&& 0xFF, key >>> 8}

  def name(-1), do: "off"

  def name(key) when is_integer(key) do
    {code, modifiers} = decode(key)
    prefix = for {bit, glyph} <- @bits, (modifiers &&& bit) != 0, into: "", do: glyph
    prefix <> Map.get(@names, code, "key #{code}")
  end

  @doc """
  Whether the hotkey leaves the app in front alone: a modifier on its own, a
  function key, or a chord with ⌘ or ⌃ never types text. (A chord may still
  be a shortcut in that app.)
  """
  def quiet?(key) when is_integer(key) and key >= 0 do
    {code, modifiers} = decode(key)
    code in @modifiers or Map.get(@names, code, "") =~ ~r/^F\d+$/ or (modifiers &&& 5) != 0
  end

  def quiet?(_), do: true

  def valid?(key) when is_integer(key) do
    key == -1 or (key >= 0 and (key &&& 0xFF) in 0..255 and (key >>> 8) in 0..31)
  end

  def valid?(_), do: false
end

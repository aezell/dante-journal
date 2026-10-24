defmodule DanteJournal.Tercet do
  @moduledoc """
  Line and tercet arithmetic. A tercet `n` covers lines `3n-2..3n`; every
  canto ends with a single closing line, which stands as its own final unit.
  """

  @cantiche [:inferno, :purgatorio, :paradiso]
  @names %{inferno: "Inferno", purgatorio: "Purgatorio", paradiso: "Paradiso"}
  @abbreviations %{inferno: "Inf.", purgatorio: "Purg.", paradiso: "Par."}

  def cantiche, do: @cantiche
  def name(cantica), do: Map.fetch!(@names, cantica)
  def abbreviation(cantica), do: Map.fetch!(@abbreviations, cantica)

  @doc "The cantica an English or Italian spoken name refers to, if any."
  def cantica_from_word(word) when is_binary(word) do
    case word |> String.downcase() |> String.trim_trailing(".") do
      w when w in ["inferno", "inf", "hell"] -> :inferno
      w when w in ["purgatorio", "purg", "purgatory"] -> :purgatorio
      w when w in ["paradiso", "par", "paradise", "heaven"] -> :paradiso
      _ -> nil
    end
  end

  @doc "The tercet a line belongs to."
  def number_for_line(line) when is_integer(line) and line >= 1, do: div(line + 2, 3)

  @doc "How many units a canto of `line_count` lines has, counting the closing line."
  def count(line_count) when is_integer(line_count) and line_count >= 1,
    do: div(line_count + 2, 3)

  @doc "The `{from, to}` lines of tercet `n` in a canto of `line_count` lines."
  def range(n, line_count) when n >= 1 do
    from = 3 * n - 2
    to = min(3 * n, line_count)
    if from > line_count, do: raise(ArgumentError, "tercet #{n} is past line #{line_count}")
    {from, to}
  end

  @doc ~S|A compact anchor label such as "Inf. 2.34–36" or "Par. 33.145".|
  def label(cantica, canto, from, to) do
    lines = if from == to, do: "#{from}", else: "#{from}–#{to}"
    "#{abbreviation(cantica)} #{canto}.#{lines}"
  end

  @numerals [
    {1000, "M"},
    {900, "CM"},
    {500, "D"},
    {400, "CD"},
    {100, "C"},
    {90, "XC"},
    {50, "L"},
    {40, "XL"},
    {10, "X"},
    {9, "IX"},
    {5, "V"},
    {4, "IV"},
    {1, "I"}
  ]

  def roman(0), do: ""

  def roman(n) when is_integer(n) and n > 0 do
    {value, numeral} = Enum.find(@numerals, fn {value, _} -> value <= n end)
    numeral <> roman(n - value)
  end

  @doc "Parses a Roman numeral (any case); nil for anything else."
  def from_roman(string) when is_binary(string) do
    upper = String.upcase(string)

    if upper != "" and
         Regex.match?(~r/^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$/, upper) do
      upper
      |> String.graphemes()
      |> Enum.map(
        &Map.fetch!(
          %{"M" => 1000, "D" => 500, "C" => 100, "L" => 50, "X" => 10, "V" => 5, "I" => 1},
          &1
        )
      )
      |> Enum.reverse()
      |> Enum.reduce({0, 0}, fn value, {total, previous} ->
        if value < previous, do: {total - value, previous}, else: {total + value, value}
      end)
      |> elem(0)
    end
  end
end

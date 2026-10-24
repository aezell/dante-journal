defmodule DanteJournal.Anchor do
  @moduledoc """
  Where in the poem a note points: a cantica, a canto and optionally a line
  range. `parse/2` reads the spoken anchor at the start of a transcript
  ("Purgatorio, canto 9, stanza 24, …") and fills what wasn't said from the
  reader's current position.
  """
  alias DanteJournal.{Tercet, Text}

  # Words that may precede a spoken anchor without being part of it.
  @fillers "(?:(?:in|at|on|and|so|okay|ok|um|uh|well|then)\\s+)*"

  @enforce_keys [:cantica, :canto]
  defstruct [:cantica, :canto, :from_line, :to_line]

  @type t :: %__MODULE__{
          cantica: :inferno | :purgatorio | :paradiso,
          canto: pos_integer(),
          from_line: pos_integer() | nil,
          to_line: pos_integer() | nil
        }

  @doc "An anchor for a whole tercet of the given canto."
  def tercet(cantica, canto, n, line_count) do
    {from, to} = Tercet.range(n, line_count)
    %__MODULE__{cantica: cantica, canto: canto, from_line: from, to_line: to}
  end

  def label(%__MODULE__{from_line: nil} = a), do: "#{Tercet.abbreviation(a.cantica)} #{a.canto}"
  def label(%__MODULE__{} = a), do: Tercet.label(a.cantica, a.canto, a.from_line, a.to_line)

  @doc "The tercet number an anchor's first line falls in, or nil for a canto-level anchor."
  def tercet_number(%__MODULE__{from_line: nil}), do: nil
  def tercet_number(%__MODULE__{from_line: from}), do: Tercet.number_for_line(from)

  @doc """
  Parses the spoken anchor at the start of `text`.

  `current` is the reader position: `%{cantica:, canto:, tercet:}`, where
  `tercet` may be nil. Returns `{anchor, phrase, source}`: the anchor, the
  matched phrase (so views can hide it) and how it was resolved:
  `:spoken` (cantica or canto was said), `:selection` (only the selected
  tercet was used) or `:position` (nothing was said, nothing selected).
  Anything said that doesn't fit the poem is dropped rather than guessed.
  """
  def parse(text, %{cantica: cantica, canto: canto} = current) when is_binary(text) do
    normalized = text |> String.downcase() |> as_heard() |> number_words_to_digits()

    captures = Regex.named_captures(anchor_regex(), normalized) || %{}
    spoken? = Enum.any?(~w(cantica canto stanza from), &(Map.get(captures, &1, "") != ""))

    case spoken? and Regex.run(anchor_regex(), normalized) do
      [phrase | _] ->
        spoken_cantica = captures["cantica"] |> blank_to_nil() |> cantica_from()
        spoken_canto = captures["canto"] |> blank_to_nil() |> canto_from()

        cantica = spoken_cantica || cantica

        canto =
          if spoken_canto && spoken_canto in 1..Text.canto_count(cantica),
            do: spoken_canto,
            else: canto

        line_count = Text.line_count(:petrocchi, cantica, canto)

        {from, to} =
          lines_from(captures, line_count) || selected_lines(current, cantica, canto, line_count)

        {%__MODULE__{cantica: cantica, canto: canto, from_line: from, to_line: to},
         clean_phrase(phrase), :spoken}

      _nothing_spoken ->
        line_count = Text.line_count(:petrocchi, cantica, canto)

        case selected_lines(current, cantica, canto, line_count) do
          {nil, nil} ->
            {%__MODULE__{cantica: cantica, canto: canto}, "", :position}

          {from, to} ->
            {%__MODULE__{cantica: cantica, canto: canto, from_line: from, to_line: to}, "",
             :selection}
        end
    end
  end

  @doc "Strips the spoken anchor phrase and the connective after it from a transcript."
  def strip_phrase(text, ""), do: text

  def strip_phrase(text, phrase) do
    exact = ~r/^[\s,.:;—-]*#{@fillers}#{Regex.escape(phrase)}\s*[,.;:—-]*\s*/iu

    # The phrase comes from the normalised transcript ("canto 1, line 7"); the
    # note still reads as heard ("Encanto one, line 7"), so fall back to a
    # tolerant pattern built from the phrase's words.
    stripped =
      case Regex.replace(exact, text, "", global: false) do
        ^text -> Regex.replace(heard_pattern(phrase), text, "", global: false)
        other -> other
      end

    if String.trim(stripped) == "", do: text, else: upcase_first(stripped)
  end

  defp heard_pattern(phrase) do
    tokens =
      phrase
      |> String.split(~r/[\s,.:;—-]+/u, trim: true)
      |> Enum.map(fn
        "canto" ->
          "(?:en|in|un)?canto"

        "in" ->
          "(?:in|en|and)?"

        token ->
          if Regex.match?(~r/^\d+$/, token),
            do: "(?:\\d+|(?:[a-z]+[\\s-]*){1,4}?)",
            else: Regex.escape(token)
      end)

    ~r/^[\s,.:;—-]*#{@fillers}#{Enum.join(tokens, "[\\s,.:;—-]*")}\s*[,.;:—-]*\s*/iu
  end

  # Words the speech model runs together or mishears around an anchor:
  # "In Canto 1" comes back as "Encanto 1".
  defp as_heard(text) do
    text
    |> String.replace(~r/\b(?:en|in|un)canto\b/u, "in canto")
    |> String.replace(~r/\bcantos\b/u, "canto")
  end

  # -- Grammar -----------------------------------------------------------------

  @cantica_words "inferno|inf\\.?|hell|purgatorio|purg\\.?|purgatory|paradiso|par\\.?|paradise|heaven"
  @unit_words "stanza|stanzas|tercet|tercets|terzina|terzine|strophe"
  @line_words "lines|line|verses|verse|ll\\.|l\\."

  defp anchor_regex do
    ~r/
      ^[\s,.:;—-]*#{@fillers}
      (?:(?<cantica>#{@cantica_words})\b[\s,.:]*)?
      (?:(?:canto\s+|(?<=\b(?:inferno|inf|hell|purgatorio|purg|purgatory|paradiso|par|paradise|heaven)[.\s,:]{1,3}))(?<canto>[0-9]+|[ivxl]+)(?=[.\s,:]|$)(?:\.(?<from2>[0-9]+)(?:[–-](?<to2>[0-9]+))?)?\b[\s,.:]*)?
      (?:
        (?:(?:#{@unit_words})\s+(?<stanza>[0-9]+)\b)
        |
        (?:(?:#{@line_words})\s+(?<from>[0-9]+)(?:\s*(?:to|through|thru|-|–|and)\s*(?<to>[0-9]+))?\b)
      )?
    /xu
  end

  defp lines_from(%{"stanza" => stanza}, line_count) when stanza not in [nil, ""] do
    n = String.to_integer(stanza)
    if n in 1..Tercet.count(line_count), do: Tercet.range(n, line_count), else: nil
  end

  defp lines_from(%{"from" => from} = captures, line_count) when from not in [nil, ""],
    do: line_range(from, captures["to"], line_count)

  defp lines_from(%{"from2" => from} = captures, line_count) when from not in [nil, ""],
    do: line_range(from, captures["to2"], line_count)

  defp lines_from(_captures, _line_count), do: nil

  defp line_range(from, to, line_count) do
    from = String.to_integer(from)
    to = if to in [nil, ""], do: from, else: String.to_integer(to)
    if from in 1..line_count and to in from..line_count//1, do: {from, to}, else: nil
  end

  # The selected tercet only applies when the note stays in the reader's canto.
  defp selected_lines(%{cantica: c, canto: n, tercet: tercet}, c, n, line_count)
       when is_integer(tercet),
       do: Tercet.range(tercet, line_count)

  defp selected_lines(_current, _cantica, _canto, _line_count), do: {nil, nil}

  defp cantica_from(nil), do: nil
  defp cantica_from(word), do: Tercet.cantica_from_word(word)

  defp canto_from(nil), do: nil

  defp canto_from(token) do
    case Integer.parse(token) do
      {n, ""} -> n
      _ -> Tercet.from_roman(token)
    end
  end

  # The matched phrase without its leading connective or punctuation.
  defp clean_phrase(phrase),
    do:
      phrase
      |> String.trim()
      |> String.replace(~r/^[\s,.:;—-]*#{@fillers}/u, "")
      |> String.trim()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp upcase_first(other), do: other

  # -- Number words ------------------------------------------------------------
  # The on-device model usually emits digits, but "canto twenty-one" happens.

  @ones %{
    "zero" => 0,
    "one" => 1,
    "two" => 2,
    "three" => 3,
    "four" => 4,
    "five" => 5,
    "six" => 6,
    "seven" => 7,
    "eight" => 8,
    "nine" => 9,
    "ten" => 10,
    "eleven" => 11,
    "twelve" => 12,
    "thirteen" => 13,
    "fourteen" => 14,
    "fifteen" => 15,
    "sixteen" => 16,
    "seventeen" => 17,
    "eighteen" => 18,
    "nineteen" => 19
  }
  @tens %{
    "twenty" => 20,
    "thirty" => 30,
    "forty" => 40,
    "fifty" => 50,
    "sixty" => 60,
    "seventy" => 70,
    "eighty" => 80,
    "ninety" => 90
  }

  @doc false
  def number_words_to_digits(text) do
    Regex.replace(
      ~r/\b(?:(one\s+)?hundred(?:\s+(?:and\s+)?)?)?(?:(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[\s-]+(one|two|three|four|five|six|seven|eight|nine))?|(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen))\b|\bhundred\b/u,
      text,
      fn
        "hundred", _, _, _, _ ->
          "100"

        _whole, hundred, tens, ones, single ->
          base = if hundred != "", do: 100, else: 0

          value =
            cond do
              tens != "" ->
                base + Map.fetch!(@tens, tens) +
                  if ones == "", do: 0, else: Map.fetch!(@ones, ones)

              single != "" ->
                base + Map.fetch!(@ones, single)

              true ->
                base
            end

          Integer.to_string(value)
      end
    )
  end
end

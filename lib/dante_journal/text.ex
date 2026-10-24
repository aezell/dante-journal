defmodule DanteJournal.Text do
  @moduledoc """
  The poem. Bundled texts are loaded from `priv/texts` once and kept in
  `:persistent_term`; a Mandelbaum import in the user's data folder is picked
  up when present. Lines are addressed by `{cantica, canto, line}`.
  """
  alias DanteJournal.Tercet

  @bundled %{petrocchi: "petrocchi.json", longfellow: "longfellow.json"}
  @english [:mandelbaum, :longfellow]

  def cantiche, do: Tercet.cantiche()

  @doc "How many cantos a cantica has."
  def canto_count(:inferno), do: 34
  def canto_count(_), do: 33

  @doc "English translations installed, best first."
  def english_translations, do: Enum.filter(@english, &available?/1)

  @doc "The English translation to show by default."
  def default_english, do: List.first(english_translations())

  def translation_name(:petrocchi), do: "Petrocchi"
  def translation_name(:longfellow), do: "Longfellow"
  def translation_name(:mandelbaum), do: "Mandelbaum"

  def available?(text), do: text in Map.keys(@bundled) or File.exists?(imported_path(text))

  @doc "A canto's lines, in order."
  def lines(text, cantica, canto) when is_atom(text) and is_atom(cantica) and is_integer(canto) do
    text
    |> load()
    |> Map.fetch!(Tercet.name(cantica))
    |> Map.fetch!(Integer.to_string(canto))
  end

  def line_count(text, cantica, canto), do: length(lines(text, cantica, canto))

  def line(text, cantica, canto, n), do: Enum.at(lines(text, cantica, canto), n - 1)

  @doc "A canto grouped into tercets: `%{number, from, to, lines}`."
  def tercets(text, cantica, canto) do
    lines = lines(text, cantica, canto)
    total = length(lines)

    lines
    |> Enum.chunk_every(3)
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk, number} ->
      {from, to} = Tercet.range(number, total)
      %{number: number, from: from, to: to, lines: chunk}
    end)
  end

  @doc "The folder imports such as Mandelbaum live in."
  def data_dir do
    Path.join(:filename.basedir(:user_data, ~c"Dante Journal") |> to_string(), "texts")
  end

  def imported_path(text), do: Path.join(data_dir(), "#{text}.json")

  defp load(text) do
    case :persistent_term.get({__MODULE__, text}, nil) do
      nil ->
        data = text |> path!() |> File.read!() |> JSON.decode!()
        :persistent_term.put({__MODULE__, text}, data)
        data

      data ->
        data
    end
  end

  defp path!(text) do
    case Map.fetch(@bundled, text) do
      {:ok, file} -> Application.app_dir(:dante_journal, Path.join("priv/texts", file))
      :error -> imported_path(text)
    end
  end
end

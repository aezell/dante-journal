defmodule DanteJournal.Import.Mandelbaum do
  @moduledoc """
  Imports Allen Mandelbaum's translation for personal use from the University
  of Virginia's World of Dante, which publishes it canto by canto beside the
  Petrocchi Italian. The result is written to the user's data folder, never
  into this repository: the translation is in copyright.

  Each page holds one canto as a table of `line ital` / `line eng` cells with
  blank spacer rows between tercets. English lines are validated against the
  bundled Petrocchi line counts, and the page's own Italian is compared with
  Petrocchi as a second check on alignment.
  """
  alias DanteJournal.{Tercet, Text}

  @base "https://worldofdante.iath.virginia.edu/comedy/dante"
  # The site numbers cantiche 1–3 and names two of them in English.
  @cantica_paths %{
    inferno: {"inferno.xml", 1},
    purgatorio: {"purgatory.xml", 2},
    paradiso: {"paradise.xml", 3}
  }

  def url(cantica, canto) do
    {file, index} = Map.fetch!(@cantica_paths, cantica)
    "#{@base}/#{file}/#{index}.#{canto}"
  end

  @doc "Fetches, parses and validates every canto; returns `{:ok, text, warnings}`."
  def run(opts \\ []) do
    fetch = Keyword.get(opts, :fetch, &fetch/1)
    log = Keyword.get(opts, :log, fn _ -> :ok end)
    pause = Keyword.get(opts, :pause_ms, 400)

    result =
      Enum.reduce_while(Text.cantiche(), {:ok, %{}, []}, fn cantica, {:ok, acc, warnings} ->
        cantos = 1..Text.canto_count(cantica)

        Enum.reduce_while(cantos, {:ok, acc, warnings}, fn canto, {:ok, acc, warnings} ->
          log.("#{Tercet.name(cantica)} #{canto}")

          with {:ok, html} <- fetch.(url(cantica, canto)),
               {:ok, english, italian} <- parse(html),
               :ok <- validate(cantica, canto, english) do
            Process.sleep(pause)
            warnings = warnings ++ compare_italian(cantica, canto, italian)

            acc =
              Map.update(
                acc,
                Tercet.name(cantica),
                %{"#{canto}" => english},
                &Map.put(&1, "#{canto}", english)
              )

            {:cont, {:ok, acc, warnings}}
          else
            {:error, reason} -> {:halt, {:error, "#{Tercet.name(cantica)} #{canto}: #{reason}"}}
          end
        end)
        |> case do
          {:ok, _, _} = ok -> {:cont, ok}
          error -> {:halt, error}
        end
      end)

    with {:ok, text, warnings} <- result, do: {:ok, text, warnings}
  end

  @doc "Writes the imported text where `DanteJournal.Text` looks for it."
  def write(text, path \\ Text.imported_path(:mandelbaum)) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(text))
    path
  end

  @doc "The English and Italian lines of one canto page, blanks removed."
  def parse(html) when is_binary(html) do
    english = cells(html, "eng")
    italian = cells(html, "ital")

    if english == [] do
      {:error, "no English lines found on the page"}
    else
      {:ok, english, italian}
    end
  end

  defp cells(html, class) do
    ~r/<td class="line #{class}">(.*?)<\/td>/s
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [cell] -> cell |> strip_tags() |> decode_entities() |> squeeze() end)
    |> Enum.reject(&(&1 == ""))
  end

  defp validate(cantica, canto, english) do
    expected = Text.line_count(:petrocchi, cantica, canto)
    got = length(english)
    if got == expected, do: :ok, else: {:error, "expected #{expected} lines, found #{got}"}
  end

  # Petrocchi on the page and in our bundle should agree line for line, give or
  # take punctuation and accents; a word-level mismatch suggests a shifted line.
  defp compare_italian(cantica, canto, italian) do
    ours = Text.lines(:petrocchi, cantica, canto)

    if length(italian) != length(ours) do
      [
        "#{Tercet.name(cantica)} #{canto}: page has #{length(italian)} Italian lines, Petrocchi has #{length(ours)}"
      ]
    else
      italian
      |> Enum.zip(ours)
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {{theirs, mine}, n} ->
        if words(theirs) == words(mine) or similar?(theirs, mine),
          do: [],
          else: [
            "#{Tercet.abbreviation(cantica)} #{canto}.#{n}: page “#{theirs}” vs Petrocchi “#{mine}”"
          ]
      end)
    end
  end

  defp words(line),
    do: line |> String.downcase() |> String.replace(~r/[^\p{L}\s]/u, "") |> String.split()

  # Most of the two texts' differences are accents and apostrophes; compare the
  # first and last word shapes after folding diacritics.
  defp similar?(a, b) do
    fold = fn s -> s |> String.normalize(:nfd) |> String.replace(~r/\p{Mn}/u, "") |> words() end
    wa = fold.(a)
    wb = fold.(b)
    wa != [] and wb != [] and List.first(wa) == List.first(wb) and List.last(wa) == List.last(wb)
  end

  defp strip_tags(cell), do: Regex.replace(~r/<[^>]+>/, cell, "")

  @entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    "rsquo" => "’",
    "lsquo" => "‘",
    "rdquo" => "”",
    "ldquo" => "“",
    "mdash" => "—",
    "ndash" => "–",
    "hellip" => "…"
  }

  def decode_entities(text) do
    text
    |> then(
      &Regex.replace(~r/&#x([0-9a-fA-F]+);/, &1, fn _, hex ->
        <<String.to_integer(hex, 16)::utf8>>
      end)
    )
    |> then(
      &Regex.replace(~r/&#([0-9]+);/, &1, fn _, dec -> <<String.to_integer(dec)::utf8>> end)
    )
    |> then(
      &Regex.replace(~r/&([a-zA-Z]+);/, &1, fn whole, name -> Map.get(@entities, name, whole) end)
    )
  end

  defp squeeze(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  # -- HTTP --------------------------------------------------------------------

  def fetch(url) do
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    headers = [
      {~c"user-agent", ~c"DanteJournal/0.1 (personal reading journal; mix dante.import)"}
    ]

    case :httpc.request(:get, {String.to_charlist(url), headers}, [ssl: ssl, timeout: 30_000],
           body_format: :binary
         ) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, body}
      {:ok, {{_, status, _}, _, _}} -> {:error, "HTTP #{status} for #{url}"}
      {:error, reason} -> {:error, "#{inspect(reason)} for #{url}"}
    end
  end
end

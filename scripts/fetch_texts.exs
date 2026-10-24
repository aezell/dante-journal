# Fetches the public-domain texts the app bundles and normalises them into
# priv/texts/*.json. Run with: mix run scripts/fetch_texts.exs
#
# Source: https://github.com/gio-derosa/divine-comedy, which parses the
# Petrocchi Italian from it.wikisource.org and Longfellow's English from
# Project Gutenberg #1004 into one record per line. Its derived literal
# "translation" field is dropped; only the poem lines are kept.
#
# Output shape, one file per text:
#   %{"Inferno" => %{"1" => ["line 1", "line 2", ...], ...}, "Purgatorio" => ..., "Paradiso" => ...}

{:ok, _} = Application.ensure_all_started(:inets)
{:ok, _} = Application.ensure_all_started(:ssl)

base = "https://raw.githubusercontent.com/gio-derosa/divine-comedy/main/data/"
expected = %{"Inferno" => {34, 4720}, "Purgatorio" => {33, 4755}, "Paradiso" => {33, 4758}}

ssl = [
  verify: :verify_peer,
  cacerts: :public_key.cacerts_get(),
  depth: 4,
  customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
]

fetch = fn name ->
  url = String.to_charlist(base <> name <> ".json")

  {:ok, {{_, 200, _}, _headers, body}} =
    :httpc.request(:get, {url, []}, [ssl: ssl], body_format: :binary)

  JSON.decode!(body)
end

normalise = fn rows ->
  rows
  |> Enum.group_by(& &1["cantica"])
  |> Map.new(fn {cantica, lines} ->
    cantos =
      lines
      |> Enum.group_by(& &1["canto"])
      |> Map.new(fn {canto, canto_lines} ->
        ordered = Enum.sort_by(canto_lines, & &1["line_number"])
        numbers = Enum.map(ordered, & &1["line_number"])

        if numbers != Enum.to_list(1..length(ordered)),
          do: raise("#{cantica} #{canto}: line numbers are not contiguous")

        {Integer.to_string(canto), Enum.map(ordered, &String.trim(&1["text"]))}
      end)

    {cantica, cantos}
  end)
end

check = fn name, text ->
  for {cantica, {cantos, lines}} <- expected do
    got_cantos = map_size(text[cantica])
    got_lines = text[cantica] |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

    if {got_cantos, got_lines} != {cantos, lines},
      do:
        raise(
          "#{name} #{cantica}: expected #{cantos} cantos / #{lines} lines, got #{got_cantos} / #{got_lines}"
        )
  end
end

for name <- ["petrocchi", "longfellow"] do
  text = name |> fetch.() |> normalise.()
  check.(name, text)
  path = Path.join(["priv", "texts", name <> ".json"])
  File.write!(path, JSON.encode!(text))
  IO.puts("wrote #{path} (#{div(File.stat!(path).size, 1024)} KiB)")
end

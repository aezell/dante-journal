defmodule DanteJournal.ImportTest do
  use ExUnit.Case, async: true
  alias DanteJournal.Import.Mandelbaum

  @fixture File.read!(Path.expand("support/fixtures/uva_canto.html", __DIR__))

  test "urls follow the site's cantica index and English file names" do
    assert Mandelbaum.url(:inferno, 34) =~ "/inferno.xml/1.34"
    assert Mandelbaum.url(:purgatorio, 9) =~ "/purgatory.xml/2.9"
    assert Mandelbaum.url(:paradiso, 33) =~ "/paradise.xml/3.33"
  end

  test "parses English and Italian cells, dropping spacers, tags and entities" do
    assert {:ok, english, italian} = Mandelbaum.parse(@fixture)

    assert english == [
             "First made-up line & a symbol,",
             "second line with an entity’s curl,",
             "third line with tags and spaces.",
             "fourth line — dashed."
           ]

    assert italian == [
             "Nel mezzo del cammin di nostra vita",
             "mi ritrovai per una selva oscura,",
             "ché la diritta via era smarrita.",
             "Ahi quanto a dir qual era è cosa dura"
           ]

    assert {:error, _} = Mandelbaum.parse("<html></html>")
  end

  test "a run validates each canto's line count and stops on a short page" do
    fetch = fn _url -> {:ok, @fixture} end

    assert {:error, "Inferno 1: expected 136 lines, found 4"} =
             Mandelbaum.run(fetch: fetch, pause_ms: 0)
  end

  test "a run accepts pages whose counts match and reports Italian drift" do
    fetch = fn url ->
      [_, index, canto] = Regex.run(~r{/(?:inferno|purgatory|paradise)\.xml/([123])\.(\d+)$}, url)
      cantica = Enum.at([:inferno, :purgatorio, :paradiso], String.to_integer(index) - 1)
      canto = String.to_integer(canto)
      ours = DanteJournal.Text.lines(:petrocchi, cantica, canto)
      # The page's Italian is ours, except one deliberately shifted line in Inferno 3.
      italian =
        if {cantica, canto} == {:inferno, 3},
          do: List.replace_at(ours, 8, "una riga che non c'entra niente"),
          else: ours

      rows =
        Enum.map_join(italian, "\n", fn line ->
          ~s(<tr><td class="line ital">#{line}</td><td></td><td></td><td class="line eng">English for: #{line}</td></tr>)
        end)

      {:ok, "<table>" <> rows <> "</table>"}
    end

    assert {:ok, text, warnings} = Mandelbaum.run(fetch: fetch, pause_ms: 0)
    assert map_size(text) == 3
    assert text["Inferno"]["1"] |> length() == 136

    assert text["Paradiso"]["33"] |> List.last() ==
             "English for: " <> DanteJournal.Text.line(:petrocchi, :paradiso, 33, 145)

    assert [warning] = warnings
    assert warning =~ "Inf. 3.9"

    dir = Path.join(System.tmp_dir!(), "dante-import-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    path = Mandelbaum.write(text, Path.join(dir, "mandelbaum.json"))
    assert JSON.decode!(File.read!(path))["Inferno"]["1"] |> length() == 136
  end
end

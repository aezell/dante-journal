defmodule DanteJournal.Export do
  @moduledoc "Notes as Markdown or plain text, with the lines they point at."
  alias DanteJournal.{Anchor, Classifier, Tercet, Text}
  alias DanteJournal.Notes.Note

  @doc "The folder exports are written to."
  def dir, do: Path.join([System.user_home!(), "Documents", "Dante Journal"])

  def markdown(notes, english, title \\ "Dante Journal") do
    body =
      notes
      |> by_canto()
      |> Enum.map_join("\n", fn {{cantica, canto}, canto_notes} ->
        heading = "## #{Tercet.name(cantica)} · Canto #{Tercet.roman(canto)}\n"
        heading <> Enum.map_join(canto_notes, "\n", &markdown_note(&1, english))
      end)

    "# #{title}\n\n#{body}"
  end

  def text(notes, english, title \\ "Dante Journal") do
    body =
      notes
      |> by_canto()
      |> Enum.map_join("\n", fn {{cantica, canto}, canto_notes} ->
        heading =
          "#{Tercet.name(cantica)} · Canto #{Tercet.roman(canto)}\n#{String.duplicate("=", 40)}\n"

        heading <> Enum.map_join(canto_notes, "\n", &text_note(&1, english))
      end)

    "#{title}\n\n#{body}"
  end

  @doc "Writes content next to the user's documents and returns the path."
  def write(content, extension, slug) do
    File.mkdir_p!(dir())
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d-%H%M")
    path = Path.join(dir(), "#{slug}-#{stamp}.#{extension}")

    with :ok <- File.write(path, content), do: {:ok, path}
  end

  @doc "Shows a written file in the Finder."
  def reveal(path), do: System.cmd("open", ["-R", path])

  defp by_canto(notes) do
    notes
    |> Enum.group_by(&{&1.anchor.cantica, &1.anchor.canto})
    |> Enum.sort_by(fn {{cantica, canto}, _} ->
      {Enum.find_index(Tercet.cantiche(), &(&1 == cantica)), canto}
    end)
    |> Enum.map(fn {key, notes} ->
      {key, Enum.sort_by(notes, &{&1.anchor.from_line || 0, &1.id})}
    end)
  end

  defp markdown_note(%Note{} = note, english) do
    lines = quoted_lines(note.anchor, english) |> Enum.map_join("\n", &("> " <> &1))
    lines = if lines == "", do: "", else: lines <> "\n>\n"

    """
    ### #{Anchor.label(note.anchor)} · #{Classifier.label(note.type)}
    #{lines}#{Anchor.strip_phrase(note.text, note.anchor_phrase)}

    <sub>#{Calendar.strftime(note.recorded_at, "%Y-%m-%d %H:%M")} UTC#{if note.edited_at, do: ", edited", else: ""}</sub>
    """
  end

  defp text_note(%Note{} = note, english) do
    lines = quoted_lines(note.anchor, english) |> Enum.map_join("\n", &("    " <> &1))
    lines = if lines == "", do: "", else: lines <> "\n\n"

    """
    #{Anchor.label(note.anchor)} · #{Classifier.label(note.type)} · #{Calendar.strftime(note.recorded_at, "%Y-%m-%d %H:%M")}
    #{lines}#{Anchor.strip_phrase(note.text, note.anchor_phrase)}
    """
  end

  defp quoted_lines(%Anchor{from_line: nil}, _english), do: []

  defp quoted_lines(%Anchor{} = a, english) do
    lines = Text.lines(english, a.cantica, a.canto)
    Enum.slice(lines, (a.from_line - 1)..(a.to_line - 1)//1)
  end
end

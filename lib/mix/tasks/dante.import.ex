defmodule Mix.Tasks.Dante.Import do
  @shortdoc "Imports the Mandelbaum translation into your data folder"
  @moduledoc """
  Fetches Allen Mandelbaum's translation, canto by canto, from the University
  of Virginia's World of Dante and writes it to

      ~/Library/Application Support/Dante Journal/texts/mandelbaum.json

  for your personal use. The translation is in copyright and is never added
  to this repository. The reader prefers it over Longfellow once present.

      mix dante.import
      mix dante.import --check     # fetch and validate without writing

  Restart the app afterwards.
  """
  use Mix.Task
  alias DanteJournal.Import.Mandelbaum

  @impl true
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, strict: [check: :boolean])
    Mix.Task.run("app.config")

    Mix.shell().info(
      "Fetching 100 cantos from #{Mandelbaum.url(:inferno, 1) |> URI.parse() |> Map.get(:host)}…"
    )

    case Mandelbaum.run(log: &Mix.shell().info("  " <> &1)) do
      {:ok, text, warnings} ->
        Enum.each(warnings, &Mix.shell().info("  note: " <> &1))

        lines =
          text
          |> Map.values()
          |> Enum.flat_map(&Map.values/1)
          |> Enum.map(&length/1)
          |> Enum.sum()

        if opts[:check] do
          Mix.shell().info("Validated #{lines} lines; nothing written (--check).")
        else
          path = Mandelbaum.write(text)

          Mix.shell().info(
            "Wrote #{lines} lines to #{path}. Restart Dante Journal to read Mandelbaum."
          )
        end

      {:error, message} ->
        Mix.raise("Import stopped: #{message}")
    end
  end
end

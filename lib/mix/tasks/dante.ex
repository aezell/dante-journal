defmodule Mix.Tasks.Dante do
  @shortdoc "Opens the Dante Journal window"
  @moduledoc """
      mix dante
      mix dante --light
  """
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case DanteJournal.CLI.run(args) do
      :ok -> :ok
      {:error, message} -> Mix.raise(message)
    end
  end
end

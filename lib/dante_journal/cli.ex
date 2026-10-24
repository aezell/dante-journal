defmodule DanteJournal.CLI do
  @moduledoc """
  Starts the journal from command-line arguments and returns once its window
  closes. `mix dante` and the packaged app both start here.

  Options: --light
  """

  @switches [light: :boolean]

  @doc "The packaged app's entry point: runs, then exits with a status."
  def main(argv) do
    case run(argv) do
      :ok ->
        :ok

      {:error, message} ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end

  @doc "Runs the journal until its window closes."
  def run(argv) do
    with {:ok, opts} <- parse(argv),
         {:ok, _apps} <- Application.ensure_all_started(:dante_journal) do
      opts = Keyword.put(opts, :theme, if(opts[:light], do: :light, else: :dark))

      case DanteJournal.start(opts) do
        {:ok, supervisor} ->
          Process.unlink(supervisor)
          IO.puts("Dante Journal is open. Close the window to exit.")
          wait_for_close()
          Supervisor.stop(supervisor)

        {:error, reason} ->
          {:error, "Could not start Dante Journal: #{inspect(reason)}"}
      end
    else
      {:error, {app, reason}} -> {:error, "Could not start #{app}: #{inspect(reason)}"}
      {:error, message} -> {:error, message}
    end
  end

  # macOS passes a process serial number to apps opened from Finder on some
  # releases; it isn't an option of ours.
  defp parse(argv) do
    argv = Enum.reject(argv, &String.starts_with?(&1, "-psn_"))

    case OptionParser.parse(argv, strict: @switches) do
      {opts, [], []} -> {:ok, opts}
      _invalid -> {:error, "Invalid arguments. Options: --light"}
    end
  end

  defp wait_for_close do
    if GPUI.Runtime.windows(DanteJournal.Runtime) != [] do
      receive do
      after
        200 -> wait_for_close()
      end
    end
  end
end

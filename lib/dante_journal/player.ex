defmodule DanteJournal.Player do
  @moduledoc "Plays a note's clip with macOS `afplay`; one clip at a time."
  use GenServer

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def play(server, id, path), do: GenServer.cast(server, {:play, id, path})
  def stop(server), do: GenServer.cast(server, :stop)

  @impl true
  def init(opts), do: {:ok, %{sink: Keyword.fetch!(opts, :sink), port: nil, id: nil}}

  @impl true
  def handle_cast({:play, id, path}, state) do
    state = halt(state)

    if File.exists?(path) and File.exists?("/usr/bin/afplay") do
      port =
        Port.open({:spawn_executable, "/usr/bin/afplay"}, [:binary, :exit_status, args: [path]])

      notify(state, {:playing, id})
      {:noreply, %{state | port: port, id: id}}
    else
      notify(state, {:error, "No audio clip for this note."})
      {:noreply, state}
    end
  end

  def handle_cast(:stop, state), do: {:noreply, halt(state)}

  @impl true
  def handle_info({port, {:exit_status, _}}, %{port: port} = state) do
    notify(state, :stopped)
    {:noreply, %{state | port: nil, id: nil}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp halt(%{port: nil} = state), do: state

  defp halt(%{port: port} = state) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> System.cmd("kill", [Integer.to_string(pid)])
      _ -> :ok
    end

    notify(state, :stopped)
    %{state | port: nil, id: nil}
  end

  defp notify(%{sink: {:runtime, runtime}}, event),
    do: GPUI.Runtime.send_view(runtime, 1, {:player, event})

  defp notify(%{sink: {:pid, pid}}, event), do: send(pid, {:player, event})
end

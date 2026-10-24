defmodule DanteJournal.Recorder do
  @moduledoc """
  Owns the `dante-ear` helper process. Starts and stops dictations, relays
  the helper's partial and final transcripts to the view, stops a dictation
  on its own after a silence, and restarts the helper if it dies.

  Events reach the view as `{:recorder, event}`:

      :ready | {:unavailable, reason} | :started | {:partial, text} | {:tick, ms}
      | {:stopped, %{text: text, clip: path, ms: ms}} | {:transcript, %{text: text, path: path}}
      | {:hotkey, :down | :up | {:listening, key} | {:learned, key} | :denied} | {:error, message}
  """
  use GenServer
  require Logger

  @restart_after 5_000

  # -- Client ------------------------------------------------------------------

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "The helper binary a packaged or development build runs."
  def default_binary, do: Application.app_dir(:dante_journal, "priv/bin/dante-ear")

  def start_recording(server, clip_path),
    do: GenServer.cast(server, {:start_recording, clip_path})

  def stop_recording(server), do: GenServer.cast(server, :stop_recording)
  @doc "Transcribes an audio file instead of the microphone; emits `{:transcript, ...}`."
  def transcribe_file(server, path), do: GenServer.cast(server, {:transcribe_file, path})
  def status(server), do: GenServer.call(server, :status)
  @doc "Watches a key system-wide for hold-to-talk; `nil` stops watching."
  def set_hotkey(server, key), do: GenServer.cast(server, {:set_hotkey, key})
  @doc "Asks the helper to report the next key pressed, as `{:hotkey, {:learned, key}}`."
  def learn_hotkey(server), do: GenServer.cast(server, :learn_hotkey)
  @doc "How long a pause ends a dictation, in ms; 0 never."
  def set_silence(server, ms), do: GenServer.cast(server, {:set_silence, ms})
  @doc "Plays a clip through the helper; events arrive as `{:player, ...}`."
  def play(server, id, path), do: GenServer.cast(server, {:play, id, path})
  def stop_playback(server), do: GenServer.cast(server, :stop_playback)

  # -- Server ------------------------------------------------------------------

  @impl true
  def init(opts) do
    state = %{
      binary: Keyword.get(opts, :binary, default_binary()),
      sink: Keyword.fetch!(opts, :sink),
      # 0 disables the pause cutoff; the idle rule and max duration still apply.
      silence_ms: Keyword.get(opts, :silence_ms, 6_000),
      max_ms: Keyword.get(opts, :max_ms, 180_000),
      # Give up when nothing at all has been heard for this long.
      idle_ms: Keyword.get(opts, :idle_ms, 15_000),
      port: nil,
      phase: :starting,
      text: "",
      started_at: nil,
      silence_timer: nil,
      max_timer: nil,
      tick_timer: nil,
      buffer: "",
      hotkey: Keyword.get(opts, :hotkey),
      playing: nil
    }

    {:ok, open(state)}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.phase, state}

  @impl true
  def handle_cast({:start_recording, clip}, %{phase: :idle} = state) do
    command(state, %{cmd: "start", clip: clip})
    {:noreply, %{state | phase: :arming, text: ""}}
  end

  def handle_cast({:start_recording, _clip}, state) do
    notify(state, {:error, reason_for(state.phase)})
    {:noreply, state}
  end

  def handle_cast(:stop_recording, %{phase: phase} = state) when phase in [:recording, :arming] do
    command(state, %{cmd: "stop"})
    {:noreply, %{cancel_timers(state) | phase: :stopping}}
  end

  def handle_cast(:stop_recording, state), do: {:noreply, state}

  def handle_cast({:transcribe_file, path}, %{phase: :idle} = state) do
    command(state, %{cmd: "file", path: path})
    {:noreply, %{state | phase: :transcribing, text: ""}}
  end

  def handle_cast({:transcribe_file, _path}, state) do
    notify(state, {:error, reason_for(state.phase)})
    {:noreply, state}
  end

  def handle_cast({:play, id, path}, state) do
    if (state.port && state.phase not in [:starting, :restarting, :unavailable]) and
         File.exists?(path) do
      command(state, %{cmd: "play", path: path})
      {:noreply, %{state | playing: id}}
    else
      notify_player(state, {:error, "No audio clip for this note."})
      {:noreply, state}
    end
  end

  def handle_cast(:stop_playback, state) do
    command(state, %{cmd: "stopplay"})
    {:noreply, state}
  end

  def handle_cast({:set_silence, ms}, state) when is_integer(ms) and ms >= 0,
    do: {:noreply, %{state | silence_ms: ms}}

  def handle_cast(:learn_hotkey, state) do
    if state.phase in [:starting, :restarting, :unavailable],
      do: notify(state, {:error, reason_for(state.phase)}),
      else: command(state, %{cmd: "learn"})

    {:noreply, state}
  end

  def handle_cast({:set_hotkey, key}, state) do
    state = %{state | hotkey: key}

    if state.phase not in [:starting, :restarting, :unavailable],
      do: command(state, %{cmd: "hotkey", key: key || 0})

    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    line = state.buffer <> line

    state =
      case JSON.decode(line) do
        {:ok, %{"event" => _} = event} -> handle_event(event, %{state | buffer: ""})
        _ -> %{state | buffer: ""}
      end

    {:noreply, state}
  end

  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state),
    do: {:noreply, %{state | buffer: state.buffer <> chunk}}

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("dante-ear exited with status #{status}; restarting in #{@restart_after} ms")

    notify(
      state,
      {:unavailable, "The transcription helper stopped (status #{status}); restarting."}
    )

    Process.send_after(self(), :reopen, @restart_after)
    {:noreply, %{cancel_timers(state) | port: nil, phase: :restarting}}
  end

  def handle_info(:reopen, state), do: {:noreply, open(state)}

  def handle_info(:silence, %{phase: :recording} = state) do
    heard = state.text != ""

    cond do
      heard and state.silence_ms > 0 ->
        command(state, %{cmd: "stop"})
        {:noreply, %{cancel_timers(state) | phase: :stopping}}

      not heard and elapsed(state) >= state.idle_ms ->
        command(state, %{cmd: "stop"})
        {:noreply, %{cancel_timers(state) | phase: :stopping}}

      true ->
        {:noreply, %{state | silence_timer: schedule(:silence, silence_interval(state))}}
    end
  end

  def handle_info(:max_duration, %{phase: :recording} = state) do
    command(state, %{cmd: "stop"})
    {:noreply, %{cancel_timers(state) | phase: :stopping}}
  end

  def handle_info(:tick, %{phase: :recording} = state) do
    notify(state, {:tick, elapsed(state)})
    {:noreply, %{state | tick_timer: schedule(:tick, 1_000)}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  # -- Helper events -----------------------------------------------------------

  defp handle_event(%{"event" => "ready"}, state) do
    notify(state, :ready)
    if state.hotkey, do: command(state, %{cmd: "hotkey", key: state.hotkey})
    %{state | phase: :idle}
  end

  defp handle_event(%{"event" => "play"} = event, state) do
    case event do
      %{"state" => "started"} ->
        notify_player(state, {:playing, state.playing})

      %{"state" => "finished"} ->
        notify_player(state, :stopped)

      %{"state" => "failed"} ->
        notify_player(state, {:error, "Couldn't play the clip: #{event["message"]}"})

      _ ->
        :ok
    end

    if event["state"] in ["finished", "failed"], do: %{state | playing: nil}, else: state
  end

  defp handle_event(%{"event" => "hotkey"} = event, state) do
    case event do
      %{"state" => "down"} -> notify(state, {:hotkey, :down})
      %{"state" => "up"} -> notify(state, {:hotkey, :up})
      %{"status" => "listening", "key" => key} -> notify(state, {:hotkey, {:listening, key}})
      %{"status" => "denied"} -> notify(state, {:hotkey, :denied})
      %{"learned" => key} when is_integer(key) -> notify(state, {:hotkey, {:learned, key}})
      _ -> :ok
    end

    state
  end

  defp handle_event(%{"event" => "started"}, state) do
    notify(state, :started)

    %{
      state
      | phase: :recording,
        started_at: System.monotonic_time(:millisecond),
        silence_timer: schedule(:silence, silence_interval(state)),
        max_timer: schedule(:max_duration, state.max_ms),
        tick_timer: schedule(:tick, 1_000)
    }
  end

  defp handle_event(%{"event" => "partial", "text" => text}, %{phase: :recording} = state) do
    notify(state, {:partial, text})
    state = cancel(state, :silence_timer)
    %{state | text: text, silence_timer: schedule(:silence, silence_interval(state))}
  end

  defp handle_event(%{"event" => "partial", "text" => text}, state) do
    notify(state, {:partial, text})
    %{state | text: text}
  end

  defp handle_event(%{"event" => "stopped"} = event, state) do
    notify(
      state,
      {:stopped,
       %{text: event["text"] || "", clip: event["clip"], ms: event["ms"] || elapsed(state)}}
    )

    %{cancel_timers(state) | phase: :idle, text: "", started_at: nil}
  end

  defp handle_event(%{"event" => "transcript"} = event, state) do
    notify(state, {:transcript, %{text: event["text"] || "", path: event["path"]}})
    %{state | phase: :idle, text: ""}
  end

  defp handle_event(%{"event" => "error", "message" => message}, state) do
    Logger.warning("dante-ear: #{message}")
    notify(state, {:error, message})
    # A failed start or stop leaves the helper idle.
    phase = if state.phase in [:arming, :stopping, :transcribing], do: :idle, else: state.phase
    %{cancel_timers(state) | phase: phase}
  end

  defp handle_event(%{"event" => "log", "message" => message}, state) do
    Logger.info("dante-ear: #{message}")
    state
  end

  defp handle_event(_unknown, state), do: state

  # -- Port --------------------------------------------------------------------

  defp open(state) do
    if File.exists?(state.binary) do
      port =
        Port.open({:spawn_executable, state.binary}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          {:line, 65_536}
        ])

      %{state | port: port, phase: :starting, buffer: ""}
    else
      notify(
        state,
        {:unavailable, "Transcription helper not built. Run native/dante-ear/build.sh."}
      )

      %{state | port: nil, phase: :unavailable}
    end
  end

  defp command(%{port: port}, map) when is_port(port),
    do: Port.command(port, JSON.encode!(map) <> "\n")

  defp command(_state, _map), do: :ok

  defp notify(%{sink: {:runtime, runtime}}, event),
    do: GPUI.Runtime.send_view(runtime, 1, {:recorder, event})

  defp notify(%{sink: {:pid, pid}}, event), do: send(pid, {:recorder, event})

  defp notify_player(%{sink: {:runtime, runtime}}, event),
    do: GPUI.Runtime.send_view(runtime, 1, {:player, event})

  defp notify_player(%{sink: {:pid, pid}}, event), do: send(pid, {:player, event})

  defp reason_for(:unavailable), do: "The transcription helper isn't available."
  defp reason_for(:starting), do: "The transcription helper is still starting."
  defp reason_for(:restarting), do: "The transcription helper is restarting."
  defp reason_for(_busy), do: "Already recording."

  defp elapsed(%{started_at: nil}), do: 0
  defp elapsed(%{started_at: at}), do: System.monotonic_time(:millisecond) - at

  # With the pause cutoff off, keep polling for the idle rule.
  defp silence_interval(%{silence_ms: 0}), do: 1_000
  defp silence_interval(%{silence_ms: ms}), do: ms

  defp schedule(message, ms), do: Process.send_after(self(), message, ms)

  defp cancel(state, key) do
    if timer = Map.get(state, key), do: Process.cancel_timer(timer)
    Map.put(state, key, nil)
  end

  defp cancel_timers(state),
    do: state |> cancel(:silence_timer) |> cancel(:max_timer) |> cancel(:tick_timer)
end
